import 'package:birthday_app/models/delivery_slot.dart';
import 'package:flutter_test/flutter_test.dart';

DeliverySlot _slot({required int capacity, required int reserved}) =>
    DeliverySlot(
      id: 1,
      serviceAreaId: 1,
      slotDate: DateTime(2026, 9, 6),
      windowStart: '09:00',
      windowEnd: '11:00',
      capacity: capacity,
      reserved: reserved,
    );

void main() {
  test('remaining is capacity minus reserved', () {
    expect(_slot(capacity: 5, reserved: 2).remaining, 3);
  });

  test('a slot with room is bookable', () {
    expect(_slot(capacity: 5, reserved: 2).isBookable, isTrue);
  });

  // The screen disables a full slot rather than letting the user find out by
  // hitting the oversold constraint.
  test('a full slot is not bookable', () {
    expect(_slot(capacity: 2, reserved: 2).isBookable, isFalse);
    expect(_slot(capacity: 2, reserved: 2).remaining, 0);
  });

  // delivery_slots_not_oversold makes this impossible in the database, but the
  // client must not render a negative if a row ever arrives inconsistent.
  test('remaining never goes below zero', () {
    expect(_slot(capacity: 1, reserved: 3).remaining, 0);
    expect(_slot(capacity: 1, reserved: 3).isBookable, isFalse);
  });

  test('a zero-capacity slot is never bookable', () {
    expect(_slot(capacity: 0, reserved: 0).isBookable, isFalse);
  });
}
