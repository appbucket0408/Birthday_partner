import 'package:birthday_app/models/gift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GiftStatus.fromWire', () {
    test('maps every state the database can emit', () {
      expect(GiftStatus.fromWire('draft'), GiftStatus.draft);
      expect(GiftStatus.fromWire('paid'), GiftStatus.paid);
      expect(GiftStatus.fromWire('awaiting_confirm'),
          GiftStatus.awaitingConfirm);
      expect(GiftStatus.fromWire('confirmed'), GiftStatus.confirmed);
      expect(GiftStatus.fromWire('placed'), GiftStatus.placed);
      expect(GiftStatus.fromWire('out_for_delivery'),
          GiftStatus.outForDelivery);
      expect(GiftStatus.fromWire('delivered'), GiftStatus.delivered);
      expect(GiftStatus.fromWire('expired'), GiftStatus.expired);
      expect(GiftStatus.fromWire('declined'), GiftStatus.declined);
      expect(GiftStatus.fromWire('delivery_failed'),
          GiftStatus.deliveryFailed);
      expect(GiftStatus.fromWire('refunded'), GiftStatus.refunded);
    });

    // A server that grows a twelfth state must not crash a gift list. The
    // enum has eleven members and the DB enum has eleven; this guards the
    // gap opening later.
    test('an unrecognised state falls back rather than throwing', () {
      expect(GiftStatus.fromWire('teleported'), GiftStatus.unknown);
    });
  });

  group('isHoldExpired', () {
    test('a draft past its hold is expired', () {
      final g = Gift(
        id: 1,
        recipientPersonId: 1,
        productId: 1,
        slotId: 1,
        occasionDate: DateTime(2026, 9, 6),
        amountMinor: 50000,
        status: GiftStatus.draft,
        slotHoldExpiresAt: DateTime(2026, 8, 30, 10, 0),
      );
      expect(g.isHoldExpiredAt(DateTime(2026, 8, 30, 10, 1)), isTrue);
      expect(g.isHoldExpiredAt(DateTime(2026, 8, 30, 9, 59)), isFalse);
    });

    // Only a draft holds a slot. A paid gift past that timestamp is not
    // "expired" in any sense the user should be shown.
    test('a non-draft is never reported as hold-expired', () {
      final g = Gift(
        id: 1,
        recipientPersonId: 1,
        productId: 1,
        slotId: 1,
        occasionDate: DateTime(2026, 9, 6),
        amountMinor: 50000,
        status: GiftStatus.paid,
        slotHoldExpiresAt: DateTime(2026, 8, 30, 10, 0),
      );
      expect(g.isHoldExpiredAt(DateTime(2026, 8, 30, 11, 0)), isFalse);
    });
  });
}
