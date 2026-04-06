// ─── RevenueCatService ────────────────────────────────────────────────────────
//
// Thin wrapper around the purchases_flutter SDK. All RevenueCat calls flow
// through here so the rest of the app stays agnostic of the payment SDK.
//
// Setup checklist (one-time, before production):
//   1. Create a RevenueCat project at app.revenuecat.com  ✅ done
//   2. Entitlement "Kazadi Inc Pro" created in RevenueCat  ✅ done
//   3. Configure products in App Store Connect + Google Play Console and link
//      them to the "Kazadi Inc Pro" entitlement inside RevenueCat
//   4. Keys available in two ways (both work):
//        a) Local dev: set REVENUECAT_API_KEY_IOS / REVENUECAT_API_KEY_ANDROID in .env
//        b) Production build: --dart-define=REVENUECAT_API_KEY_IOS=appl_...
//
// No-op behaviour: When neither key is set, every method returns null/false
// immediately so no calls are made to the SDK.

import 'dart:io';

import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/config/env.dart';

class RevenueCatService {
  RevenueCatService._();

  /// Identifier for the premium entitlement in the RevenueCat dashboard.
  /// Must match exactly what is configured under Entitlements in your
  /// RevenueCat project (app.revenuecat.com → Entitlements).
  static const _entitlementId = 'Kazadi Inc Pro';

  static bool get _enabled {
    if (Platform.isIOS) return Env.revenueCatApiKeyIos.isNotEmpty;
    if (Platform.isAndroid) return Env.revenueCatApiKeyAndroid.isNotEmpty;
    return false;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Call once at app start — before any other RevenueCat method.
  static Future<void> configure() async {
    if (!_enabled) return;
    try {
      final apiKey = Platform.isIOS
          ? Env.revenueCatApiKeyIos
          : Env.revenueCatApiKeyAndroid;
      await Purchases.configure(PurchasesConfiguration(apiKey));
    } catch (_) {}
  }

  // ── Identity ──────────────────────────────────────────────────────────────

  /// Associate the RevenueCat customer record with a Supabase user ID.
  /// Call after the user signs in.
  static Future<void> identify(String userId) async {
    if (!_enabled) return;
    try {
      await Purchases.logIn(userId);
    } catch (_) {}
  }

  /// Detach the RevenueCat customer record. Call after sign-out.
  static Future<void> reset() async {
    if (!_enabled) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  // ── Entitlement check ─────────────────────────────────────────────────────

  /// Returns `true` when the current customer has an active "premium"
  /// entitlement. Hits a local cache after the first network fetch.
  static Future<bool> isPremium() async {
    if (!_enabled) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(_entitlementId);
    } catch (_) {
      return false;
    }
  }

  // ── Offerings ─────────────────────────────────────────────────────────────

  /// Returns the current (default) offering from RevenueCat, or `null` when
  /// the SDK is not configured or no offerings are available yet.
  static Future<Offering?> getDefaultOffering() async {
    if (!_enabled) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } catch (_) {
      return null;
    }
  }

  // ── Purchase ──────────────────────────────────────────────────────────────

  /// Initiates a purchase for [package]. Returns `true` when the "premium"
  /// entitlement becomes active after purchase.
  ///
  /// Returns `false` on user cancellation or SDK not configured.
  /// Rethrows any unexpected [PurchasesError] so the UI can surface it.
  static Future<bool> purchasePackage(Package package) async {
    if (!_enabled) return false;
    try {
      final result = await Purchases.purchasePackage(package);
      return result.customerInfo.entitlements.active.containsKey(_entitlementId);
    } on PurchasesError catch (e) {
      if (e.code == PurchasesErrorCode.purchaseCancelledError) return false;
      rethrow;
    } catch (_) {
      return false;
    }
  }

  // ── Restore ───────────────────────────────────────────────────────────────

  /// Restores previous purchases. Returns `true` when premium is found.
  static Future<bool> restore() async {
    if (!_enabled) return false;
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.containsKey(_entitlementId);
    } catch (_) {
      return false;
    }
  }
}
