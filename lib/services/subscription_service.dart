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
  static const bool _devPremiumOverride = false;

  // ── Primary gate ─────────────────────────────────────────────────────────

  /// Returns true when the current user has an active premium subscription.
  ///
  /// Synchronous — safe to call from build(). Decision order:
  ///   1. Dev override — short-circuits all checks when set to true.
  ///   2. DB profile tier — checked first so that server-granted premium
  ///      (test accounts, SQL upgrades, RevenueCat webhook) works immediately
  ///      without depending on the SDK being correctly configured.
  ///   3. RevenueCat live entitlement — authoritative signal for real IAP
  ///      subscriptions. Checked second so a live subscriber whose webhook
  ///      hasn't synced yet still gets access.
  ///   4. Defaults to false when neither source confirms premium.
  ///
  /// Checking DB first also ensures the test account (preview@tavera.app)
  /// works regardless of RevenueCat SDK key configuration, since the test
  /// project intentionally uses SQL-granted tiers rather than real IAP.
  static bool isPremium(WidgetRef ref) {
    if (_devPremiumOverride) return true;

    // DB profile — authoritative for SQL-granted tiers & test accounts.
    // ref.watch ensures the widget rebuilds when the Realtime stream emits
    // a new tier (e.g. after a webhook updates subscription_tier).
    final profile = ref.watch(userProfileProvider).valueOrNull;
    if (_dbPremium(profile)) return true;

    // RevenueCat — live entitlement for real IAP subscribers.
    // valueOrNull is null while the async fetch is in flight — we fall
    // through to the false default rather than incorrectly blocking access.
    final rcStatus = ref.watch(revenueCatPremiumProvider).valueOrNull;
    return rcStatus ?? false;
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
