import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/gifting/slot_picker_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/gift.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/repositories/gift_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real fake, not a mock -- same pattern as
/// test/features/gifting/catalog_cubit_test.dart's `_FakeGift`.
class _FakeGift implements GiftRepository {
  _FakeGift({this.slotsToReturn = const []});

  List<DeliverySlot> slotsToReturn;
  final List<DateTime> onOrAfterCalls = [];

  @override
  Future<List<DeliverySlot>> slotsIn(
    int serviceAreaId, {
    required DateTime onOrAfter,
  }) async {
    onOrAfterCalls.add(onOrAfter);
    return slotsToReturn;
  }

  @override
  Future<List<ServiceArea>> serviceAreas() async =>
      throw UnimplementedError('not used by SlotPickerScreen');

  @override
  Future<List<Product>> productsIn(int serviceAreaId) async =>
      throw UnimplementedError('not used by SlotPickerScreen');

  @override
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  }) async =>
      throw UnimplementedError('not used by SlotPickerScreen');

  @override
  Future<List<Gift>> myGifts() async =>
      throw UnimplementedError('not used by SlotPickerScreen');
}

const _birthday = Birthday(month: 6, day: 15);
DateTime _now() => DateTime(2026, 1, 1);
final _occasionDate = _birthday.nextOccurrence(_now());

final _product = Product(
  id: 1,
  serviceAreaId: 7,
  name: 'Chocolate Truffle',
  flavour: 'chocolate',
  size: '500g',
  priceMinor: 84905,
  imageUrl: null,
);

DeliverySlot _slot(
  int id, {
  DateTime? slotDate,
  String windowStart = '09:00',
  String windowEnd = '11:00',
  int capacity = 5,
  int reserved = 0,
}) =>
    DeliverySlot(
      id: id,
      serviceAreaId: 7,
      slotDate: slotDate ?? _occasionDate,
      windowStart: windowStart,
      windowEnd: windowEnd,
      capacity: capacity,
      reserved: reserved,
    );

void main() {
  Future<void> pumpPicker(WidgetTester tester, _FakeGift gift) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<GiftRepository>.value(
          value: gift,
          child: SlotPickerScreen(
            personId: 1,
            product: _product,
            birthday: _birthday,
            now: _now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 1. A slot with room renders its window and its remaining count, and its
  // onTap is non-null.
  testWidgets(
      'a slot with room renders its window and its remaining count, with a '
      'non-null onTap', (tester) async {
    final gift = _FakeGift(
      slotsToReturn: [_slot(1, capacity: 5, reserved: 2)],
    );

    await pumpPicker(tester, gift);

    expect(find.text('09:00–11:00'), findsOneWidget);
    expect(find.text('3 left'), findsOneWidget);
    final tile = tester.widget<ListTile>(find.byKey(const Key('slot_1')));
    expect(tile.onTap, isNotNull);
  });

  // 2. A FULL slot renders AppStrings.giftSlotFull and its onTap is NULL,
  // and tapping it pushes nothing -- Amendment A4. The reserve is real van
  // capacity, so the picker disables the row rather than letting the user
  // discover it by hitting the oversold constraint.
  testWidgets(
      'a FULL slot renders as Full with a null onTap, and tapping it '
      'pushes nothing', (tester) async {
    final gift = _FakeGift(
      slotsToReturn: [_slot(1, capacity: 3, reserved: 3)],
    );

    await pumpPicker(tester, gift);

    expect(find.text(AppStrings.giftSlotFull), findsOneWidget);
    final tile = tester.widget<ListTile>(find.byKey(const Key('slot_1')));
    expect(tile.onTap, isNull);

    expect(find.textContaining('coming in a later task'), findsNothing);
    await tester.tap(find.byKey(const Key('slot_1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('coming in a later task'), findsNothing);
  });

  // 3. An empty slot list renders AppStrings.giftNoSlots, not a blank
  // screen.
  testWidgets('an empty slot list renders AppStrings.giftNoSlots',
      (tester) async {
    final gift = _FakeGift(slotsToReturn: const []);

    await pumpPicker(tester, gift);

    expect(find.text(AppStrings.giftNoSlots), findsOneWidget);
  });

  // 4. The back affordance is present and enabled -- asserted on ARRIVAL
  // back at the pushing screen, not merely that a BackButton widget exists.
  // SlotPickerScreen is pushed (not routed via context.go), so the default
  // arrow is supplied by the framework -- see the class doc.
  testWidgets(
      'the back affordance actually returns to the screen that pushed it',
      (tester) async {
    final gift = _FakeGift(slotsToReturn: const []);
    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<GiftRepository>.value(
          value: gift,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('push_picker'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SlotPickerScreen(
                        personId: 1,
                        product: _product,
                        birthday: _birthday,
                        now: _now,
                      ),
                    ),
                  ),
                  child: const Text('push'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('push_picker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('push_picker')), findsNothing);

    final backButton = find.byType(BackButton);
    expect(backButton, findsOneWidget);
    expect(tester.widget<BackButton>(backButton).onPressed, isNull);
    // BackButton's own onPressed is null by design -- it falls back to
    // Navigator.maybePop internally -- so enabled-ness is proven by the pop
    // actually happening, not by that field.
    await tester.tap(backButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('push_picker')), findsOneWidget);
  });

  // 5 (Amendment A3). A slot on a LATER date than the occasion date is
  // excluded from the render, even though GiftRepository.slotsIn's
  // `onOrAfter` filter alone would have included it.
  testWidgets(
      'a slot on a later date than the occasion date is excluded from the '
      'render', (tester) async {
    final onDate = _slot(1, slotDate: _occasionDate, windowStart: '09:00');
    final laterDate = _slot(
      2,
      slotDate: _occasionDate.add(const Duration(days: 1)),
      windowStart: '14:00',
    );
    final gift = _FakeGift(slotsToReturn: [onDate, laterDate]);

    await pumpPicker(tester, gift);

    expect(find.byKey(const Key('slot_1')), findsOneWidget);
    expect(find.byKey(const Key('slot_2')), findsNothing);
  });
}
