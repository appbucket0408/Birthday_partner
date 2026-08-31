import 'dart:async';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/gifting/draft_cubit.dart';
import 'package:birthday_app/features/gifting/draft_state.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/gift.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/repositories/gift_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real fake, not a mock -- same pattern as
/// test/features/gifting/catalog_cubit_test.dart's `_FakeGift`.
class _FakeGift implements GiftRepository {
  _FakeGift({this.giftToReturn, this.createDraftError});

  Gift? giftToReturn;
  Object? createDraftError;

  int createDraftCalls = 0;
  DateTime? lastOccasionDate;

  /// When set, `createDraft()` suspends on this until it is completed --
  /// the same device `catalog_cubit_test.dart`'s `serviceAreasGate` uses to
  /// force two `create()` calls to genuinely overlap rather than merely
  /// racing to resolve on their own.
  Completer<void>? createDraftGate;

  @override
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  }) async {
    createDraftCalls++;
    lastOccasionDate = occasionDate;
    if (createDraftGate != null) await createDraftGate!.future;
    if (createDraftError != null) throw createDraftError!;
    return giftToReturn!;
  }

  @override
  Future<List<ServiceArea>> serviceAreas() async =>
      throw UnimplementedError('not used by DraftCubit');

  @override
  Future<List<Product>> productsIn(int serviceAreaId) async =>
      throw UnimplementedError('not used by DraftCubit');

  @override
  Future<List<DeliverySlot>> slotsIn(
    int serviceAreaId, {
    required DateTime onOrAfter,
  }) async =>
      throw UnimplementedError('not used by DraftCubit');

  @override
  Future<List<Gift>> myGifts() async =>
      throw UnimplementedError('not used by DraftCubit');
}

Gift _gift({DateTime? occasionDate}) => Gift(
      id: 1,
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: occasionDate ?? DateTime(2026, 6, 15),
      amountMinor: 84905,
      status: GiftStatus.draft,
    );

void main() {
  // 1. create() emits DraftSaving then DraftCreated carrying the returned
  // Gift.
  blocTest<DraftCubit, DraftState>(
    'create() emits DraftSaving then DraftCreated carrying the returned '
    'Gift',
    build: () => DraftCubit(_FakeGift(giftToReturn: _gift())),
    act: (c) => c.create(
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: DateTime(2026, 6, 15),
    ),
    expect: () => [
      isA<DraftSaving>(),
      isA<DraftCreated>().having((s) => s.gift.id, 'gift.id', 1),
    ],
  );

  // 2 (Amendment B1). `occasionDate` is a plain argument, forwarded to
  // `createDraft` VERBATIM -- never derived from a `Birthday` or a clock
  // inside this cubit. Assert the fake recorded the EXACT date passed in,
  // to the calendar day. This is the assertion that keeps the picker's
  // filtered date and the booked date from ever being able to disagree --
  // see draft_cubit.dart's class doc for why a second, independent
  // derivation here would be a bug.
  test(
      'create() forwards the supplied occasionDate to createDraft verbatim, '
      'never re-deriving it', () async {
    final gift = _FakeGift(giftToReturn: _gift());
    final cubit = DraftCubit(gift);
    final occasionDate = DateTime(2027, 3, 1);

    await cubit.create(
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: occasionDate,
    );

    expect(gift.lastOccasionDate, occasionDate);
  });

  // 3. A 23514 (slot just filled) surfaces as DraftError with slotFull true
  // and AppStrings.giftSlotJustFilled -- NOT the generic failure. Two users
  // racing for the last slot is a legitimate outcome, not a fault.
  blocTest<DraftCubit, DraftState>(
    'a 23514 surfaces as DraftError with slotFull true and '
    'giftSlotJustFilled',
    build: () => DraftCubit(
      _FakeGift(
        createDraftError: const ServerFailure('slot full', code: '23514'),
      ),
    ),
    act: (c) => c.create(
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: DateTime(2026, 6, 15),
    ),
    expect: () => [
      isA<DraftSaving>(),
      isA<DraftError>()
          .having((s) => s.message, 'message', AppStrings.giftSlotJustFilled)
          .having((s) => s.slotFull, 'slotFull', true),
    ],
  );

  // 4. A 45005 (does not celebrate this person) surfaces as DraftError with
  // AppStrings.giftNotCelebrating, and slotFull stays false.
  blocTest<DraftCubit, DraftState>(
    'a 45005 surfaces as DraftError with giftNotCelebrating',
    build: () => DraftCubit(
      _FakeGift(
        createDraftError:
            const ServerFailure('not celebrating', code: '45005'),
      ),
    ),
    act: (c) => c.create(
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: DateTime(2026, 6, 15),
    ),
    expect: () => [
      isA<DraftSaving>(),
      isA<DraftError>()
          .having((s) => s.message, 'message', AppStrings.giftNotCelebrating)
          .having((s) => s.slotFull, 'slotFull', false),
    ],
  );

  // 5. Any other ServerFailure surfaces with slotFull false and the
  // ServerFailure's own human message -- the discriminating assertion is
  // the exact message, not merely `isA<DraftError>()`, which would pass for
  // either branch. A non-AppFailure falls back to
  // AppStrings.somethingWentWrong.
  test(
      'any other ServerFailure surfaces with slotFull false and its own '
      "message, never 'Instance of'", () async {
    final gift = _FakeGift(
      createDraftError: const ServerFailure('boom from the server'),
    );
    final cubit = DraftCubit(gift);

    await cubit.create(
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: DateTime(2026, 6, 15),
    );

    final state = cubit.state;
    expect(state, isA<DraftError>());
    final error = state as DraftError;
    expect(error.message, 'boom from the server');
    expect(error.slotFull, false);
    expect(error.message, isNot(contains('Instance of')));
  });

  test('a non-AppFailure error falls back to AppStrings.somethingWentWrong',
      () async {
    final gift = _FakeGift(createDraftError: StateError('unexpected'));
    final cubit = DraftCubit(gift);

    await cubit.create(
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: DateTime(2026, 6, 15),
    );

    final state = cubit.state;
    expect(state, isA<DraftError>());
    expect((state as DraftError).message, AppStrings.somethingWentWrong);
    expect(state.slotFull, false);
  });

  // 6. A second create() while the first is in flight is ignored
  // (ReentrancyGuard). A double-tap here burns real delivery capacity, not
  // just a duplicate row. Built so the two calls genuinely OVERLAP: the
  // fake suspends createDraft() on a Completer, both create() calls are
  // fired WITHOUT awaiting the first, and only then is the gate completed.
  // ReentrancyGuard claims its key synchronously before the first await, so
  // a test that awaited the first call before firing the second would prove
  // nothing -- the guard always releases its key in a `finally` as soon as
  // the first call finishes, so a later, non-overlapping second call always
  // goes through regardless of whether the guard exists at all.
  test('a second create() while the first is in flight is ignored', () async {
    final gate = Completer<void>();
    final gift = _FakeGift(giftToReturn: _gift())..createDraftGate = gate;
    final cubit = DraftCubit(gift);

    final first = cubit.create(
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: DateTime(2026, 6, 15),
    );
    final second = cubit.create(
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: DateTime(2026, 6, 15),
    );
    gate.complete();
    await Future.wait([first, second]);

    expect(gift.createDraftCalls, 1);
  });
}
