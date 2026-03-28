import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/challenge.dart';
import '../services/analytics_service.dart';
import 'auth_controller.dart' show authStateProvider;

// ─── ChallengeController ──────────────────────────────────────────────────────
//
// Manages the user's challenges: browsing public ones, joining, creating, and
// loading the detail with a full leaderboard.

// ── Providers ────────────────────────────────────────────────────────────────

/// The user's active + upcoming challenges (challenges they participate in).
final myChallengesProvider =
    AsyncNotifierProvider<MyChallengesNotifier, List<Challenge>>(
  MyChallengesNotifier.new,
);

/// Public challenges available to browse / join.
final publicChallengesProvider =
    AsyncNotifierProvider<PublicChallengesNotifier, List<Challenge>>(
  PublicChallengesNotifier.new,
);

/// Detail view for a single challenge (includes full participant leaderboard).
final challengeDetailProvider =
    AsyncNotifierProviderFamily<ChallengeDetailNotifier, Challenge?, String>(
  ChallengeDetailNotifier.new,
);

// ── MyChallengesNotifier ──────────────────────────────────────────────────────

class MyChallengesNotifier extends AsyncNotifier<List<Challenge>> {
  @override
  Future<List<Challenge>> build() async {
    final authState = await ref.watch(authStateProvider.future);
    if (authState.session == null) return [];
    return _fetch();
  }

  Future<List<Challenge>> _fetch() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    // Join through challenge_participants to get only the user's challenges.
    final rows = await client
        .from('challenge_participants')
        .select('challenge_id, challenges(*)')
        .eq('user_id', userId)
        .order('joined_at', ascending: false);

    final all = (rows as List<dynamic>)
        .map((row) {
          final challengeMap =
              row['challenges'] as Map<String, dynamic>? ?? {};
          return Challenge.fromMap(challengeMap);
        })
        .toList();

    // Fire analytics for any challenge that just completed (was active, now past end date).
    final previousIds = state.valueOrNull?.map((c) => c.id).toSet() ?? {};
    for (final c in all) {
      if (c.isCompleted && previousIds.contains(c.id)) {
        AnalyticsService.track('challenge_completed', properties: {
          'challenge_id': c.id,
          'type': c.type.name,
        });
      }
    }

