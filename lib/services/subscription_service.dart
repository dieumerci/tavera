// ─── SubscriptionService ──────────────────────────────────────────────────────
//
// Anti-corruption layer between the rest of the app and whatever payment SDK
// is in use. All feature-gate checks call this service — never RevenueCat,
// StoreKit, or any other SDK directly. Swapping providers (or going
// fully server-side) means touching only this file and RevenueCatService.
//
// Decision chain for isPremium():
//   1. Dev override — short-circuits all checks during development.
//   2. RevenueCat entitlement — live entitlement status from the SDK, cached
//      by [revenueCatPremiumProvider] and refreshed on auth changes.
//   3. profiles.subscription_tier — DB fallback for when the SDK is not yet
//      configured (no --dart-define keys set) or the SDK call fails.
//   4. Defaults to false when nothing is available.
//
// To enable real subscription gating:
//   1. Set _devPremiumOverride = false.
//   2. Configure RevenueCat API keys via --dart-define.
//   3. The rest of the app requires no changes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/auth_controller.dart';
import '../models/user_profile.dart';
import 'revenue_cat_service.dart';

// ── RevenueCat status provider ────────────────────────────────────────────────
//
// Fetches and caches the RevenueCat premium status. Widget trees watching this
// rebuild when it completes or is invalidated (e.g. after a purchase or
// auth state change). Using .valueOrNull lets synchronous call-sites fall
// through to the DB check on first render without blocking.

final revenueCatPremiumProvider = FutureProvider<bool>((ref) async {
  return RevenueCatService.isPremium();
});

// ─────────────────────────────────────────────────────────────────────────────

class SubscriptionService {
  SubscriptionService._();

  // ── Dev override ─────────────────────────────────────────────────────────
  // Set to true to unlock all premium features locally without any SDK setup.
  // Flip to false before shipping to production or when testing paywall flow.
  static const bool _devPremiumOverride = true;

  // ── Primary gate ─────────────────────────────────────────────────────────

  /// Returns true when the current user has an active premium subscription.
  ///
  /// Synchronous — safe to call from build(). Uses the cached RevenueCat
  /// status via [revenueCatPremiumProvider]; falls back to the DB tier while
  /// the async fetch is in flight.
  static bool isPremium(WidgetRef ref) {
    if (_devPremiumOverride) return true;

    // RevenueCat entitlement (cached; null while loading → fall through)
    final rcStatus = ref.watch(revenueCatPremiumProvider).valueOrNull;
    if (rcStatus != null) return rcStatus;

    // DB fallback — ref.watch so the widget rebuilds when the profile stream
    // emits a new tier (e.g. after an external SQL update or webhook).
    final profile = ref.watch(userProfileProvider).valueOrNull;
    return _dbPremium(profile);
  }

  /// Async variant — awaits RevenueCat before returning. Use in one-off
  /// checks (e.g. post-purchase confirmation) rather than in build().
  static Future<bool> isPremiumAsync(WidgetRef ref) async {
    if (_devPremiumOverride) return true;
    return ref.read(revenueCatPremiumProvider.future);
  }

  // ── Convenience getters ──────────────────────────────────────────────────

  /// The current user's subscription tier, or `free` when not loaded.
  static SubscriptionTier tier(WidgetRef ref) {
    return ref.watch(userProfileProvider).valueOrNull?.tier
        ?? SubscriptionTier.free;
  }

  // ── Feature flags ────────────────────────────────────────────────────────

  static bool canAccessCoaching(WidgetRef ref) => isPremium(ref);
  static bool canAccessMealPlanner(WidgetRef ref) => isPremium(ref);

  /// All tiers can join challenges; only premium can create them.
  static bool canJoinChallenge(WidgetRef ref) => true;
  static bool canCreateChallenge(WidgetRef ref) => isPremium(ref);

  // ── Internal ─────────────────────────────────────────────────────────────

  static bool _dbPremium(UserProfile? profile) {
    if (profile == null) return false;
    return profile.isPremium;
  }
}
