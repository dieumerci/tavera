import 'package:flutter/services.dart';

// ─── HapticService ────────────────────────────────────────────────────────────
//
// Centralised haptic feedback layer. All haptics in the app must go through
// this service so that weight, pattern, and accessibility tuning can be changed
// in one place without touching every call site.
//
// Design intent (production rule):
//   heavy()     → primary confirmed actions: Log Meal, Create Challenge, Submit
//   medium()    → important interactions: capture photo, save form, delete
//   selection() → lightweight UI feedback: tab switch, chip tap, toggle, focus

class HapticService {
  HapticService._();

  /// Primary confirmed action — e.g. "Log Meal", "Get Started", "Submit".
  static Future<void> heavy() => HapticFeedback.heavyImpact();

  /// Important interaction — e.g. photo capture, form save, delete confirm.
  static Future<void> medium() => HapticFeedback.mediumImpact();

  /// Lightweight UI state change — e.g. tab switch, chip selection, focus.
  static Future<void> selection() => HapticFeedback.selectionClick();

  /// Alert or error — triple light pulse to signal something needs attention.
  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.heavyImpact();
  }

  /// Success celebration — used after meal saved, challenge completed, etc.
  static Future<void> success() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.lightImpact();
  }
}
