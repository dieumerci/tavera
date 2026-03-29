import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/food_item.dart';
import '../models/product_match.dart';
import 'barcode_normalization_service.dart';
import 'nutrition_resolution_service.dart';
import 'product_matching_service.dart';

/// Orchestrates all product identification layers in priority order:
///
///   1. Open Food Facts — exact barcode
///   2. Open Food Facts — normalised barcode (UPC-A ↔ EAN-13)
///   3. Local [products] table — barcode array match
///   4. Local [products] table — alias / brand+name match  (via [identifyByText])
///
/// Results are cached in-memory for the app session to avoid duplicate
/// API calls when the user scans the same product multiple times.
///
/// [offLookup] is injectable for testing (pass `(_) async => null` to skip
/// network calls and exercise only the local-DB path).
class ProductIdentificationService {
  final ProductMatchingService _matcher;
  final Future<FoodItem?> Function(String barcode) _offLookup;
  final Map<String, ProductIdentificationResult> _cache = {};

  ProductIdentificationService(
    this._matcher, {
    Future<FoodItem?> Function(String barcode)? offLookup,
  }) : _offLookup = offLookup ?? _fetchFromOff;

  // ── Barcode identification ─────────────────────────────────────────────────

  /// Identifies a product by its scanned barcode string.
  ///
  /// Tries all fallback layers and caches the result keyed by [rawBarcode].
  /// Always returns a non-null result; check [resolved] before using [item].
  Future<ProductIdentificationResult> identifyByBarcode(
      String rawBarcode) async {
    final cacheKey = rawBarcode.trim();
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final variants = BarcodeNormalizationService.variants(rawBarcode);
    if (variants.isEmpty) {
      return _cache[cacheKey] = const ProductIdentificationResult(
        matchSource: MatchSource.unresolved,
        confidenceScore: 0.0,
        fallbackReason: 'barcode contains no digits',
      );
    }

    // Layer 1: Open Food Facts — exact barcode
    final offItem = await _offLookup(rawBarcode);
    if (offItem != null) {
      return _cache[cacheKey] = ProductIdentificationResult(
        item: offItem,
        matchSource: MatchSource.offExact,
        confidenceScore: 1.0,
      );
    }

    // Layer 2: Open Food Facts — normalised barcode variants
    for (final variant in variants) {
      if (variant == rawBarcode) continue;
      final item = await _offLookup(variant);
      if (item != null) {
        return _cache[cacheKey] = ProductIdentificationResult(
          item: item,
          matchSource: MatchSource.offNormalized,
          confidenceScore: 0.95,
          fallbackReason: 'normalised barcode: $variant',
        );
      }
    }

    // Layer 3: Local products table — all barcode variants
    for (final variant in variants) {
      final row = await _matcher.findByBarcode(variant);
      if (row != null) {
        return _cache[cacheKey] = ProductIdentificationResult(
          item: NutritionResolutionService.resolve(row),
          matchSource: MatchSource.localBarcode,
          confidenceScore: (row['confidence'] as num?)?.toDouble() ?? 1.0,
          fallbackReason:
              variant == rawBarcode ? null : 'normalised barcode: $variant',
        );
      }
    }

    return _cache[cacheKey] = const ProductIdentificationResult(
      matchSource: MatchSource.unresolved,
      confidenceScore: 0.0,
      fallbackReason:
          'barcode not found in Open Food Facts or local database',
    );
  }

  // ── Text / OCR identification ──────────────────────────────────────────────

