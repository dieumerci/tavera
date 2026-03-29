/// Converts a raw barcode string into every valid normalised variant.
///
/// Handles:
/// - Stripping non-digit characters (spaces, hyphens, etc.)
/// - UPC-A (12 digits) ↔ EAN-13 (13 digits with leading '0') conversion
/// - EAN-13 check-digit validation to avoid producing bogus codes
///
/// Callers should iterate [variants] when querying APIs or the local
/// products table, trying each until a match is found.
class BarcodeNormalizationService {
  BarcodeNormalizationService._();

  /// Returns every valid normalised form of [raw], including the original.
  ///
  /// Returns an empty list if [raw] contains no digits.
  static List<String> variants(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return [];

    final results = <String>{digits};

    if (digits.length == 12) {
      // UPC-A → EAN-13: prepend '0' and validate checksum.
      final ean13 = '0$digits';
      if (_validEan13Checksum(ean13)) results.add(ean13);
    } else if (digits.length == 13 && _validEan13Checksum(digits)) {
      // EAN-13 → UPC-A: strip leading '0' (only when the code starts with 0).
      if (digits.startsWith('0')) results.add(digits.substring(1));
    }

    return results.toList();
  }

  /// Returns true when [code] is a well-formed 13-digit EAN-13 barcode.
  ///
  /// Validates using the standard alternating ×1 / ×3 weight scheme.
  static bool isValidEan13(String code) => _validEan13Checksum(code);

  static bool _validEan13Checksum(String code) {
    if (code.length != 13) return false;
    if (!RegExp(r'^\d{13}$').hasMatch(code)) return false;

    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = int.parse(code[i]);
      sum += i.isEven ? d : d * 3;
    }
    final expectedCheck = (10 - (sum % 10)) % 10;
    return expectedCheck == int.parse(code[12]);
  }
}
