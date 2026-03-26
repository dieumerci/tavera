import 'dart:async' show Timer, unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/extensions/date_extensions.dart';
import '../models/food_item.dart';
import '../models/meal_log.dart';
import '../models/user_profile.dart';
import 'challenge_controller.dart' show myChallengesProvider;

// ── Daily summary state ─────────────────────────────────────────────────────

class DailyLogState {
  final List<MealLog> todayLogs;
  final int totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;

  const DailyLogState({
    this.todayLogs = const [],
    this.totalCalories = 0,
    this.totalProtein = 0,
    this.totalCarbs = 0,
    this.totalFat = 0,
  });

  int get logCount => todayLogs.length;

  DailyLogState copyWith({
    List<MealLog>? todayLogs,
    int? totalCalories,
    double? totalProtein,
    double? totalCarbs,
    double? totalFat,
  }) =>
      DailyLogState(
        todayLogs: todayLogs ?? this.todayLogs,
        totalCalories: totalCalories ?? this.totalCalories,
        totalProtein: totalProtein ?? this.totalProtein,
        totalCarbs: totalCarbs ?? this.totalCarbs,
        totalFat: totalFat ?? this.totalFat,
      );
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Builds a UTC timestamp range for a given LOCAL calendar day.
/// Sending UTC ISO strings ensures Postgres (which stores timestamptz as UTC)
/// compares correctly regardless of the user's timezone offset.
({String start, String end}) _dayRange(DateTime localDay) {
  final start = DateTime(localDay.year, localDay.month, localDay.day).toUtc();
  final end = start.add(const Duration(days: 1));
  return (start: start.toIso8601String(), end: end.toIso8601String());
}

DailyLogState _summarise(List<MealLog> logs) {
  final calories = logs.fold(0, (s, l) => s + l.totalCalories);
  final protein  = logs.fold(0.0, (s, l) => s + (l.totalProtein ?? 0));
  final carbs    = logs.fold(0.0, (s, l) => s + (l.totalCarbs   ?? 0));
  final fat      = logs.fold(0.0, (s, l) => s + (l.totalFat     ?? 0));
  return DailyLogState(
    todayLogs: logs,
    totalCalories: calories,
    totalProtein: protein,
    totalCarbs: carbs,
    totalFat: fat,
  );
}

// ── Today's log controller (used by camera chip) ────────────────────────────

class LogController extends AsyncNotifier<DailyLogState> {
  @override
  Future<DailyLogState> build() => _fetchTodayLogs();

  Future<DailyLogState> _fetchTodayLogs() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const DailyLogState();

    final range = _dayRange(DateTime.now());

    final response = await client
        .from('meal_logs')
        .select()
        .eq('user_id', userId)
        .gte('logged_at', range.start)
        .lt('logged_at', range.end)
        .order('logged_at', ascending: false);

    final logs = (response as List<dynamic>)
        .map((e) => MealLog.fromMap(e as Map<String, dynamic>))
        .toList();

    return _summarise(logs);
  }

  /// Returns true if the user may log another meal right now.
  bool canLog(UserProfile? profile) {
    if (profile?.isPremium == true) return true;
    return (state.valueOrNull?.logCount ?? 0) < AppConfig.freeDailyLogLimit;
  }

  /// Instant UI update while the DB write is in-flight.
  void optimisticallyAddLog(MealLog log) {
    final current = state.valueOrNull ?? const DailyLogState();
    final logs = [log, ...current.todayLogs];
    state = AsyncData(_summarise(logs));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchTodayLogs);
  }
}

final logControllerProvider =
    AsyncNotifierProvider<LogController, DailyLogState>(LogController.new);

// ── History provider (any date, cached per date) ────────────────────────────

/// FutureProvider.family keyed on a LOCAL calendar day.
/// Each unique date gets its own cached provider instance — navigating
/// back to a visited date is instant, only new dates hit Supabase.
final historyLogsProvider =
    FutureProvider.family<List<MealLog>, DateTime>((ref, date) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];

  final range = _dayRange(date);

  final response = await client
      .from('meal_logs')
      .select()
      .eq('user_id', userId)
      .gte('logged_at', range.start)
      .lt('logged_at', range.end)
      .order('logged_at', ascending: false);

  return (response as List<dynamic>)
      .map((e) => MealLog.fromMap(e as Map<String, dynamic>))
      .toList();
});

// ── Water tracking ──────────────────────────────────────────────────────────
// Persisted to `daily_stats` in Supabase so intake survives restarts and
// syncs across devices. UI updates are instant (optimistic); DB writes are
// fire-and-forget so a network hiccup never blocks the add/subtract action.

const _waterStepMl = 250;

final waterMlProvider = StateNotifierProvider<_WaterNotifier, int>(
  (_) => _WaterNotifier()..loadToday(),
);

class _WaterNotifier extends StateNotifier<int> {
  _WaterNotifier() : super(0);

  // Capture the calendar date at construction time so that the value loaded
  // by loadToday() and every subsequent _upsert() always refer to the same
  // DB row — even if the device crosses midnight between taps.
  final String _today = DateTime.now().toIsoDateString();

  // Debounce timer: coalesces rapid button taps into a single upsert.
  Timer? _debounce;

  /// Load today's persisted value from DB on first build.
  Future<void> loadToday() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentSession?.user.id;
      if (userId == null) return;

      final row = await client
          .from('daily_stats')
          .select('water_ml')
          .eq('user_id', userId)
          .eq('stat_date', _today)
          .maybeSingle();

