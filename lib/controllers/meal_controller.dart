import 'dart:async' show unawaited;
import 'dart:convert' show base64Encode;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/food_item.dart';
import '../models/meal_log.dart';
import '../services/analytics_service.dart';
import 'challenge_controller.dart' show myChallengesProvider;
import 'known_meal_controller.dart' show knownMealControllerProvider;
import 'log_controller.dart' show notifyChallenges;

// Top-level function required by compute() — runs in a background isolate.
// Decodes bytes, resizes so the longest side ≤ 1024 px, re-encodes at 85% JPEG.
// Returns the compressed bytes OR the original bytes if decoding fails.
//
// Memory note: the isolate receives a COPY of rawBytes (Dart isolate
// semantics). To limit peak usage we:
//   1. Immediately null the decoded image reference once resizing is done so
//      the GC can reclaim it before we build the output list.
//   2. Cap the output at 1024 px — at medium camera preset the image is
//      already 1280×720, so the resize is always a shrink, never an expand.
Uint8List _compressImageIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final img.Image resized;
  if (decoded.width > 1024 || decoded.height > 1024) {
    resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: 1024)
        : img.copyResize(decoded, height: 1024);
  } else {
    resized = decoded;
  }

  // encodeJpg creates a new List<int>; wrap in Uint8List so the transfer
  // back to the main isolate avoids an extra copy.
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}

enum MealProcessingStep { idle, uploading, analysing, review, saving, saved }

class MealState {
  final MealProcessingStep step;
  final String? imageUrl;
  final List<FoodItem> items;
  final int totalCalories;
  final String? error;
  /// The database ID of the meal log after a successful save.
  /// Non-null only when step == MealProcessingStep.saved.
  /// Used by the caller (AddFoodSheet) to open the mood-rating sheet for
  /// the correct log without a second round-trip to fetch it.
  final String? savedLogId;

  const MealState({
    this.step = MealProcessingStep.idle,
    this.imageUrl,
    this.items = const [],
    this.totalCalories = 0,
    this.error,
    this.savedLogId,
  });

  bool get isProcessing =>
      step == MealProcessingStep.uploading ||
      step == MealProcessingStep.analysing;

  // Review content should stay visible during saving so the "Saving…"
  // button spinner is shown rather than flashing an empty dark sheet.
  bool get isReady =>
      step == MealProcessingStep.review ||
      step == MealProcessingStep.saving;

  /// Human-readable label for the current processing step.
  String get stepLabel => switch (step) {
        MealProcessingStep.uploading => 'Uploading photo…',
        MealProcessingStep.analysing => 'Identifying food…',
        MealProcessingStep.saving => 'Saving meal…',
        _ => '',
      };

  MealState copyWith({
    MealProcessingStep? step,
    String? imageUrl,
    List<FoodItem>? items,
    int? totalCalories,
    String? error,
    String? savedLogId,
  }) =>
      MealState(
        step: step ?? this.step,
        imageUrl: imageUrl ?? this.imageUrl,
        items: items ?? this.items,
        totalCalories: totalCalories ?? this.totalCalories,
        error: error,
        savedLogId: savedLogId ?? this.savedLogId,
      );
}

class MealController extends Notifier<MealState> {
  @override
  MealState build() => const MealState();

