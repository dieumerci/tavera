// Tavera widget tests
// Full integration tests require a real Supabase instance.
// Unit-level tests for models and controllers live here.

import 'package:flutter_test/flutter_test.dart';
import 'package:tavera/models/food_item.dart';
import 'package:tavera/models/meal_log.dart';

void main() {
  group('FoodItem', () {
    test('fromMap parses correctly', () {
      final map = {
        'name': 'Chicken breast',
        'portion_size': 150,
        'portion_unit': 'g',
        'calories': 248,
        'protein': 46.5,
        'carbs': 0.0,
        'fat': 5.4,
        'confidence': 0.95,
      };
      final item = FoodItem.fromMap(map);
      expect(item.name, 'Chicken breast');
      expect(item.calories, 248);
      expect(item.protein, 46.5);
    });

    test('copyWith preserves unchanged fields', () {
      const item = FoodItem(
        name: 'Rice',
        portionSize: 200,
        portionUnit: 'g',
        calories: 260,
      );
      final updated = item.copyWith(calories: 300);
      expect(updated.name, 'Rice');
      expect(updated.calories, 300);
      expect(updated.portionSize, 200);
    });
  });

  group('MealLog', () {
    test('totalCalories survives round-trip serialisation', () {
      final log = MealLog(
        id: 'test-id',
        userId: 'user-id',
        loggedAt: DateTime(2026, 3, 23, 12, 0),
        items: const [
          FoodItem(name: 'Apple', portionSize: 180, portionUnit: 'g', calories: 94),
          FoodItem(name: 'Peanut butter', portionSize: 30, portionUnit: 'g', calories: 188),
        ],
        totalCalories: 282,
      );
      final map = log.toMap();
      final restored = MealLog.fromMap(map);
      expect(restored.totalCalories, 282);
      expect(restored.items.length, 2);
    });
  });
}
