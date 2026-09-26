import '../models/delivery_slot.dart';
import '../models/product.dart';
import '../models/service_area.dart';

/// Everything the ops console reads and writes: the catalog and the delivery
/// calendar. One responsibility; deliberately NOT folded into
/// [GiftRepository], and NOT a wrapper around it.
///
/// The separation is not stylistic. `GiftRepository`'s reads are shaped for a
/// buyer and would make this console impossible:
///
/// - `productsIn` filters `.eq(is_active, true)`. Staff need to SEE an
///   inactive product in order to reactivate it; a console built on that read
///   could never display the row it exists to edit.
/// - `slotsIn` takes a required `onOrAfter` bound, for someone picking a
///   future window. Staff need arbitrary ranges, including past dates, to
///   audit what was offered.
///
/// Writes are authorised server-side by `service_areas_staff_write`,
/// `products_staff_write` and `delivery_slots_staff_write`
/// (20260822000006_catalog_slots.sql:55-71), each `for all using
/// (private.is_staff())`. A non-staff caller reaching these methods gets an
/// RLS refusal, not a silent no-op.
abstract interface class OpsRepository {
  Future<List<ServiceArea>> allServiceAreas();

  /// Active AND inactive, unlike `GiftRepository.productsIn` — staff must see
  /// what they are about to reactivate.
  Future<List<Product>> allProductsIn(int serviceAreaId);

  Future<Product> createProduct({
    required int serviceAreaId,
    required String name,
    String? flavour,
    String? size,
    required int priceMinor,
  });

  Future<Product> setProductActive(int productId, {required bool isActive});

  /// Inclusive of both bounds, ordered by `slot_date` then `window_start`, so
  /// the screen never has to sort.
  Future<List<DeliverySlot>> slotsBetween(
    int serviceAreaId, {
    required DateTime from,
    required DateTime to,
  });

  Future<DeliverySlot> createSlot({
    required int serviceAreaId,
    required DateTime slotDate,
    required String windowStart,
    required String windowEnd,
    required int capacity,
  });

  Future<DeliverySlot> setSlotCapacity(int slotId, {required int capacity});
}
