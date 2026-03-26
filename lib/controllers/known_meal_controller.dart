import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/food_item.dart';
import '../models/known_meal.dart';
import '../services/analytics_service.dart';
import 'auth_controller.dart' show authStateProvider;
import 'log_controller.dart';

// ─── KnownMealController ──────────────────────────────────────────────────────
//
// Manages the user's known meals — frequently logged meals identified by a
// fingerprint hash of their sorted item names.
//
// On each meal log, the app should call `recordLog()` to potentially promote
// the meal into `known_meals` (or increment its occurrence_count).
//
// The Dashboard reads `topKnownMeals` to show one-tap re-logging chips.

// ── Provider ─────────────────────────────────────────────────────────────────

final knownMealControllerProvider =
    AsyncNotifierProvider<KnownMealController, List<KnownMeal>>(
  KnownMealController.new,
);

/// Top 5 known meals for Dashboard chips.
/// Primary sort: time-of-day proximity (meals last logged near the current
/// hour appear first); secondary sort: occurrence count descending.
final topKnownMealsProvider = Provider<List<KnownMeal>>((ref) {
  final meals = ref.watch(knownMealControllerProvider).valueOrNull ?? [];
  if (meals.isEmpty) return [];
  final nowHour = DateTime.now().hour;
  // Circular distance in hours (0–12) — closer = lower score.
  int hourDist(int h) => min((h - nowHour).abs(), 24 - (h - nowHour).abs());
  final sorted = [...meals]..sort((a, b) {
      final da = hourDist(a.lastLoggedAt.toLocal().hour);
      final db = hourDist(b.lastLoggedAt.toLocal().hour);
      if (da != db) return da.compareTo(db);
      return b.occurrenceCount.compareTo(a.occurrenceCount);
    });
  return sorted.take(5).toList();
});

// ── Controller ────────────────────────────────────────────────────────────────

class KnownMealController extends AsyncNotifier<List<KnownMeal>> {
  @override
  Future<List<KnownMeal>> build() async {
    final authState = await ref.watch(authStateProvider.future);
    if (authState.session == null) return [];
    return _fetch();
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<List<KnownMeal>> _fetch() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await client
        .from('known_meals')
        .select()
        .eq('user_id', userId)
        .order('occurrence_count', ascending: false)
        .limit(20);

    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return (rows as List<dynamic>)
        .map((e) => KnownMeal.fromMap(e as Map<String, dynamic>))
        .where((m) => m.lastLoggedAt.isAfter(cutoff))
        .toList();
  }

  // ── Record a log ──────────────────────────────────────────────────────────

  /// Called after a meal is successfully saved. Creates or increments the
  /// known_meal entry for this combination of food items.
  Future<void> recordLog(List<FoodItem> items) async {
    if (items.isEmpty) return;
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final fp = _fingerprint(items);
    final totalCalories = items.fold(0, (s, i) => s + i.calories);
    final name = _generateName(items);

    // Upsert: increment occurrence_count if fingerprint already exists.
    await client.from('known_meals').upsert(
      {
        'user_id': userId,
        'name': name,
        'fingerprint': fp,
        'items': items.map((i) => i.toMap()).toList(),
        'total_calories': totalCalories,
        'last_logged_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id,fingerprint',
    );

    // Increment occurrence_count via a separate update (upsert doesn't RPC).
    await client.rpc('increment_known_meal_count', params: {
      'p_user_id': userId,
      'p_fingerprint': fp,
    });

    // Refresh local list.
    state = await AsyncValue.guard(_fetch);
  }

  // ── Re-log a known meal ───────────────────────────────────────────────────

  /// Logs a known meal directly from the Dashboard chip. Returns the new
  /// MealLog ID on success, or null on failure.
  Future<String?> relog(KnownMeal meal, WidgetRef ref) async {
    try {
      final log = await directLogMeal(ref, items: meal.items);
      if (log != null) {
        // Bump occurrence count and last_logged_at.
        await recordLog(meal.items);
        AnalyticsService.track('known_meal_relogged', properties: {
          'meal_name': meal.name,
          'calories': meal.totalCalories,
        });
      }
      return log?.id;
    } catch (_) {
      return null;
    }
  }

  // ── Rename a known meal ───────────────────────────────────────────────────

  Future<void> rename(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final client = Supabase.instance.client;
    await client
        .from('known_meals')
        .update({'name': trimmed})
        .eq('id', id);
    state = AsyncValue.data(
      (state.valueOrNull ?? [])
          .map((m) => m.id == id ? m.copyWithName(trimmed) : m)
          .toList(),
    );
  }

  // ── Delete a known meal ───────────────────────────────────────────────────

  Future<void> delete(String id) async {
    final client = Supabase.instance.client;
    await client.from('known_meals').delete().eq('id', id);
    state = AsyncValue.data(
      (state.valueOrNull ?? []).where((m) => m.id != id).toList(),
    );
  }

  // ── Fingerprint helpers ───────────────────────────────────────────────────

  /// SHA-256-like fingerprint: sorted item names, lowercased, joined + hashed.
  /// Using a simple deterministic hash so the DB unique constraint works.
  static String _fingerprint(List<FoodItem> items) {
    final names = items.map((i) => i.name.toLowerCase().trim()).toList()..sort();
    final joined = names.join('|');
    return _simpleHash(joined);
  }

  /// djb2 hash — fast, deterministic, good enough for deduplication.
  static String _simpleHash(String s) {
    var hash = 5381;
    for (final rune in s.runes) {
      hash = ((hash << 5) + hash + rune) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Human-readable name: first 2–3 item names, truncated.
  static String _generateName(List<FoodItem> items) {
    final names = items.take(min(3, items.length)).map((i) {
      final n = i.name.trim();
      // Capitalise first letter.
      return n.isEmpty ? n : n[0].toUpperCase() + n.substring(1);
    }).toList();
    return names.join(', ');
  }
}

// ── increment_known_meal_count RPC helper ─────────────────────────────────────
//
// Add this function to your Supabase SQL editor:
//
// create or replace function public.increment_known_meal_count(
//   p_user_id uuid,
//   p_fingerprint text
// ) returns void
// language plpgsql
// security definer
// as $$
// begin
//   update public.known_meals
//   set occurrence_count = occurrence_count + 1,
//       last_logged_at   = now()
//   where user_id    = p_user_id
//     and fingerprint = p_fingerprint;
// end;
// $$;
