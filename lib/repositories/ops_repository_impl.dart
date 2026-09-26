import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../models/delivery_slot.dart';
import '../models/product.dart';
import '../models/service_area.dart';
import 'ops_repository.dart';

class OpsRepositoryImpl implements OpsRepository {
  const OpsRepositoryImpl(this._client);
  final SupabaseClient _client;

  /// `slot_date` is a Postgres `date`, and PostgREST wants it as `YYYY-MM-DD`.
  /// Built from the DateTime's own y/m/d fields rather than `toIso8601String`,
  /// which would carry a time and a zone: this host runs IST and Postgres runs
  /// UTC, and M3 Phase 1b shipped a fixture that passed by day and failed by
  /// night for exactly that reason.
  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<List<ServiceArea>> allServiceAreas() async {
    try {
      final rows = await _client
          .from(ApiParams.serviceAreas)
          .select()
          .order(ApiParams.name);
      return (rows as List)
          .map((r) => ServiceArea.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<Product>> allProductsIn(int serviceAreaId) async {
    try {
      // No .eq(isActive, true) -- that is the whole point of this repository
      // existing alongside GiftRepository.productsIn, which does filter it.
      // A console that hid inactive products could never show the row it
      // exists to reactivate.
      final rows = await _client
          .from(ApiParams.products)
          .select()
          .eq(ApiParams.serviceAreaId, serviceAreaId)
          .order(ApiParams.name);
      return (rows as List)
          .map((r) => Product.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<Product> createProduct({
    required int serviceAreaId,
    required String name,
    String? flavour,
    String? size,
    required int priceMinor,
  }) async {
    try {
      final row = await _client
          .from(ApiParams.products)
          .insert({
            ApiParams.serviceAreaId: serviceAreaId,
            ApiParams.name: name,
            ApiParams.flavour: flavour,
            ApiParams.size: size,
            ApiParams.priceMinor: priceMinor,
          })
          .select()
          .single();
      return Product.fromRow(row);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<Product> setProductActive(
    int productId, {
    required bool isActive,
  }) async {
    try {
      final row = await _client
          .from(ApiParams.products)
          .update({ApiParams.isActive: isActive})
          .eq(ApiParams.id, productId)
          .select()
          .single();
      return Product.fromRow(row);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<DeliverySlot>> slotsBetween(
    int serviceAreaId, {
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rows = await _client
          .from(ApiParams.deliverySlots)
          .select()
          .eq(ApiParams.serviceAreaId, serviceAreaId)
          .gte(ApiParams.slotDate, _dateOnly(from))
          .lte(ApiParams.slotDate, _dateOnly(to))
          .order(ApiParams.slotDate)
          .order(ApiParams.windowStart);
      return (rows as List)
          .map((r) => DeliverySlot.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<DeliverySlot> createSlot({
    required int serviceAreaId,
    required DateTime slotDate,
    required String windowStart,
    required String windowEnd,
    required int capacity,
  }) async {
    try {
      final row = await _client
          .from(ApiParams.deliverySlots)
          .insert({
            ApiParams.serviceAreaId: serviceAreaId,
            ApiParams.slotDate: _dateOnly(slotDate),
            ApiParams.windowStart: windowStart,
            ApiParams.windowEnd: windowEnd,
            ApiParams.capacity: capacity,
          })
          .select()
          .single();
      return DeliverySlot.fromRow(row);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<DeliverySlot> setSlotCapacity(
    int slotId, {
    required int capacity,
  }) async {
    try {
      // `reserved` is never touched here -- private.reserve_slot owns it, and
      // delivery_slots_not_oversold (reserved <= capacity) rejects a capacity
      // below what is already held. The console validates first so the user
      // gets a real message instead of that constraint's bare 23514.
      final row = await _client
          .from(ApiParams.deliverySlots)
          .update({ApiParams.capacity: capacity})
          .eq(ApiParams.id, slotId)
          .select()
          .single();
      return DeliverySlot.fromRow(row);
    } catch (e) {
      throw mapError(e);
    }
  }
}
