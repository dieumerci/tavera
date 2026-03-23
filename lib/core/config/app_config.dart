import 'env.dart';

class AppConfig {
  AppConfig._();

  // Delegate to Env so all secret reads go through the dart-define layer.
  static String get supabaseUrl => Env.supabaseUrl;
  static String get supabaseAnonKey => Env.supabaseAnonKey;

  // Free tier enforcement
  static const freeDailyLogLimit = 3;

  // Pricing
  static const premiumMonthlyPrice = '\$4.99/month';
}
