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

  // Defaults — single source of truth used by models, controllers, and UI.
  static const defaultCalorieGoal = 2000;
  static const defaultWaterGoalMl = 2000;

  /// Preset calorie targets shown in the goal-editor sheet and onboarding.
  static const caloriePresets = [1500, 1800, 2000, 2500, 3000];
}
