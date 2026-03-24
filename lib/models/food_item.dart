class FoodItem {
  final String name;
  final double portionSize;
  final String portionUnit;
  final int calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double confidenceScore;

  const FoodItem({
    required this.name,
    required this.portionSize,
    required this.portionUnit,
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.confidenceScore = 1.0,
  });

  factory FoodItem.fromMap(Map<String, dynamic> map) => FoodItem(
        name: map['name'] as String,
        portionSize: (map['portion_size'] as num).toDouble(),
        portionUnit: (map['portion_unit'] as String?) ?? 'g',
        calories: (map['calories'] as num).toInt(),
        protein: (map['protein'] as num?)?.toDouble(),
        carbs: (map['carbs'] as num?)?.toDouble(),
        fat: (map['fat'] as num?)?.toDouble(),
        confidenceScore: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'portion_size': portionSize,
        'portion_unit': portionUnit,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'confidence': confidenceScore,
      };

  /// Human-readable portion label, e.g. "150 g" or "1.5 cup".
  /// Drops the decimal when the value is a whole number.
  String get portionLabel {
    final sizeStr = portionSize == portionSize.roundToDouble()
        ? portionSize.toInt().toString()
        : portionSize.toStringAsFixed(1);
    return '$sizeStr $portionUnit';
  }

  FoodItem copyWith({
    String? name,
    double? portionSize,
    String? portionUnit,
    int? calories,
    double? protein,
    double? carbs,
    double? fat,
  }) =>
      FoodItem(
        name: name ?? this.name,
        portionSize: portionSize ?? this.portionSize,
        portionUnit: portionUnit ?? this.portionUnit,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        confidenceScore: confidenceScore,
      );
}
