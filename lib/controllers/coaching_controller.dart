import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coaching_insight.dart';

// ─── CoachingController ───────────────────────────────────────────────────────
//
// Manages the list of coaching insights for the current user.
// Loads the most recent N insights from `coaching_insights`, and exposes
// `generate()` to call the `generate-coaching` Edge Function for the
// current week.

// ── Provider ─────────────────────────────────────────────────────────────────

final coachingControllerProvider =
    AsyncNotifierProvider<CoachingController, List<CoachingInsight>>(
  CoachingController.new,
);

// ── Controller ────────────────────────────────────────────────────────────────

class CoachingController extends AsyncNotifier<List<CoachingInsight>> {
  @override
  Future<List<CoachingInsight>> build() => _fetchInsights();

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<List<CoachingInsight>> _fetchInsights() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await client
        .from('coaching_insights')
        .select()
        .eq('user_id', userId)
        .order('week_start', ascending: false)
        .limit(20);

    return (response as List<dynamic>)
        .map((e) => CoachingInsight.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // ── Generate ──────────────────────────────────────────────────────────────

  /// Calls the `generate-coaching` Edge Function for the week containing [date]
  /// (defaults to the current week's Monday). Returns early if the current
  /// user has already generated insights for this week.
  Future<void> generate({DateTime? date}) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final weekStart = _mondayOf(date ?? DateTime.now());
    final weekStartStr =
        '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';

    // Optimistic check — skip if this week already has insights.
    final existing = state.valueOrNull ?? [];
    final alreadyGenerated = existing.any(
      (i) =>
          i.weekStart.year == weekStart.year &&
          i.weekStart.month == weekStart.month &&
          i.weekStart.day == weekStart.day,
    );
    if (alreadyGenerated) return;

    state = const AsyncValue.loading();
    try {
      await client.functions.invoke(
        'generate-coaching',
        body: {'user_id': userId, 'week_start': weekStartStr},
      );
      // Refresh from DB to get the newly inserted rows.
      state = await AsyncValue.guard(_fetchInsights);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  // ── Mark as read ──────────────────────────────────────────────────────────

  Future<void> markRead(String insightId) async {
    final client = Supabase.instance.client;

    await client
        .from('coaching_insights')
        .update({'is_read': true})
        .eq('id', insightId);

    // Update local state optimistically.
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
      current
          .map((i) => i.id == insightId ? i.copyWith(isRead: true) : i)
          .toList(),
    );
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetchInsights);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns the Monday (start) of the ISO week containing [date].
  static DateTime _mondayOf(DateTime date) {
    final diff = date.weekday - DateTime.monday;
    return DateTime(date.year, date.month, date.day - diff);
  }
}

// ── Convenience provider — unread count ──────────────────────────────────────

/// Number of unread coaching insights for the current user.
final unreadInsightCountProvider = Provider<int>((ref) {
  final insights = ref.watch(coachingControllerProvider).valueOrNull ?? [];
  return insights.where((i) => !i.isRead).length;
});
