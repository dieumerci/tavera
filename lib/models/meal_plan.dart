// ─── MealPlan + MealPlanDay + PlannedMeal ─────────────────────────────────────
//
// AI-generated personalised meal plan for a given week.
// Produced by the `generate-meal-plan` Edge Function after the user has
// at least 7 days of meal logs.
//
// DB tables:
//
//   meal_plans
//     id              uuid PK
//     user_id         uuid FK → auth.users
//     week_start      date   (Monday of the planned week, UTC)
//     calorie_target  int
//     days            jsonb  (array of MealPlanDay objects)
//     ai_notes        text   (optional dietitian-style summary)
//     created_at      timestamptz
//
// The `days` JSONB column stores the full nested structure so the planner
// is self-contained and doesn't require an extra join.

class MealPlan {
  final String id;
  final String userId;
  final DateTime weekStart;
  final int calorieTarget;
  final List<MealPlanDay> days;
  final String? aiNotes;
  final DateTime createdAt;

  const MealPlan({
    required this.id,
    required this.userId,
    required this.weekStart,
    required this.calorieTarget,
    required this.days,
    this.aiNotes,
    required this.createdAt,
  });

  factory MealPlan.fromMap(Map<String, dynamic> map) => MealPlan(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        weekStart: DateTime.parse(map['week_start'] as String),
        calorieTarget: (map['calorie_target'] as int?) ?? 2000,
        days: (map['days'] as List<dynamic>? ?? [])
            .map((d) => MealPlanDay.fromMap(d as Map<String, dynamic>))
            .toList(),
        aiNotes: map['ai_notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  /// Total planned calories for the week.
  int get weeklyCalories =>
      days.fold(0, (s, d) => s + d.totalCalories);
}

class MealPlanDay {
  // Day index 0 = Monday, 6 = Sunday (ISO week).
  final int dayIndex;
  final List<PlannedMeal> meals;

  const MealPlanDay({required this.dayIndex, required this.meals});

  int get totalCalories => meals.fold(0, (s, m) => s + m.calories);

  factory MealPlanDay.fromMap(Map<String, dynamic> map) => MealPlanDay(
        dayIndex: (map['day_index'] as int?) ?? 0,
        meals: (map['meals'] as List<dynamic>? ?? [])
            .map((m) => PlannedMeal.fromMap(m as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'day_index': dayIndex,
        'meals': meals.map((m) => m.toMap()).toList(),
      };
}

enum MealSlot {
  breakfast,
  lunch,
  dinner,
  snack;

  String get label => switch (this) {
        MealSlot.breakfast => 'Breakfast',
        MealSlot.lunch     => 'Lunch',
        MealSlot.dinner    => 'Dinner',
        MealSlot.snack     => 'Snack',
      };
}

class PlannedMeal {
  final MealSlot slot;
  final String name;
  final String description;
  final int calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  /// Rough prep time in minutes.
  final int? prepMinutes;

  const PlannedMeal({
    required this.slot,
    required this.name,
    required this.description,
    required this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.prepMinutes,
  });

  factory PlannedMeal.fromMap(Map<String, dynamic> map) => PlannedMeal(
        slot: MealSlot.values.firstWhere(
          (e) => e.name == (map['slot'] as String? ?? 'lunch'),
          orElse: () => MealSlot.lunch,
        ),
        name: (map['name'] as String?) ?? '',
        description: (map['description'] as String?) ?? '',
        calories: (map['calories'] as int?) ?? 0,
        proteinG: (map['protein_g'] as num?)?.toDouble(),
        carbsG: (map['carbs_g'] as num?)?.toDouble(),
        fatG: (map['fat_g'] as num?)?.toDouble(),
        prepMinutes: map['prep_minutes'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'slot': slot.name,
        'name': name,
        'description': description,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'prep_minutes': prepMinutes,
      };
}
