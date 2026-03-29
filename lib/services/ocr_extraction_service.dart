import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Structured product information extracted from a label image by Gemini OCR.
class OcrExtraction {
  final String? brand;
  final String? productName;
  final double? sizeMl;
  final double? sizeG;

  /// Barcode digits visible as printed text below the barcode symbol,
  /// if Gemini could read them from the label photo.
  final String? barcode;

  const OcrExtraction({
    this.brand,
    this.productName,
    this.sizeMl,
    this.sizeG,
    this.barcode,
  });

  /// True when at least one field useful for product matching was extracted.
  bool get hasUsableData => brand != null || productName != null;
}

/// Sends a product label image to the [identify-product] Edge Function
/// and returns structured product metadata extracted by Gemini 1.5 Flash.
///
/// This is the only service that talks to the Edge Function — barcode
/// normalisation and products-table matching remain in their own services.
class OcrExtractionService {
  OcrExtractionService._();

  /// Base64-encodes [imageBytes] and calls the [identify-product] edge function.
  ///
  /// Returns null if the call fails or Gemini cannot extract useful data.
  static Future<OcrExtraction?> extractFromImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final base64Image = base64Encode(imageBytes);
      final response =
          await Supabase.instance.client.functions.invoke(
        'identify-product',
        body: {
          'image_base64': base64Image,
          'mime_type': mimeType,
        },
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null) return null;

      return OcrExtraction(
        brand: data['brand'] as String?,
        productName: data['product_name'] as String?,
        sizeMl: (data['size_ml'] as num?)?.toDouble(),
        sizeG: (data['size_g'] as num?)?.toDouble(),
        barcode: data['barcode'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