  /// Full pipeline: compress image → upload → call edge function → parse result → review state.
  Future<void> analyseCapture(File imageFile) async {
    final client = Supabase.instance.client;

    // Use currentSession (not just currentUser) — currentUser can be non-null
    // even when the JWT is expired. We need a live session to call the function.
    final session = client.auth.currentSession;
    final userId = session?.user.id;

    if (userId == null || session == null) {
      state = state.copyWith(
        step: MealProcessingStep.idle,
        error: 'Session expired — please sign out and sign back in.',
      );
      return;
    }

    // — Step 1: Upload (with client-side compression) —
    state = state.copyWith(step: MealProcessingStep.uploading, error: null);

    try {
      // Compress in a background isolate — avoids main-thread jank on large
      // phone photos (10–20 MB). Resizes longest side to ≤ 1024 px at 85% JPEG.
      final rawBytes = await imageFile.readAsBytes();
      final compressedBytes = await compute(_compressImageIsolate, rawBytes);
      final uploadFile = await File(
        '${imageFile.parent.path}/c_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ).writeAsBytes(compressedBytes);

      final fileName =
          '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

      try {
        await client.storage.from('meal-images').upload(
              fileName,
              uploadFile,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
      } catch (e) {
        throw Exception('Upload failed — have you run the SQL migration?\n$e');
      } finally {
        // Delete both temp files regardless of upload outcome to avoid
        // accumulating compressed copies in the app's cache directory.
        // Silently swallow errors — temp files not cleaning up is non-fatal.
        // catchError must return FileSystemEntity to satisfy the generic type.
        unawaited(uploadFile.delete().catchError((_) => uploadFile));
        unawaited(imageFile.delete().catchError((_) => imageFile));
      }

      final imageUrl =
          client.storage.from('meal-images').getPublicUrl(fileName);

      // — Step 2: Analyse —
      state = state.copyWith(
        step: MealProcessingStep.analysing,
        imageUrl: imageUrl,
      );

      late final dynamic response;
      try {
        response = await client.functions.invoke(
          'analyse-meal',
          body: {'image_url': imageUrl},
          // Explicitly pass the JWT — avoids race conditions where the
          // client hasn't yet attached a refreshed token automatically.
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        );
      } catch (e) {
        throw Exception(
            'Edge function unreachable — is "analyse-meal" deployed?\n$e');
      }

      if (response.status != 200) {
        final body = response.data?.toString() ?? 'no body';
        throw Exception(
            'Edge function error (HTTP ${response.status}) — check OpenAI key is set as secret.\nResponse: $body');
      }

      final data = response.data as Map<String, dynamic>;

      if (data['items'] == null) {
        throw Exception('AI returned no items. Raw: $data');
      }

      final items = (data['items'] as List<dynamic>)
          .map((e) => FoodItem.fromMap(e as Map<String, dynamic>))
          .toList();

      final totalCalories =
          (data['total_calories'] as num?)?.toInt() ??
              items.fold<int>(0, (s, i) => s + i.calories);

      // — Step 3: Review —
      state = state.copyWith(
        step: MealProcessingStep.review,
        items: items,
        totalCalories: totalCalories,
      );
    } catch (e) {
      state = state.copyWith(
        step: MealProcessingStep.idle,
        error: e.toString(),
      );
    }
  }

  /// Nutrition label scanner pipeline: compress → base64 → scan-label edge fn → review.
  ///
  /// Unlike [analyseCapture], label scans do not upload to Storage — the image
  /// is sent as base64 directly to avoid cluttering the meal-images bucket.
  /// The result is a single [FoodItem] pre-populated with printed values.
  Future<void> analyseLabel(File imageFile) async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final userId = session?.user.id;

    if (userId == null || session == null) {
      state = state.copyWith(
        step: MealProcessingStep.idle,
        error: 'Session expired — please sign out and sign back in.',
      );
      return;
    }

    state = state.copyWith(step: MealProcessingStep.analysing, error: null);

    try {
      final rawBytes = await imageFile.readAsBytes();
      final compressedBytes = await compute(_compressImageIsolate, rawBytes);

      // Delete the original file after reading — label photos don't need
      // to persist on device once the bytes are in memory.
      unawaited(imageFile.delete().catchError((_) => imageFile));

      final imageBase64 = base64Encode(compressedBytes);

      late final dynamic response;
      try {
        response = await client.functions.invoke(
          'scan-label',
          body: {'image_base64': imageBase64, 'mime_type': 'image/jpeg'},
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        );
      } catch (e) {
        throw Exception(
            'Edge function unreachable — is "scan-label" deployed?\n$e');
      }

      if (response.status != 200) {
        final body = response.data?.toString() ?? 'no body';
        throw Exception(
            'scan-label error (HTTP ${response.status})\nResponse: $body');
      }

      final data = response.data as Map<String, dynamic>;

      final item = FoodItem.fromMap(data);

      // Surface a user-friendly error when the label was unreadable.
      if (item.calories == 0 &&
          (data['confidence'] as num? ?? 1.0) < 0.2) {
        throw Exception(
            'Could not read the label — try a clearer, better-lit photo.');
      }

      state = state.copyWith(
        step: MealProcessingStep.review,
        items: [item],
        totalCalories: item.calories,
      );
    } catch (e) {
      state = state.copyWith(
        step: MealProcessingStep.idle,
        error: e.toString(),
      );
    }
  }

  /// Called from the review UI when the user edits a food item.
  void updateItem(int index, FoodItem updated) {
    final items = List<FoodItem>.from(state.items);
    items[index] = updated;
    state = state.copyWith(
      items: items,
      totalCalories: items.fold<int>(0, (s, i) => s + i.calories),
    );
  }

  /// Called from the review UI's "+ Add item" button.
  /// Appends a manually entered item and recalculates the total.
  void addItem(FoodItem item) {
    final items = List<FoodItem>.from(state.items)..add(item);
    state = state.copyWith(
      items: items,
      totalCalories: items.fold<int>(0, (s, i) => s + i.calories),
    );
  }

  /// Called from the review UI when the user removes a food item.
  void removeItem(int index) {
    final items = List<FoodItem>.from(state.items)..removeAt(index);
    state = state.copyWith(
      items: items,
      totalCalories: items.fold<int>(0, (s, i) => s + i.calories),
    );
  }

  /// Persists the confirmed meal to the database.
  Future<MealLog?> confirmAndSave() async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final userId = session?.user.id;

    if (userId == null) {
      state = state.copyWith(
        step: MealProcessingStep.review,
        error: 'Session expired — please sign out and sign back in.',
      );
      return null;
    }

    if (state.items.isEmpty) {
      state = state.copyWith(
        step: MealProcessingStep.review,
        error: 'No food items to save.',
      );
      return null;
    }

    state = state.copyWith(step: MealProcessingStep.saving, error: null);

    try {
      final response = await client.from('meal_logs').insert({
        'user_id': userId,
        'image_url': state.imageUrl,
        'items': state.items.map((e) => e.toMap()).toList(),
        'total_calories': state.totalCalories,
        'total_protein':
            state.items.fold<double>(0.0, (s, i) => s + (i.protein ?? 0.0)),
        'total_carbs':
            state.items.fold<double>(0.0, (s, i) => s + (i.carbs ?? 0.0)),
        'total_fat':
            state.items.fold<double>(0.0, (s, i) => s + (i.fat ?? 0.0)),
        'total_fiber':
            state.items.fold<double>(0.0, (s, i) => s + (i.fiber ?? 0.0)),
      }).select().single();

      final log = MealLog.fromMap(response);

      AnalyticsService.track('meal_logged', properties: {
        'source': 'camera',
        'calories': log.totalCalories,
        'item_count': log.items.length,
      });

      // Record to adaptive meal memory — fire-and-forget, non-fatal.
      // Capture items before any state mutation so the list is stable.
      final savedItems = List<FoodItem>.from(state.items);
      ref
          .read(knownMealControllerProvider.notifier)
          .recordLog(savedItems)
          .ignore();

      // Score any active challenges in the background — never awaited.
      // Skip entirely if the user has no active challenges to avoid a
      // needless edge-function round-trip.
      final hasChallenges =
          ref.read(myChallengesProvider).valueOrNull?.isNotEmpty == true;
      if (hasChallenges) {
        notifyChallenges(log, onComplete: () {
          // Guard against notifier being disposed before the callback fires.
          try {
            ref.invalidate(myChallengesProvider);
          } catch (_) {}
        });
      }

      state = state.copyWith(
        step: MealProcessingStep.saved,
        savedLogId: log.id,
      );
      return log;
    } catch (e) {
      final msg = e.toString();
      final friendly = msg.contains('relation') || msg.contains('does not exist')
          ? 'Database table missing — run the SQL migration in Supabase.'
          : msg.contains('violates') || msg.contains('policy')
              ? 'Permission denied — check RLS policies in Supabase.'
              : msg;
      state = state.copyWith(
        step: MealProcessingStep.review,
        error: friendly,
      );
      return null;
    }
  }

  void reset() => state = const MealState();
}

final mealControllerProvider =
    NotifierProvider<MealController, MealState>(MealController.new);
