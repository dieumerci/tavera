import 'food_item.dart';

/// The source that produced a product identification result.
enum MatchSource {
  /// Open Food Facts — exact barcode match.
  offExact,

  /// Open Food Facts — normalised barcode (e.g. UPC-A ↔ EAN-13 conversion).
  offNormalized,

  /// Local [products] table — barcode array match.
  localBarcode,

  /// Local [products] table — alias or brand+name text match.
  localAlias,

  /// Gemini OCR on product label image, matched against local [products] table.
  ocrMatch,

  /// No match found in any source.
  unresolved,
}

/// Result returned by [ProductIdentificationService].
///
/// [item] is null when the product could not be confidently identified
/// ([matchSource] == [MatchSource.unresolved] or [confidenceScore] < 0.5).
class ProductIdentificationResult {
  final FoodItem? item;
  final MatchSource matchSource;
  final double confidenceScore;

  /// Human-readable reason a fallback was used, if applicable.
  final String? fallbackReason;

  const ProductIdentificationResult({
    this.item,
    required this.matchSource,
    required this.confidenceScore,
    this.fallbackReason,
  });

  /// True when the result has a usable item with confidence ≥ 0.5.
  bool get resolved => item != null && confidenceScore >= 0.5;
}
