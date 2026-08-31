import '../models/delivery_slot.dart';
import '../models/gift.dart';
import '../models/product.dart';
import '../models/service_area.dart';

/// Everything the sender's gifting flow reads and writes. One responsibility;
/// deliberately not folded into GraphRepository or PersonRepository.
abstract interface class GiftRepository {
  Future<List<ServiceArea>> serviceAreas();

  Future<List<Product>> productsIn(int serviceAreaId);

  /// Slots for an area on or after [onOrAfter], with `capacity` and `reserved`
  /// so the picker can show what is left.
  Future<List<DeliverySlot>> slotsIn(
    int serviceAreaId, {
    required DateTime onOrAfter,
  });

  /// Drafts a gift and reserves the slot for fifteen minutes.
  ///
  /// Throws [ServerFailure] with code `45005` when the caller does not
  /// celebrate the recipient, and `23514` when the slot just filled -- that
  /// second one is a race two users hit legitimately, not a fault.
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  });

  /// The caller's own gifts. `deliveryCity` is null until the recipient
  /// confirms; nothing in this phase confirms.
  Future<List<Gift>> myGifts();
}
