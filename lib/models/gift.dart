import '../api/api_params.dart';

enum GiftStatus {
  draft,
  paid,
  awaitingConfirm,
  confirmed,
  placed,
  outForDelivery,
  delivered,
  expired,
  declined,
  deliveryFailed,
  refunded,
  unknown;

  static GiftStatus fromWire(String value) => switch (value) {
        'draft' => GiftStatus.draft,
        'paid' => GiftStatus.paid,
        'awaiting_confirm' => GiftStatus.awaitingConfirm,
        'confirmed' => GiftStatus.confirmed,
        'placed' => GiftStatus.placed,
        'out_for_delivery' => GiftStatus.outForDelivery,
        'delivered' => GiftStatus.delivered,
        'expired' => GiftStatus.expired,
        'declined' => GiftStatus.declined,
        'delivery_failed' => GiftStatus.deliveryFailed,
        'refunded' => GiftStatus.refunded,
        _ => GiftStatus.unknown,
      };
}

/// A row in public.gifts, as the SENDER sees it.
///
/// [deliveryCity] is null until the recipient confirms — it is denormalised
/// onto the gift at confirmation precisely so the sender can learn the city
/// without any access to the addresses row, which RLS hides from them
/// entirely. In this phase nothing confirms, so it is always null.
class Gift {
  const Gift({
    required this.id,
    required this.recipientPersonId,
    required this.productId,
    required this.slotId,
    required this.occasionDate,
    required this.amountMinor,
    required this.status,
    this.message,
    this.deliveryCity,
    this.slotHoldExpiresAt,
  });

  final int id;
  final int recipientPersonId;
  final int productId;
  final int? slotId;
  final DateTime occasionDate;
  final int amountMinor;
  final GiftStatus status;
  final String? message;
  final String? deliveryCity;
  final DateTime? slotHoldExpiresAt;

  /// Only a draft holds a slot, so only a draft can have a hold that lapsed.
  bool isHoldExpiredAt(DateTime now) =>
      status == GiftStatus.draft &&
      slotHoldExpiresAt != null &&
      now.isAfter(slotHoldExpiresAt!);

  factory Gift.fromRow(Map<String, dynamic> row) => Gift(
        id: row[ApiParams.id] as int,
        recipientPersonId: row[ApiParams.recipientPersonId] as int,
        productId: row[ApiParams.productId] as int,
        slotId: row[ApiParams.slotId] as int?,
        occasionDate: DateTime.parse(row[ApiParams.occasionDate] as String),
        amountMinor: row[ApiParams.amountMinor] as int,
        status: GiftStatus.fromWire(row[ApiParams.status] as String),
        message: row[ApiParams.message] as String?,
        deliveryCity: row[ApiParams.deliveryCity] as String?,
        slotHoldExpiresAt: row[ApiParams.slotHoldExpiresAt] == null
            ? null
            : DateTime.parse(row[ApiParams.slotHoldExpiresAt] as String),
      );
}
