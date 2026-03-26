// ─── SubscriptionService ──────────────────────────────────────────────────────
//
// Anti-corruption layer between the rest of the app and whatever payment SDK
// is in use. All feature-gate checks call this service — never RevenueCat,
// StoreKit, or any other SDK directly. Swapping providers (or going
// fully server-side) means touching only this file.
//
// Phase 2 implementation strategy:
//   1. For now the truth is the `subscription_tier` column in `profiles`.
//      The AuthController already loads this into UserProfile.
//   2. When RevenueCat is integrated, add a RevenueCat.isConfigured() check
//      first; if true, use EntitlementInfo; otherwise fall back to DB.
//   3. Server-side receipt validation can be added here as a third path.
//
// Usage:
//   final isPremium = await SubscriptionService.isPremium(ref);
//
//   // Or gate UI inline:
//   if (!await SubscriptionService.isPremium(ref)) {
//     PaywallSheet.show(context);
//     return;
//   }

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/auth_controller.dart';
import '../models/user_profile.dart';

class SubscriptionService {
  SubscriptionService._();

  // ── Dev override ─────────────────────────────────────────────────────────
  // Set to true to unlock all premium features locally without a DB write.
  // Flip back to false before shipping to production.
  // ignore: dead_code
  static const bool _devPremiumOverride = true;

  // ── Primary gate ─────────────────────────────────────────────────────────

  /// Returns true when the current user has an active premium subscription.
  ///
  /// Decision chain:
  ///   1. RevenueCat entitlement (when SDK is integrated — stub for now).
  ///   2. `profiles.subscription_tier` from the DB (current implementation).
  ///   3. Defaults to `false` when the profile is unavailable.
  static bool isPremium(WidgetRef ref) {
    final profile = ref.read(userProfileProvider).valueOrNull;
    return _checkPremium(profile);
  }

  /// Async variant — awaits the profile if it hasn't loaded yet.
  static Future<bool> isPremiumAsync(WidgetRef ref) async {
    final profileAsync = ref.read(userProfileProvider);
    final profile = await profileAsync.when(
      data: (p) async => p,
      loading: () => ref.read(userProfileProvider.future),
      error: (_, __) async => null,
    );
    return _checkPremium(profile);
  }

  // ── Convenience getters ──────────────────────────────────────────────────

  /// The current user's subscription tier, or `free` when not loaded.
  static SubscriptionTier tier(WidgetRef ref) {
    return ref.read(userProfileProvider).valueOrNull?.tier
        ?? SubscriptionTier.free;
  }

  // ── Feature flags ────────────────────────────────────────────────────────
  // These make call-site intent explicit and allow granular per-feature
  // gating (e.g. some features could be on a higher tier).

  /// Coaching insights require premium.
  static bool canAccessCoaching(WidgetRef ref) => isPremium(ref);

  /// Meal planner requires premium.
  static bool canAccessMealPlanner(WidgetRef ref) => isPremium(ref);

  /// Social challenges are available to all tiers (free users can join but
  /// cannot create — gated at the challenge creation action).
  static bool canJoinChallenge(WidgetRef ref) => true;

  /// Creating a challenge requires premium.
  static bool canCreateChallenge(WidgetRef ref) => isPremium(ref);

  // ── Internal ─────────────────────────────────────────────────────────────

  static bool _checkPremium(UserProfile? profile) {
    if (_devPremiumOverride) return true;
    if (profile == null) return false;
    // Phase 2 hook: if RevenueCat is configured and returns a result, trust it.
    // For now, trust the DB column.
    return profile.isPremium;
  }
}
