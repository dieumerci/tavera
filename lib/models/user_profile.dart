enum SubscriptionTier { free, premium }

class UserProfile {
  final String id;
  final String? email;
  final String? name;
  final String? avatarUrl;
  final int calorieGoal;
  final SubscriptionTier tier;
  final bool onboardingCompleted;

  const UserProfile({
    required this.id,
    this.email,
    this.name,
    this.avatarUrl,
    this.calorieGoal = 2000,
    this.tier = SubscriptionTier.free,
    this.onboardingCompleted = false,
  });

  bool get isPremium => tier == SubscriptionTier.premium;

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
        id: map['id'] as String,
        email: map['email'] as String?,
        name: map['name'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        calorieGoal: (map['calorie_goal'] as int?) ?? 2000,
        tier: SubscriptionTier.values.firstWhere(
          (e) => e.name == (map['subscription_tier'] ?? 'free'),
          orElse: () => SubscriptionTier.free,
        ),
        onboardingCompleted: (map['onboarding_completed'] as bool?) ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'name': name,
        'avatar_url': avatarUrl,
        'calorie_goal': calorieGoal,
        'subscription_tier': tier.name,
        'onboarding_completed': onboardingCompleted,
      };

  UserProfile copyWith({
    String? name,
    String? avatarUrl,
    int? calorieGoal,
    SubscriptionTier? tier,
    bool? onboardingCompleted,
  }) =>
      UserProfile(
        id: id,
        email: email,
        name: name ?? this.name,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        calorieGoal: calorieGoal ?? this.calorieGoal,
        tier: tier ?? this.tier,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      );
}
