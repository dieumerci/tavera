import 'food_item.dart';

// ── Meal scoring ───────────────────────────────────────────────────────────────
// Rates each meal relative to the user's daily calorie goal.
//
// Green  ≤ 35 % of daily goal AND protein ≥ 15 g  →  well-balanced, on track
// Yellow ≤ 50 % of daily goal                     →  moderate, acceptable
// Red    > 50 % of daily goal                     →  heavy meal, worth noting
//
// These thresholds are intentionally non-judgmental — they indicate how a
// single meal sits within the context of the day, not whether it is "good"
// or "bad". The app does not shame users for red meals.
enum MealScore { green, yellow, red }

class MealLog {
  final String id;
  final String userId;
  final String? imageUrl;
  final DateTime loggedAt;
  final List<FoodItem> items;
  final int totalCalories;
  final double? totalProtein;
  final double? totalCarbs;
  final double? totalFat;
  /// Sum of dietary fibre across all items (grams).
  /// Null for logs created before migration 008 (pre net-carbs support).
  final double? totalFiber;
  /// Optional after-meal rating captured by the Mood-Energy engine (Phase 3).
  /// Keys: 'energy' (1–5), 'mood' (1–5). Null when the user has not rated.
  final Map<String, int>? feeling;

  const MealLog({
    required this.id,
    required this.userId,
    this.imageUrl,
    required this.loggedAt,
    required this.items,
    required this.totalCalories,
    this.totalProtein,
    this.totalCarbs,
    this.totalFat,
    this.totalFiber,
    this.feeling,
  });

  /// Score relative to [calorieGoal] (daily target, not per-meal allocation).
  /// Thresholds are intentional guidance, not judgement.
  MealScore score({required int calorieGoal}) {
    final ratio = totalCalories / calorieGoal;
    final protein = totalProtein ?? 0;
    if (ratio <= 0.35 && protein >= 15) return MealScore.green;
    if (ratio <= 0.50) return MealScore.yellow;
    return MealScore.red;
  }

  /// Net carbs = carbs − fiber, floored at 0 per item.
  /// For items without fiber data (older logs), fiber defaults to 0 so
  /// net carbs equals gross carbs — preserving backward compatibility.
  double get totalNetCarbs => items.fold(
        0.0,
        (sum, item) => sum +
            ((item.carbs ?? 0) - (item.fiber ?? 0)).clamp(
              0.0,
              double.infinity,
            ),
      );

  factory MealLog.fromMap(Map<String, dynamic> map) => MealLog(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        imageUrl: map['image_url'] as String?,
        loggedAt: DateTime.parse(map['logged_at'] as String),
        items: (map['items'] as List<dynamic>)
            .map((e) => FoodItem.fromMap(e as Map<String, dynamic>))
            .toList(),
        totalCalories: (map['total_calories'] as num).toInt(),
        totalProtein: (map['total_protein'] as num?)?.toDouble(),
        totalCarbs: (map['total_carbs'] as num?)?.toDouble(),
        totalFat: (map['total_fat'] as num?)?.toDouble(),
        totalFiber: (map['total_fiber'] as num?)?.toDouble(),
        feeling: (map['feeling'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toInt())),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'image_url': imageUrl,
        'logged_at': loggedAt.toIso8601String(),
        'items': items.map((e) => e.toMap()).toList(),
        'total_calories': totalCalories,
        'total_protein': totalProtein,
        'total_carbs': totalCarbs,
        'total_fat': totalFat,
        'total_fiber': totalFiber,
        if (feeling != null) 'feeling': feeling,
      };
}
