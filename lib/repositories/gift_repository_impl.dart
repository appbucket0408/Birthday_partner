import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/result.dart';
import '../models/delivery_slot.dart';
import '../models/gift.dart';
import '../models/product.dart';
import '../models/service_area.dart';
import 'gift_repository.dart';

class GiftRepositoryImpl implements GiftRepository {
  const GiftRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ServiceArea>> serviceAreas() async {
    try {
      // service_areas_select_all hides nothing behind RLS -- is_active is
      // filtered here, not by the database.
      //
      // .order(name): whole-branch review §8 should-fix 7. Without it,
      // Postgres returns rows in whatever order it finds convenient (not
      // guaranteed to be insertion order), and CatalogCubit.load picks
      // areas.first.id as the default selection -- so both the default area
      // AND the dropdown's own order were nondeterministic. `name` is a
      // stable, always-present column, unlike `id` gaps or timestamps this
      // table doesn't have.
      final rows = await _client
          .from(ApiParams.serviceAreas)
          .select()
          .eq(ApiParams.isActive, true)
          .order(ApiParams.name);
      return (rows as List)
          .map((r) => ServiceArea.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<Product>> productsIn(int serviceAreaId) async {
    try {
      // .order(name): same reasoning as serviceAreas() above (whole-branch
      // review §8 should-fix 7). Ordered by name, not price, because this is
      // a catalog listing a shopper scans by product identity ("Classic
      // Chocolate Truffle") rather than by a price they haven't compared
      // yet -- and unlike price, name is guaranteed unique-enough per area
      // to give a stable, human-predictable order today.
      final rows = await _client
          .from(ApiParams.products)
          .select()
          .eq(ApiParams.serviceAreaId, serviceAreaId)
          .eq(ApiParams.isActive, true)
          .order(ApiParams.name);
      return (rows as List)
          .map((r) => Product.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<DeliverySlot>> slotsIn(
    int serviceAreaId, {
    required DateTime onOrAfter,
  }) async {
    try {
      final rows = await _client
          .from(ApiParams.deliverySlots)
          .select()
          .eq(ApiParams.serviceAreaId, serviceAreaId)
          .gte(
            ApiParams.slotDate,
            onOrAfter.toIso8601String().split('T').first,
          )
          .order(ApiParams.slotDate);
      return (rows as List)
          .map((r) => DeliverySlot.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  }) async {
    try {
      final row = await _client.rpc(
        ApiEndpoints.rpcCreateGift,
        params: {
          ApiParams.pRecipientPersonId: recipientPersonId,
          ApiParams.pProductId: productId,
          ApiParams.pSlotId: slotId,
          ApiParams.pOccasionDate:
              occasionDate.toIso8601String().split('T').first,
          ApiParams.pMessage: message,
        },
      );
      return Gift.fromRow(row as Map<String, dynamic>);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<Gift>> myGifts() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthFailure('no session');
    try {
      final rows = await _client
          .from(ApiParams.gifts)
          .select()
          .eq(ApiParams.senderProfileId, userId)
          .order(ApiParams.createdAt, ascending: false);
      return (rows as List)
          .map((r) => Gift.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapError(e);
    }
  }
}
