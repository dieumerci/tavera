/// Compile-time environment values injected via --dart-define.
///
/// Build with secrets:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ... \
///     --dart-define=OPENAI_API_KEY=sk-...
///
/// defaultValue falls back to the dev keys so local runs work without
/// any extra flags. Remove the defaults before open-sourcing the repo.
class Env {
  Env._();

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

  /// PostHog project API key.
  /// Leave empty during local development — AnalyticsService becomes a no-op.
  /// Set via --dart-define=POSTHOG_API_KEY=phc_... for staging/production builds.
  static const posthogApiKey = String.fromEnvironment(
    'POSTHOG_API_KEY',
    defaultValue: '',
  );

  /// RevenueCat iOS API key (Apple App Store).
  /// Obtain from RevenueCat dashboard → Project Settings → API Keys.
  /// Set via --dart-define=REVENUECAT_API_KEY_IOS=appl_...
  static const revenueCatApiKeyIos = String.fromEnvironment(
    'REVENUECAT_API_KEY_IOS',
    defaultValue: '',
  );

  /// RevenueCat Android API key (Google Play Store).
  /// Set via --dart-define=REVENUECAT_API_KEY_ANDROID=goog_...
  static const revenueCatApiKeyAndroid = String.fromEnvironment(
    'REVENUECAT_API_KEY_ANDROID',
    defaultValue: '',
  );
}
