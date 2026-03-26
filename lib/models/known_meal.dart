import 'food_item.dart';

class KnownMeal {
  final String id;
  final String userId;
  final String name;
  final String fingerprint;
  final List<FoodItem> items;
  final int totalCalories;
  final int occurrenceCount;
  final DateTime lastLoggedAt;

  const KnownMeal({
    required this.id,
    required this.userId,
    required this.name,
    required this.fingerprint,
    required this.items,
    required this.totalCalories,
    required this.occurrenceCount,
    required this.lastLoggedAt,
  });

  KnownMeal copyWithName(String newName) => KnownMeal(
        id: id,
        userId: userId,
        name: newName,
        fingerprint: fingerprint,
        items: items,
        totalCalories: totalCalories,
        occurrenceCount: occurrenceCount,
        lastLoggedAt: lastLoggedAt,
      );

  factory KnownMeal.fromMap(Map<String, dynamic> map) => KnownMeal(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        fingerprint: map['fingerprint'] as String,
        items: (map['items'] as List<dynamic>)
            .map((e) => FoodItem.fromMap(e as Map<String, dynamic>))
            .toList(),
        totalCalories: (map['total_calories'] as num).toInt(),
        occurrenceCount: (map['occurrence_count'] as num).toInt(),
        lastLoggedAt: DateTime.parse(map['last_logged_at'] as String),
      );
}
