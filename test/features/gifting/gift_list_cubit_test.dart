import 'dart:async';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/gifting/gift_list_cubit.dart';
import 'package:birthday_app/features/gifting/gift_list_state.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/gift.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/repositories/gift_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real fake, not a mock -- same pattern as
/// test/features/gifting/draft_cubit_test.dart's `_FakeGift`.
class _FakeGift implements GiftRepository {
  _FakeGift({this.giftsToReturn = const [], this.myGiftsError});

  List<Gift> giftsToReturn;
  Object? myGiftsError;

  int myGiftsCalls = 0;

  /// When set, `myGifts()` suspends on this until it is completed -- the
  /// same device draft_cubit_test.dart's `createDraftGate` uses to force two
  /// calls to genuinely overlap rather than merely racing to resolve on
  /// their own.
  Completer<void>? myGiftsGate;

  @override
  Future<List<Gift>> myGifts() async {
    myGiftsCalls++;
    if (myGiftsGate != null) await myGiftsGate!.future;
    if (myGiftsError != null) throw myGiftsError!;
    return giftsToReturn;
  }

  @override
  Future<List<ServiceArea>> serviceAreas() async =>
      throw UnimplementedError('not used by GiftListCubit');

  @override
  Future<List<Product>> productsIn(int serviceAreaId) async =>
      throw UnimplementedError('not used by GiftListCubit');

  @override
  Future<List<DeliverySlot>> slotsIn(
    int serviceAreaId, {
    required DateTime onOrAfter,
  }) async =>
      throw UnimplementedError('not used by GiftListCubit');

  @override
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  }) async =>
      throw UnimplementedError('not used by GiftListCubit');
}

Gift _gift({
  int id = 1,
  GiftStatus status = GiftStatus.draft,
  DateTime? slotHoldExpiresAt,
}) =>
    Gift(
      id: id,
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: DateTime(2026, 6, 15),
      amountMinor: 84905,
      status: status,
      slotHoldExpiresAt: slotHoldExpiresAt,
    );

void main() {
  // 1. load() emits Loading then Loaded with the gifts newest-first --
  // GiftRepository.myGifts() already orders by created_at descending
  // server-side (Task 4), so this proves the cubit forwards that order
  // verbatim rather than re-sorting it into something else.
  blocTest<GiftListCubit, GiftListState>(
    'load() emits Loading then Loaded with the gifts in the order the '
    'repository returned them (newest-first)',
    build: () => GiftListCubit(
      _FakeGift(giftsToReturn: [_gift(id: 9), _gift(id: 1), _gift(id: 5)]),
    ),
    act: (c) => c.load(),
    expect: () => [
      isA<GiftListLoading>(),
      isA<GiftListLoaded>().having(
        (s) => s.gifts.map((g) => g.id).toList(),
        'gift ids, in order',
        [9, 1, 5],
      ),
    ],
  );

  // 2. An empty list emits a Loaded empty state, not an error.
  blocTest<GiftListCubit, GiftListState>(
    'an empty list emits a Loaded empty state, not an error',
    build: () => GiftListCubit(_FakeGift(giftsToReturn: const [])),
    act: (c) => c.load(),
    expect: () => [
      isA<GiftListLoading>(),
      isA<GiftListLoaded>().having((s) => s.gifts, 'gifts', isEmpty),
    ],
  );

  // 3. A draft past its hold is flagged via Gift.isHoldExpiredAt against the
  // INJECTED clock, not the real one. `injectedNow` is chosen far from the
  // real wall clock (2026-08-31 at the time this suite was written): the
  // fixture's slotHoldExpiresAt sits BEFORE injectedNow but AFTER the real
  // clock, so a cubit that fell back to DateTime.now() would compute
  // isHoldExpiredAt as false and this test would fail -- a test reading the
  // real clock is a time bomb, and this is the assertion that would catch
  // reverting to one.
  test(
      'a draft past its hold (against the injected clock) is flagged in '
      'expiredIds', () async {
    final injectedNow = DateTime(2030, 1, 1);
    final expiredGift = _gift(
      id: 1,
      status: GiftStatus.draft,
      slotHoldExpiresAt: DateTime(2029, 12, 31),
    );
    final liveGift = _gift(
      id: 2,
      status: GiftStatus.draft,
      slotHoldExpiresAt: DateTime(2030, 6, 1),
    );
    final gift = _FakeGift(giftsToReturn: [expiredGift, liveGift]);
    final cubit = GiftListCubit(gift, now: () => injectedNow);

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<GiftListLoaded>());
    expect((state as GiftListLoaded).expiredIds, {1});
  });

  // 4a. A failure surfaces with a human message.
  test('a ServerFailure surfaces with its own message, never "Instance of"',
      () async {
    final gift = _FakeGift(
      myGiftsError: const ServerFailure('boom from the server'),
    );
    final cubit = GiftListCubit(gift);

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<GiftListError>());
    expect((state as GiftListError).message, 'boom from the server');
    expect(state.message, isNot(contains('Instance of')));
  });

  // 4b. A non-AppFailure falls back to AppStrings.somethingWentWrong.
  test('a non-AppFailure error falls back to AppStrings.somethingWentWrong',
      () async {
    final gift = _FakeGift(myGiftsError: StateError('unexpected'));
    final cubit = GiftListCubit(gift);

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<GiftListError>());
    expect((state as GiftListError).message, AppStrings.somethingWentWrong);
  });

  // 5. A second load() while the first is in flight is ignored
  // (ReentrancyGuard). Built so the two calls genuinely OVERLAP: the fake
  // suspends myGifts() on a Completer, both load() calls are fired WITHOUT
  // awaiting the first, and only then is the gate completed -- the same
  // construction draft_cubit_test.dart's reentrancy test uses, for the same
  // reason (ReentrancyGuard claims its key synchronously, before the first
  // await, so a non-overlapping second call would prove nothing).
  test('a second load() while the first is in flight is ignored', () async {
    final gate = Completer<void>();
    final gift = _FakeGift(giftsToReturn: [_gift()])..myGiftsGate = gate;
    final cubit = GiftListCubit(gift);

    final first = cubit.load();
    final second = cubit.load();
    gate.complete();
    await Future.wait([first, second]);

    expect(gift.myGiftsCalls, 1);
  });
}
