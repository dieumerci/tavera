import '../models/food_item.dart';

/// Converts a [products] table row into a [FoodItem] ready for logging.
///
/// Handles both liquid (ml) and solid (g) product types.
/// Per-100-unit macros are scaled to the actual serving size.
class NutritionResolutionService {
  NutritionResolutionService._();

  /// Creates a [FoodItem] from [productRow] (a row from the [products] table).
  ///
  /// [sizeOverride] replaces the product's default serving size — useful
  /// when the user selects a custom portion on the confirmation sheet.
  static FoodItem resolve(
    Map<String, dynamic> productRow, {
    double? sizeOverride,
  }) {
    final brand = productRow['brand'] as String;
    final name = productRow['canonical_name'] as String;
    final displayName = '$brand $name';
    final confidence = (productRow['confidence'] as num?)?.toDouble() ?? 1.0;

    final sizeMl = (productRow['size_ml'] as num?)?.toDouble();
    if (sizeMl != null) {
      return _resolveLiquid(
        displayName: displayName,
        row: productRow,
        sizeMl: sizeMl,
        sizeOverride: sizeOverride,
        confidence: confidence,
      );
    }

    return _resolveSolid(
      displayName: displayName,
      row: productRow,
      sizeOverride: sizeOverride,
      confidence: confidence,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static FoodItem _resolveLiquid({
    required String displayName,
    required Map<String, dynamic> row,
    required double sizeMl,
    double? sizeOverride,
    required double confidence,
  }) {
    final calsPer100 = (row['calories_per_100ml'] as num?)?.toDouble() ?? 0.0;
    final serving = sizeOverride ??
        (row['serving_size_ml'] as num?)?.toDouble() ??
        sizeMl;
    final factor = serving / 100.0;

    return FoodItem(
      name: displayName,
      portionSize: serving,
      portionUnit: 'ml',
      calories: (calsPer100 * factor).round(),
      protein: _macro(row, 'protein_per_100', factor),
      carbs: _macro(row, 'carbs_per_100', factor),
      fat: _macro(row, 'fat_per_100', factor),
      fiber: _macro(row, 'fiber_per_100', factor),
      confidenceScore: confidence,
    );
  }

  static FoodItem _resolveSolid({
    required String displayName,
    required Map<String, dynamic> row,
    double? sizeOverride,
    required double confidence,
  }) {
    final calsPer100 = (row['calories_per_100g'] as num?)?.toDouble() ?? 0.0;
    final defaultSize = (row['size_g'] as num?)?.toDouble() ??
        (row['serving_size_g'] as num?)?.toDouble() ??
        100.0;
    final serving = sizeOverride ?? defaultSize;
    final factor = serving / 100.0;

    return FoodItem(
      name: displayName,
      portionSize: serving,
      portionUnit: 'g',
      calories: (calsPer100 * factor).round(),
      protein: _macro(row, 'protein_per_100', factor),
      carbs: _macro(row, 'carbs_per_100', factor),
      fat: _macro(row, 'fat_per_100', factor),
      fiber: _macro(row, 'fiber_per_100', factor),
      confidenceScore: confidence,
    );
  }

  static double? _macro(Map<String, dynamic> row, String key, double factor) {
    final val = (row[key] as num?)?.toDouble();
    if (val == null) return null;
    return val * factor;
  }
}
