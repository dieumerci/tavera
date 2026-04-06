import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Environment values for the Tavera app.
///
/// Resolution order (highest priority wins):
///   1. --dart-define at build time  → compile-time constants (production builds)
///   2. .env file at runtime         → dotenv fallback (local development)
///   3. Empty string                 → no-op behaviour in services
///
/// Production build example:
///   flutter build ipa --release \
///     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ... \
///     --dart-define=REVENUECAT_API_KEY_IOS=appl_... \
///     --dart-define=POSTHOG_API_KEY=phc_...
///
/// Local development: copy .env.example → .env and fill in your credentials.
/// The dotenv fallback means you never need --dart-define flags locally.
class Env {
  Env._();

  // ── Supabase ─────────────────────────────────────────────────────────────
  // The anon key is intentionally safe to embed — it is a *public* credential
  // protected by Supabase's Row-Level Security policies, not an admin key.
  // Swap for your own project's values before open-sourcing this repository.
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hdtuezlbabsebkoucjhp.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
        '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhkdHVlemxiYWJzZWJrb3VjamhwIiwi'
        'cm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNzQ3MDksImV4cCI6MjA4OTg1MDcwOX0'
        '.6i2WwozUbjWGsRDRUKuNWiJetH13zu7-7VIW9WEYZJ4',
  );

  // ── PostHog ───────────────────────────────────────────────────────────────
  // No-op when empty — AnalyticsService silently disables itself.
  static const posthogApiKey = String.fromEnvironment(
    'POSTHOG_API_KEY',
    defaultValue: '',
  );

  // ── RevenueCat ────────────────────────────────────────────────────────────
  // Dart-define wins at build time; dotenv provides the local dev fallback so
  // you can test in-app purchases without passing --dart-define flags.
  // Use your platform-specific PUBLIC SDK key (appl_... / goog_... / test_...).
  // Never use the V2 secret key (sk_...) here — that is server-side only.

  static String get revenueCatApiKeyIos {
    const compileTime = String.fromEnvironment('REVENUECAT_API_KEY_IOS');
    if (compileTime.isNotEmpty) return compileTime;
    return dotenv.maybeGet('REVENUECAT_API_KEY_IOS') ?? '';
  }

  static String get revenueCatApiKeyAndroid {
    const compileTime = String.fromEnvironment('REVENUECAT_API_KEY_ANDROID');
    if (compileTime.isNotEmpty) return compileTime;
    return dotenv.maybeGet('REVENUECAT_API_KEY_ANDROID') ?? '';
  }
}
