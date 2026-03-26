// ─── FastingController ────────────────────────────────────────────────────────
//
// Owns the currently active fasting session (or null when not fasting).
// State is FastingSession? — the single active row from fasting_sessions where
// ended_at IS NULL, or null when no fast is running.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fasting_session.dart';

// ── Active session ────────────────────────────────────────────────────────────

final fastingControllerProvider =
    AsyncNotifierProvider<FastingController, FastingSession?>(
  FastingController.new,
);

class FastingController extends AsyncNotifier<FastingSession?> {
  @override
  Future<FastingSession?> build() => _fetchActive();

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Starts a new fast with [protocol].
  /// Any currently active fast is ended first (one active fast at a time).
  Future<void> start(FastingProtocol protocol) async {
    state = const AsyncLoading();
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      // Close any open fast before creating a new one.
      await _endAllActive(client, userId);

      final now = DateTime.now();
      final targetEnd = now.add(Duration(hours: protocol.fastHours));

      final row = await client
          .from('fasting_sessions')
          .insert({
            'user_id': userId,
            'protocol': protocol.label,
            'fast_hours': protocol.fastHours,
            'started_at': now.toUtc().toIso8601String(),
            'target_end': targetEnd.toUtc().toIso8601String(),
          })
          .select()
          .single();

      state = AsyncValue.data(FastingSession.fromMap(row));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Ends the current fast (sets ended_at = now in DB and clears state).
  Future<void> stop() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final client = Supabase.instance.client;
    final now = DateTime.now().toUtc().toIso8601String();

    await client
        .from('fasting_sessions')
        .update({'ended_at': now})
        .eq('id', current.id);

    // Invalidate history so the completed session appears immediately.
    ref.invalidate(fastingHistoryProvider);
    state = const AsyncValue.data(null);
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  Future<FastingSession?> _fetchActive() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return null;

    final rows = await client
        .from('fasting_sessions')
        .select()
        .eq('user_id', userId)
        .isFilter('ended_at', null)
        .order('started_at', ascending: false)
        .limit(1);

    if ((rows as List).isEmpty) return null;
    return FastingSession.fromMap(rows.first);
  }

  Future<void> _endAllActive(SupabaseClient client, String userId) async {
    await client
        .from('fasting_sessions')
        .update({'ended_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', userId)
        .isFilter('ended_at', null);
  }
}

// ── History ───────────────────────────────────────────────────────────────────

/// Last 14 completed fasting sessions (most recent first).
final fastingHistoryProvider = FutureProvider<List<FastingSession>>((ref) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];

  final rows = await client
      .from('fasting_sessions')
      .select()
      .eq('user_id', userId)
      .not('ended_at', 'is', null)
      .order('started_at', ascending: false)
      .limit(14);

  return (rows as List)
      .map((r) => FastingSession.fromMap(r as Map<String, dynamic>))
      .toList();
});