  /// Identifies a product from [text] extracted by OCR or typed by the user.
  ///
  /// [brand] and [sizeMl] are optional hints that improve matching when
  /// multiple products share the same name or when size disambiguation is
  /// needed (e.g. 250 ml vs 330 ml cans).
  Future<ProductIdentificationResult> identifyByText(
    String text, {
    String? brand,
    double? sizeMl,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const ProductIdentificationResult(
        matchSource: MatchSource.unresolved,
        confidenceScore: 0.0,
        fallbackReason: 'empty text query',
      );
    }

    // Layer 4a: exact alias match
    final aliasRow = await _matcher.findByAlias(trimmed);
    if (aliasRow != null) {
      return ProductIdentificationResult(
        item: NutritionResolutionService.resolve(aliasRow),
        matchSource: MatchSource.localAlias,
        confidenceScore:
            (aliasRow['confidence'] as num?)?.toDouble() ?? 0.9,
      );
    }

    // Layer 4b: brand + name search with optional size disambiguation
    if (brand != null && brand.isNotEmpty) {
      final rows = await _matcher.searchByBrandAndName(
        brand,
        trimmed,
        sizeMl: sizeMl,
      );
      if (rows.isNotEmpty) {
        final row = rows.first;
        final confidence =
            sizeMl != null ? _sizeConfidence(row, sizeMl) : 0.8;
        return ProductIdentificationResult(
          item: NutritionResolutionService.resolve(row),
          matchSource: MatchSource.localAlias,
          confidenceScore: confidence,
          fallbackReason: 'brand+name text match',
        );
      }
    }

    return ProductIdentificationResult(
      matchSource: MatchSource.unresolved,
      confidenceScore: 0.0,
      fallbackReason: 'no match for text: "$trimmed"',
    );
  }

  // ── Open Food Facts ────────────────────────────────────────────────────────

  static Future<FoodItem?> _fetchFromOff(String barcode) async {
    try {
      final uri = Uri.parse(
        'https://world.openfoodfacts.org/api/v2/product/$barcode.json'
        '?fields=product_name,brands,nutriments,serving_quantity,serving_size',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final body = json.decode(response.body) as Map<String, dynamic>;
      if (body['status'] != 1) return null;

      final product = body['product'] as Map<String, dynamic>? ?? {};
      return _parseOffProduct(product);
    } catch (_) {
      return null;
    }
  }

  static FoodItem? _parseOffProduct(Map<String, dynamic> p) {
    final name = (p['product_name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;

    final brands = (p['brands'] as String? ?? '').trim();
    final displayName = brands.isNotEmpty ? '$name · $brands' : name;

    final n = p['nutriments'] as Map<String, dynamic>? ?? {};
    final kcalServing = (n['energy-kcal_serving'] as num?)?.toInt();
    final kcalPer100 = (n['energy-kcal_100g'] as num?)?.toInt() ??
        (n['energy-kcal'] as num?)?.toInt();
    final servingQty =
        (p['serving_quantity'] as num?)?.toDouble() ?? 100.0;

    final int kcal;
    final String portionUnit;
    final double portionSize;

    if (kcalServing != null && kcalServing > 0) {
      kcal = kcalServing;
      portionUnit = 'serving';
      portionSize = 1.0;
    } else if (kcalPer100 != null && kcalPer100 > 0) {
      kcal = ((kcalPer100 * servingQty) / 100).round();
      portionUnit = 'g';
      portionSize = servingQty;
    } else {
      return null;
    }
    if (kcal <= 0) return null;

    double? nutrient(String key) {
      final serving = (n['${key}_serving'] as num?)?.toDouble();
      if (serving != null && serving >= 0) return serving;
      final per100 = (n['${key}_100g'] as num?)?.toDouble();
      if (per100 != null && per100 >= 0) return per100 * servingQty / 100;
      return null;
    }

    return FoodItem(
      name: displayName,
      portionSize: portionSize,
      portionUnit: portionUnit,
      calories: kcal,
      protein: nutrient('proteins'),
      carbs: nutrient('carbohydrates'),
      fat: nutrient('fat'),
      confidenceScore: 1.0,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Confidence score [0.0–1.0] penalised by how far [row]'s size_ml
  /// deviates from [targetMl].  Exact match = 1.0, ±50 ml = 0.9,
  /// ±150 ml = 0.75, further = 0.5.
  static double _sizeConfidence(
      Map<String, dynamic> row, double targetMl) {
    final rowSize = (row['size_ml'] as num?)?.toDouble();
    if (rowSize == null) return 0.7;
    final diff = (rowSize - targetMl).abs();
    if (diff == 0) return 1.0;
    if (diff <= 50) return 0.9;
    if (diff <= 150) return 0.75;
    return 0.5;
  }
}

// ── Riverpod provider ─────────────────────────────────────────────────────────

final productIdentificationProvider =
    Provider<ProductIdentificationService>((ref) {
  final matcher =
      SupabaseProductMatchingService(Supabase.instance.client);
  return ProductIdentificationService(matcher);
});
