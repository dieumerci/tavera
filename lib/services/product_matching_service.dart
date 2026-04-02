import 'package:supabase_flutter/supabase_flutter.dart';

/// Abstract interface for querying the [products] table.
///
/// The live implementation uses Supabase RPC. Tests inject a mock
/// to avoid requiring a real database connection.
abstract class ProductMatchingService {
  Future<Map<String, dynamic>?> findByBarcode(String barcode);
  Future<Map<String, dynamic>?> findByAlias(String alias);
  Future<List<Map<String, dynamic>>> searchByBrandAndName(
    String brand,
    String name, {
    double? sizeMl,
  });
}

/// Supabase-backed implementation using the RPC helpers defined in
/// migration 009 ([find_product_by_barcode], [find_product_by_alias],
/// [search_products_by_brand_name]).
///
/// RPC calls are used instead of PostgREST array-filter syntax to avoid
/// quoting and encoding edge-cases with text[] columns.
class SupabaseProductMatchingService implements ProductMatchingService {
  final SupabaseClient _client;

  const SupabaseProductMatchingService(this._client);

  @override
  Future<Map<String, dynamic>?> findByBarcode(String barcode) async {
    final rows = await _client.rpc(
      'find_product_by_barcode',
      params: {'p_barcode': barcode},
    ) as List<dynamic>;
    if (rows.isEmpty) return null;
    return rows.first as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>?> findByAlias(String alias) async {
    final rows = await _client.rpc(
      'find_product_by_alias',
      params: {'p_alias': alias},
    ) as List<dynamic>;
    if (rows.isEmpty) return null;
    return rows.first as Map<String, dynamic>;
  }

  @override
  Future<List<Map<String, dynamic>>> searchByBrandAndName(
    String brand,
    String name, {
    double? sizeMl,
  }) async {
    final rows = await _client.rpc(
      'search_products_by_brand_name',
      params: {
        'p_brand': brand,
        'p_name': name,
        if (sizeMl != null) 'p_size_ml': sizeMl,
      },
    ) as List<dynamic>;
    return rows.cast<Map<String, dynamic>>();
  }
}
