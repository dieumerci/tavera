import '../core/config/app_config.dart';

enum SubscriptionTier { free, premium }

enum Sex { male, female, other }

class UserProfile {
  final String id;
  final String? email;
  final String? name;
  final String? avatarUrl;
  final int calorieGoal;
  final SubscriptionTier tier;
  final bool onboardingCompleted;

  /// When true, display (carbs − fiber) in all macro UIs.
  /// Stored as `net_carbs_mode` in the profiles table.
  final bool netCarbsMode;

  // Body stats — all optional; used for BMR-based goal suggestions.
  final double? weightKg;
  final int? heightCm;
  final int? age;
  final Sex? sex;

  const UserProfile({
    required this.id,
    this.email,
    this.name,
    this.avatarUrl,
    this.calorieGoal = AppConfig.defaultCalorieGoal,
    this.tier = SubscriptionTier.free,
    this.onboardingCompleted = false,
    this.netCarbsMode = false,
    this.weightKg,
    this.heightCm,
    this.age,
    this.sex,
  });

  bool get isPremium => tier == SubscriptionTier.premium;

  /// Whether enough body stats have been entered to compute a BMR estimate.
  bool get canComputeBmr =>
      weightKg != null && heightCm != null && age != null && sex != null;

  /// Mifflin-St Jeor BMR × sedentary activity factor (1.2).
  /// Returns null when any required stat is missing.
  int? get suggestedCalorieGoal {
    if (!canComputeBmr) return null;
    final w = weightKg!;
    final h = heightCm!.toDouble();
    final a = age!.toDouble();
    final bmr = sex == Sex.female
        ? 10 * w + 6.25 * h - 5 * a - 161
        : 10 * w + 6.25 * h - 5 * a + 5;
    // Default to sedentary (×1.2) — user can pick higher in the goal editor.
    return (bmr * 1.2).round();
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
        id: map['id'] as String,
        email: map['email'] as String?,
        name: map['name'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        calorieGoal: (map['calorie_goal'] as int?) ?? AppConfig.defaultCalorieGoal,
        tier: SubscriptionTier.values.firstWhere(
          (e) => e.name == (map['subscription_tier'] ?? 'free'),
          orElse: () => SubscriptionTier.free,
        ),
        onboardingCompleted:
            (map['onboarding_completed'] as bool?) ?? false,
        netCarbsMode: (map['net_carbs_mode'] as bool?) ?? false,
        weightKg: (map['weight_kg'] as num?)?.toDouble(),
        heightCm: map['height_cm'] as int?,
        age: map['age'] as int?,
        sex: map['sex'] == null
            ? null
            : Sex.values.firstWhere(
                (e) => e.name == map['sex'],
                orElse: () => Sex.other,
              ),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'name': name,
        'avatar_url': avatarUrl,
        'calorie_goal': calorieGoal,
        'subscription_tier': tier.name,
        'onboarding_completed': onboardingCompleted,
        'net_carbs_mode': netCarbsMode,
        'weight_kg': weightKg,
        'height_cm': heightCm,
        'age': age,
        'sex': sex?.name,
      };

  UserProfile copyWith({
    String? name,
    String? avatarUrl,
    int? calorieGoal,
    SubscriptionTier? tier,
    bool? onboardingCompleted,
    bool? netCarbsMode,
    double? weightKg,
    int? heightCm,
    int? age,
    Sex? sex,
  }) =>
      UserProfile(
        id: id,
        email: email,
        name: name ?? this.name,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        calorieGoal: calorieGoal ?? this.calorieGoal,
        tier: tier ?? this.tier,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
        netCarbsMode: netCarbsMode ?? this.netCarbsMode,
        weightKg: weightKg ?? this.weightKg,
        heightCm: heightCm ?? this.heightCm,
        age: age ?? this.age,
        sex: sex ?? this.sex,
      );
}
