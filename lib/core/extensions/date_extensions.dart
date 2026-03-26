/// Date utility extensions used across controllers and edge-function payloads.
///
/// Centralises the ISO YYYY-MM-DD string formatting that was previously
/// hand-rolled in three separate controllers.
extension DateFormatting on DateTime {
  /// Returns the date component as an ISO 8601 date string (YYYY-MM-DD)
  /// using the *local* calendar — no timezone conversion.
  ///
  /// Equivalent to `DateFormat('yyyy-MM-dd').format(this)` but without the
  /// `intl` dependency, and always uses the instance's year/month/day fields
  /// directly, so there is no chance of a UTC-vs-local off-by-one error.
  ///
  /// Usage:
  ///   DateTime.now().toIsoDateString()          // "2026-03-26"
  ///   DateTime(2026, 1, 5).toIsoDateString()    // "2026-01-05"
  String toIsoDateString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
