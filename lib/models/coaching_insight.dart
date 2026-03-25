// ─── CoachingInsight ─────────────────────────────────────────────────────────
//
// Represents one AI-generated coaching insight produced by the
// `generate-coaching` Edge Function. Each insight covers one week of logs
// and contains actionable text the user can act on.
//
// DB table: coaching_insights
//   id            uuid PK
//   user_id       uuid FK → auth.users
//   week_start    date  (Monday of the covered week, UTC)
//   headline      text  (short, ≤ 80 chars)
//   body          text  (markdown, ≤ 800 chars)
//   category      text  (calories | macros | consistency | hydration | general)
//   is_read       bool  default false
//   created_at    timestamptz

enum InsightCategory {
  calories,
  macros,
  consistency,
  hydration,
  general;

  String get label => switch (this) {
        InsightCategory.calories    => 'Calories',
        InsightCategory.macros      => 'Macros',
        InsightCategory.consistency => 'Consistency',
        InsightCategory.hydration   => 'Hydration',
        InsightCategory.general     => 'General',
      };
}

class CoachingInsight {
  final String id;
  final String userId;
  final DateTime weekStart;
  final String headline;
  final String body;
  final InsightCategory category;
  final bool isRead;
  final DateTime createdAt;

  const CoachingInsight({
    required this.id,
    required this.userId,
    required this.weekStart,
    required this.headline,
    required this.body,
    required this.category,
    required this.isRead,
    required this.createdAt,
  });

  factory CoachingInsight.fromMap(Map<String, dynamic> map) => CoachingInsight(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        weekStart: DateTime.parse(map['week_start'] as String),
        headline: map['headline'] as String,
        body: map['body'] as String,
        category: InsightCategory.values.firstWhere(
          (e) => e.name == (map['category'] as String? ?? 'general'),
          orElse: () => InsightCategory.general,
        ),
        isRead: (map['is_read'] as bool?) ?? false,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  CoachingInsight copyWith({bool? isRead}) => CoachingInsight(
        id: id,
        userId: userId,
        weekStart: weekStart,
        headline: headline,
        body: body,
        category: category,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );
}
