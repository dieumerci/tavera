class AppConfig {
  AppConfig._();

  static const supabaseUrl = 'https://hdtuezlbabsebkoucjhp.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhkdHVlemxiYWJzZWJrb3VjamhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNzQ3MDksImV4cCI6MjA4OTg1MDcwOX0.6i2WwozUbjWGsRDRUKuNWiJetH13zu7-7VIW9WEYZJ4';

  // Free tier enforcement
  static const freeDailyLogLimit = 3;

  // Pricing
  static const premiumMonthlyPrice = '\$4.99/month';
}
