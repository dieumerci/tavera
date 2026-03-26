// ─── GroceryDeliveryService ───────────────────────────────────────────────────
//
// Abstract interface for grocery delivery integrations.
// Phase 2: architecture only — no live integrations.
// Phase 3: implement InstacartDeliveryService + AmazonFreshDeliveryService.

import '../models/grocery_list.dart';

abstract class GroceryDeliveryService {
  /// Human-readable name shown in the UI (e.g. 'Instacart').
  String get displayName;

  /// Whether the service is available in the user's region / has credentials.
  Future<bool> isAvailable();

  /// Adds all unchecked [items] to the user's cart on the delivery platform.
  Future<void> addItemsToCart(List<GroceryItem> items);

  /// Opens the delivery platform's checkout (deep link or in-app browser).
  Future<void> openCheckout();
}
