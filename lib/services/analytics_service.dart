import 'package:posthog_flutter/posthog_flutter.dart';

import '../core/config/env.dart';

// ─── AnalyticsService ─────────────────────────────────────────────────────────
//
// Anti-corruption layer over PostHog. All analytics calls in the app go
// through here so the underlying vendor can be swapped without touching
// feature code.
//
// Behaviour:
//   • No-op when POSTHOG_API_KEY is empty (local dev / CI).
//   • Silently swallows every PostHog error — an analytics failure must
//     never surface to the user or crash the app.
//
// Initialise once in main() before runApp():
//   await AnalyticsService.initialise();
//
// Key event catalogue (grep for AnalyticsService.track to find call sites):
//   meal_logged          source: camera|gallery|barcode|quick_add, calories
//   paywall_shown        source: <screen_name>
//   challenge_created    type: <challenge_type>
//   challenge_joined     method: direct|invite_code
//   meal_plan_generated  —
//   known_meal_relogged  calories: <int>

class AnalyticsService {
  AnalyticsService._();

  static bool get _enabled => Env.posthogApiKey.isNotEmpty;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Call once in main() after WidgetsFlutterBinding.ensureInitialized().
  static Future<void> initialise() async {
    if (!_enabled) return;
    try {
      final config = PostHogConfig(Env.posthogApiKey)
        ..host = 'https://us.i.posthog.com'
        // Disable autocapture — we track events explicitly for cleaner data.
        ..captureApplicationLifecycleEvents = false
        ..debug = false;
      await Posthog().setup(config);
    } catch (_) {}
  }

  // ── Identity ──────────────────────────────────────────────────────────────

  /// Call after sign-in / session restore with the Supabase user ID.
  static Future<void> identify(
    String userId, {
    Map<String, Object>? properties,
  }) async {
    if (!_enabled) return;
    try {
      await Posthog().identify(
        userId: userId,
        userProperties: properties,
      );
    } catch (_) {}
  }

  /// Call on sign-out to dissociate the session from the user.
  static Future<void> reset() async {
    if (!_enabled) return;
    try {
      await Posthog().reset();
    } catch (_) {}
  }

  // ── Event tracking ────────────────────────────────────────────────────────

  /// Track a named event with optional properties.
  /// Values must be JSON-serialisable non-null Objects.
  /// Null values are silently dropped before forwarding to PostHog.
  static Future<void> track(
    String event, {
    Map<String, Object?>? properties,
  }) async {
    if (!_enabled) return;
    try {
      // Filter out null values — PostHog expects Map<String, Object>.
      final safe = properties == null
          ? null
          : Map<String, Object>.fromEntries(
              properties.entries
                  .where((e) => e.value != null)
                  .map((e) => MapEntry(e.key, e.value!)),
            );
      await Posthog().capture(eventName: event, properties: safe);
    } catch (_) {}
  }
}