      // Re-check mounted after the async gap before mutating state.
      if (!mounted) return;
      state = (row?['water_ml'] as int?) ?? 0;
    } catch (_) {
      // Non-fatal — fall back to in-memory zero.
    }
  }

  void add() {
    state = state + _waterStepMl;
    _persist();
  }

  void subtract() {
    if (state >= _waterStepMl) {
      state = state - _waterStepMl;
      _persist();
    }
  }

  void reset() {
    state = 0;
    _persist();
  }

  /// Debounced persist — rapid taps (e.g. 5× in 500 ms) collapse into one
  /// upsert, preventing a burst of redundant network requests.
  void _persist() {
    _debounce?.cancel();
    // Capture the current state value now so that the upsert always writes
    // the state that was current when the last tap fired, not a later value.
    final snapshot = state;
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _upsert(snapshot, _today),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  static Future<void> _upsert(int waterMl, String statDate) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentSession?.user.id;
      if (userId == null) return;

      await client.from('daily_stats').upsert(
        {
          'user_id': userId,
          'stat_date': statDate,
          'water_ml': waterMl,
        },
        onConflict: 'user_id,stat_date',
      );
    } catch (_) {
      // Non-fatal — next successful write will self-correct.
    }
  }
}

// ── Challenge scoring ────────────────────────────────────────────────────────

/// Fire-and-forget: posts the saved [log] to the `challenge-notifier` Edge
/// Function so active challenges are scored and ranked without blocking the UI.
///
/// [onComplete] — optional callback invoked after the edge function returns
/// (whether it succeeded or not). Use it to invalidate provider caches, e.g.:
///   `notifyChallenges(log, onComplete: () => ref.invalidate(myChallengesProvider))`
///
/// Silently swallows errors — a scoring failure must never surface to the user
/// because the meal has already been saved successfully.
void notifyChallenges(MealLog log, {void Function()? onComplete}) {
  unawaited(_postChallengeEvent(log, onComplete: onComplete));
}

Future<void> _postChallengeEvent(
  MealLog log, {
  void Function()? onComplete,
}) async {
  try {
    final client = Supabase.instance.client;
    final userId = client.auth.currentSession?.user.id;
    if (userId == null) return;

    await client.functions.invoke(
      'challenge-notifier',
      body: {
        'user_id': userId,
        'meal_log_id': log.id,
        'calories': log.totalCalories,
        'protein_g': log.totalProtein,
        'carbs_g': log.totalCarbs,
        'fat_g': log.totalFat,
        'logged_at': log.loggedAt.toIso8601String(),
      },
    );
  } catch (_) {
    // Non-fatal — challenge scores will self-correct on the next log.
  } finally {
    onComplete?.call();
  }
}

// ── Direct log (barcode / manual quick-add) ─────────────────────────────────

/// Saves a meal without the AI pipeline — used by barcode scan and quick-add.
/// Optimistically updates the daily chip and invalidates the history cache.
/// Returns the saved [MealLog] or null if the write fails.
Future<MealLog?> directLogMeal(
  WidgetRef ref, {
  required List<FoodItem> items,
  String? imageUrl,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentSession?.user.id;
  if (userId == null || items.isEmpty) return null;

  final totalCalories = items.fold<int>(0, (s, i) => s + i.calories);
  final totalProtein  = items.fold<double>(0.0, (s, i) => s + (i.protein ?? 0));
  final totalCarbs    = items.fold<double>(0.0, (s, i) => s + (i.carbs   ?? 0));
  final totalFat      = items.fold<double>(0.0, (s, i) => s + (i.fat     ?? 0));

  try {
    final response = await client.from('meal_logs').insert({
      'user_id': userId,
      'image_url': imageUrl,
      'items': items.map((e) => e.toMap()).toList(),
      'total_calories': totalCalories,
      'total_protein': totalProtein,
      'total_carbs': totalCarbs,
      'total_fat': totalFat,
    }).select().single();

    final log = MealLog.fromMap(response);

    // Instant chip update + invalidate today's history cache.
    ref.read(logControllerProvider.notifier).optimisticallyAddLog(log);
    final today = DateTime.now();
    ref.invalidate(historyLogsProvider(
      DateTime(today.year, today.month, today.day),
    ));

    // Score any active challenges in the background — never awaited.
    // Skip if no active challenges to avoid a needless network call.
    // On completion, invalidate so the leaderboard reflects the new scores.
    final hasChallenges =
        ref.read(myChallengesProvider).valueOrNull?.isNotEmpty == true;
    if (hasChallenges) {
      notifyChallenges(log, onComplete: () {
        try {
          ref.invalidate(myChallengesProvider);
        } catch (_) {}
      });
    }

    return log;
  } catch (_) {
    return null;
  }
}

// ── Meal deletion ────────────────────────────────────────────────────────────

/// Deletes a meal log by ID, then invalidates both the history cache for
/// that day and today's running totals so the chip stays accurate.
Future<void> deleteMealLog(
  WidgetRef ref,
  String logId,
  DateTime loggedAt,
) async {
  await Supabase.instance.client
      .from('meal_logs')
      .delete()
      .eq('id', logId);

  // Invalidate the history cache for that day.
  ref.invalidate(historyLogsProvider(
    DateTime(loggedAt.year, loggedAt.month, loggedAt.day),
  ));

  // If it was today, also refresh the camera chip totals.
  final today = DateTime.now();
  if (loggedAt.year == today.year &&
      loggedAt.month == today.month &&
      loggedAt.day == today.day) {
    ref.read(logControllerProvider.notifier).refresh();
  }
}