    return all.where((c) => !c.isCompleted).toList();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  /// Creates a new challenge and auto-joins the creator.
  Future<Challenge?> create({
    required String title,
    required String description,
    required ChallengeType type,
    required double targetValue,
    required DateTime startDate,
    required DateTime endDate,
    bool isPublic = true,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return null;

    final insertData = {
      'creator_id': userId,
      'title': title,
      'description': description,
      'type': type.name.replaceAllMapped(
        RegExp('[A-Z]'),
        (m) => '_${m.group(0)!.toLowerCase()}',
      ),
      'target_value': targetValue,
      'start_date': startDate.toIso8601String().split('T').first,
      'end_date': endDate.toIso8601String().split('T').first,
      'is_public': isPublic,
    };

    final response = await client
        .from('challenges')
        .insert(insertData)
        .select()
        .single();

    final challenge = Challenge.fromMap(response);

    // Auto-join as creator.
    await _joinChallenge(client, userId, challenge.id);

    AnalyticsService.track('challenge_created', properties: {
      'type': type.name,
      'is_public': isPublic,
    });

    await refresh();
    return challenge;
  }

  /// Joins an existing challenge by ID (public) or invite code (private).
  Future<bool> join({String? challengeId, String? inviteCode}) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return false;

    String? resolvedId = challengeId;

    if (resolvedId == null && inviteCode != null) {
      final row = await client
          .from('challenges')
          .select('id')
          .eq('invite_code', inviteCode.toUpperCase())
          .maybeSingle();
      resolvedId = row?['id'] as String?;
    }

    if (resolvedId == null) return false;

    // ── Participant cap ──────────────────────────────────────────────────────
    // Phase 2 cap: maximum 10 participants per challenge.
    final countRows = await client
        .from('challenge_participants')
        .select('id')
        .eq('challenge_id', resolvedId);
    if ((countRows as List<dynamic>).length >= Challenge.maxParticipants) {
      return false; // Full — caller should surface "Challenge is full" message.
    }

    try {
      await _joinChallenge(client, userId, resolvedId);
      AnalyticsService.track('challenge_joined', properties: {
        'method': inviteCode != null ? 'invite_code' : 'direct',
      });
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Leaves a challenge the user currently participates in.
  /// Returns `true` on success. Creators cannot leave their own challenges.
  Future<bool> leave(String challengeId) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      await client
          .from('challenge_participants')
          .delete()
          .eq('challenge_id', challengeId)
          .eq('user_id', userId);

      AnalyticsService.track('challenge_left', properties: {
        'challenge_id': challengeId,
      });

      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _joinChallenge(
    SupabaseClient client,
    String userId,
    String challengeId,
  ) async {
    // Fetch the user's display name from their profile.
    final profile = await client
        .from('profiles')
        .select('name, avatar_url')
        .eq('id', userId)
        .maybeSingle();

    await client.from('challenge_participants').upsert(
      {
        'challenge_id': challengeId,
        'user_id': userId,
        'display_name': profile?['name'] as String? ?? 'Anonymous',
        'avatar_url': profile?['avatar_url'],
      },
      onConflict: 'challenge_id,user_id',
    );

    await client.from('challenge_events').insert({
      'challenge_id': challengeId,
      'user_id': userId,
      'event_type': 'joined',
      'payload': {},
    });
  }
}

// ── PublicChallengesNotifier ──────────────────────────────────────────────────

class PublicChallengesNotifier extends AsyncNotifier<List<Challenge>> {
  @override
  Future<List<Challenge>> build() async {
    final authState = await ref.watch(authStateProvider.future);
    if (authState.session == null) return [];
    return _fetch();
  }

  Future<List<Challenge>> _fetch() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    final today = DateTime.now().toIso8601String().split('T').first;

    final rows = await client
        .from('challenges')
        .select()
        .eq('is_public', true)
        .gte('end_date', today)
        .order('created_at', ascending: false)
        .limit(30);

    // Exclude challenges the user is already in.
    final myRows = await client
        .from('challenge_participants')
        .select('challenge_id')
        .eq('user_id', userId);

    final myIds = (myRows as List<dynamic>)
        .map((r) => r['challenge_id'] as String)
        .toSet();

    final challengeList = (rows as List<dynamic>)
        .map((e) => Challenge.fromMap(e as Map<String, dynamic>))
        .where((c) => !myIds.contains(c.id))
        .toList();

    if (challengeList.isEmpty) return challengeList;

    // Batch-fetch participant counts for all returned challenges.
    final ids = challengeList.map((c) => c.id).toList();
    final countRows = await client
        .from('challenge_participants')
        .select('challenge_id')
        .inFilter('challenge_id', ids);

    final counts = <String, int>{};
    for (final row in (countRows as List<dynamic>)) {
      final cid = row['challenge_id'] as String;
      counts[cid] = (counts[cid] ?? 0) + 1;
    }

    return challengeList
        .map((c) => c.withParticipantCount(counts[c.id] ?? 0))
        .toList();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }
}

// ── ChallengeDetailNotifier ───────────────────────────────────────────────────

class ChallengeDetailNotifier
    extends FamilyAsyncNotifier<Challenge?, String> {
  @override
  Future<Challenge?> build(String arg) async {
    final authState = await ref.watch(authStateProvider.future);
    if (authState.session == null) return null;
    return _fetch(arg);
  }

  Future<Challenge?> _fetch(String challengeId) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return null;

    final challengeRow = await client
        .from('challenges')
        .select()
        .eq('id', challengeId)
        .maybeSingle();

    if (challengeRow == null) return null;

    final participantsRows = await client
        .from('challenge_participants')
        .select()
        .eq('challenge_id', challengeId)
        .order('rank');

    final participants = (participantsRows as List<dynamic>)
        .map((e) =>
            ChallengeParticipant.fromMap(e as Map<String, dynamic>))
        .toList();

    return Challenge.fromMap({
      ...challengeRow,
      'participants': (participantsRows as List<dynamic>)
          .cast<Map<String, dynamic>>(),
    }).copyWithParticipants(participants);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _fetch(arg));
  }
}

// ── Completed challenges provider (for profile badges) ───────────────────────

/// Loads the user's completed challenges (end_date passed) as lightweight
/// records — just enough data for badge display. Fetched once on demand.
final completedChallengesProvider = FutureProvider<List<Challenge>>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  if (authState.session == null) return [];

  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];

  final rows = await client
      .from('challenge_participants')
      .select('challenge_id, challenges(*)')
      .eq('user_id', userId)
      .order('joined_at', ascending: false);

  return (rows as List<dynamic>)
      .map((row) {
        final map = row['challenges'] as Map<String, dynamic>? ?? {};
        return Challenge.fromMap(map);
      })
      .where((c) => c.isCompleted)
      .toList();
});

// ── Challenge.copyWithParticipants extension ─────────────────────────────────

extension ChallengeX on Challenge {
  Challenge copyWithParticipants(List<ChallengeParticipant> participants) =>
      Challenge(
        id: id,
        creatorId: creatorId,
        title: title,
        description: description,
        type: type,
        targetValue: targetValue,
        startDate: startDate,
        endDate: endDate,
        isPublic: isPublic,
        inviteCode: inviteCode,
        createdAt: createdAt,
        participants: participants,
      );
}
