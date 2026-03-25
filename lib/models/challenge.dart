// ─── Challenge + ChallengeParticipant ────────────────────────────────────────
//
// Social Accountability Challenge model.
//
// DB tables:
//
//   challenges
//     id              uuid PK
//     creator_id      uuid FK → auth.users
//     title           text
//     description     text
//     type            text  (calorie_budget | streak | macro_target | custom)
//     target_value    numeric   (e.g. 1800 kcal budget, or 7-day streak)
//     start_date      date
//     end_date        date
//     is_public       bool default true
//     invite_code     text unique   (6-char alphanumeric, for private challenges)
//     created_at      timestamptz
//
//   challenge_participants
//     id              uuid PK
//     challenge_id    uuid FK → challenges
//     user_id         uuid FK → auth.users
//     display_name    text
//     avatar_url      text
//     score           numeric default 0
//     streak_days     int     default 0
//     rank            int     (updated by `challenge-notifier` Edge Function)
//     joined_at       timestamptz
//
//   challenge_events
//     id              uuid PK
//     challenge_id    uuid FK → challenges
//     user_id         uuid FK → auth.users
//     event_type      text  (meal_logged | goal_hit | streak_milestone | joined)
//     payload         jsonb
//     created_at      timestamptz

enum ChallengeType {
  calorieBudget,
  streak,
  macroTarget,
  custom;

  String get label => switch (this) {
        ChallengeType.calorieBudget => 'Calorie Budget',
        ChallengeType.streak        => 'Streak',
        ChallengeType.macroTarget   => 'Macro Target',
        ChallengeType.custom        => 'Custom',
      };

  String get icon => switch (this) {
        ChallengeType.calorieBudget => '🔥',
        ChallengeType.streak        => '⚡',
        ChallengeType.macroTarget   => '💪',
        ChallengeType.custom        => '🎯',
      };
}

class Challenge {
  final String id;
  final String creatorId;
  final String title;
  final String description;
  final ChallengeType type;
  final double targetValue;
  final DateTime startDate;
  final DateTime endDate;
  final bool isPublic;
  final String inviteCode;
  final DateTime createdAt;

  // Populated via join when loading the challenge list / detail.
  final List<ChallengeParticipant> participants;

  const Challenge({
    required this.id,
    required this.creatorId,
    required this.title,
    required this.description,
    required this.type,
    required this.targetValue,
    required this.startDate,
    required this.endDate,
    required this.isPublic,
    required this.inviteCode,
    required this.createdAt,
    this.participants = const [],
  });

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startDate) && now.isBefore(endDate.add(const Duration(days: 1)));
  }

  bool get isUpcoming => DateTime.now().isBefore(startDate);
  bool get isCompleted => DateTime.now().isAfter(endDate);

  int get daysRemaining {
    final diff = endDate.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory Challenge.fromMap(Map<String, dynamic> map) => Challenge(
        id: map['id'] as String,
        creatorId: map['creator_id'] as String,
        title: map['title'] as String,
        description: (map['description'] as String?) ?? '',
        type: ChallengeType.values.firstWhere(
          (e) => e.name == _camelFromSnake(map['type'] as String? ?? 'custom'),
          orElse: () => ChallengeType.custom,
        ),
        targetValue: (map['target_value'] as num?)?.toDouble() ?? 0,
        startDate: DateTime.parse(map['start_date'] as String),
        endDate: DateTime.parse(map['end_date'] as String),
        isPublic: (map['is_public'] as bool?) ?? true,
        inviteCode: (map['invite_code'] as String?) ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
        participants: (map['participants'] as List<dynamic>?)
                ?.map((e) =>
                    ChallengeParticipant.fromMap(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toInsertMap() => {
        'creator_id': creatorId,
        'title': title,
        'description': description,
        'type': _snakeFromCamel(type.name),
        'target_value': targetValue,
        'start_date': startDate.toIso8601String().split('T').first,
        'end_date': endDate.toIso8601String().split('T').first,
        'is_public': isPublic,
      };
}

class ChallengeParticipant {
  final String id;
  final String challengeId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final double score;
  final int streakDays;
  final int rank;
  final DateTime joinedAt;

  const ChallengeParticipant({
    required this.id,
    required this.challengeId,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.score,
    required this.streakDays,
    required this.rank,
    required this.joinedAt,
  });

  factory ChallengeParticipant.fromMap(Map<String, dynamic> map) =>
      ChallengeParticipant(
        id: map['id'] as String,
        challengeId: map['challenge_id'] as String,
        userId: map['user_id'] as String,
        displayName: (map['display_name'] as String?) ?? 'Anonymous',
        avatarUrl: map['avatar_url'] as String?,
        score: (map['score'] as num?)?.toDouble() ?? 0,
        streakDays: (map['streak_days'] as int?) ?? 0,
        rank: (map['rank'] as int?) ?? 0,
        joinedAt: DateTime.parse(map['joined_at'] as String),
      );
}

// ── Helpers ────────────────────────────────────────────────────────────────

String _camelFromSnake(String s) {
  final parts = s.split('_');
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

String _snakeFromCamel(String s) => s.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '_${m.group(0)!.toLowerCase()}',
    );
