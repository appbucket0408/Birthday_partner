import 'dart:async';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/gifting/draft_cubit.dart';
import 'package:birthday_app/features/gifting/draft_screen.dart';
import 'package:birthday_app/features/gifting/draft_state.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/gift.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/repositories/gift_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

/// A mocked DraftCubit -- same pattern as
/// test/features/gifting/catalog_screen_test.dart's `_MockCatalogCubit`.
/// Lets each test drop straight into the exact state it wants, with no real
/// GiftRepository or network round trip -- draft_cubit_test.dart already
/// covers the cubit's own branching; this file is about what the SCREEN
/// does with each state.
class _MockDraftCubit extends MockCubit<DraftState> implements DraftCubit {}

/// A real fake, not a mock -- same pattern as
/// test/features/gifting/draft_cubit_test.dart's `_FakeGift`. Used only by
/// the 23514/45005 tests below, which need the REAL `DraftCubit` (via the
/// real `DraftScreen`, not the mocked `DraftView`) so that reverting
/// `draft_cubit.dart`'s error-code mapping actually breaks them -- a mocked
/// cubit handed a pre-built `DraftError` would render correctly regardless
/// of whether the mapping in `draft_cubit.dart` exists at all.
class _FakeGift implements GiftRepository {
  _FakeGift({this.createDraftError});

  Object? createDraftError;

  @override
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  }) async {
    if (createDraftError != null) throw createDraftError!;
    return _gift();
  }

  @override
  Future<List<ServiceArea>> serviceAreas() async =>
      throw UnimplementedError('not used by DraftScreen');

  @override
  Future<List<Product>> productsIn(int serviceAreaId) async =>
      throw UnimplementedError('not used by DraftScreen');

  @override
  Future<List<DeliverySlot>> slotsIn(
    int serviceAreaId, {
    required DateTime onOrAfter,
  }) async =>
      throw UnimplementedError('not used by DraftScreen');

  @override
  Future<List<Gift>> myGifts() async =>
      throw UnimplementedError('not used by DraftScreen');
}

// Distinctive on purpose (fix round 1, item 1): a stale id-based label (e.g.
// 'Recipient #2') cannot accidentally match this.
const _recipientName = 'Priya Sharma';
const _recipientPersonId = 2;

final _product = Product(
  id: 3,
  serviceAreaId: 7,
  name: 'Chocolate Truffle',
  flavour: 'chocolate',
  size: '500g',
  priceMinor: 84905,
  imageUrl: null,
);

final _slot = DeliverySlot(
  id: 4,
  serviceAreaId: 7,
  slotDate: DateTime(2026, 6, 15),
  windowStart: '09:00',
  windowEnd: '11:00',
  capacity: 5,
  reserved: 1,
);

final _occasionDate = DateTime(2026, 6, 15);

Gift _gift() => Gift(
      id: 1,
      recipientPersonId: _recipientPersonId,
      productId: _product.id,
      slotId: _slot.id,
      occasionDate: _occasionDate,
      amountMinor: _product.priceMinor,
      status: GiftStatus.draft,
    );

void main() {
  late _MockDraftCubit cubit;

  setUp(() {
    cubit = _MockDraftCubit();
    when(
      () => cubit.create(
        recipientPersonId: _recipientPersonId,
        productId: _product.id,
        slotId: _slot.id,
        occasionDate: _occasionDate,
        message: null,
      ),
    ).thenAnswer((_) async {});
  });

  /// Pumps `DraftView` (not `DraftScreen`) with the mocked cubit injected
  /// directly via `BlocProvider.value` -- the same reason `CatalogView` is
  /// pumped instead of `CatalogScreen` in catalog_screen_test.dart.
  /// `RepositoryProvider<GiftRepository>` is deliberately absent: `DraftView`
  /// never reads one itself (only `DraftScreen`'s own `BlocProvider.create`
  /// does, and that is bypassed entirely by injecting the mock).
  Future<void> pumpView(
    WidgetTester tester,
    Stream<DraftState> stream, {
    required DraftState initialState,
  }) async {
    whenListen(cubit, stream, initialState: initialState);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DraftCubit>.value(
          value: cubit,
          child: DraftView(
            recipientPersonId: _recipientPersonId,
            recipientName: _recipientName,
            product: _product,
            slot: _slot,
            occasionDate: _occasionDate,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Pumps the REAL `DraftScreen` (not `DraftView` with a mocked cubit)
  /// backed by [gift] -- needed only by the 23514/45005 tests, which must
  /// exercise `draft_cubit.dart`'s actual error-code mapping, not a
  /// hand-built `DraftError` state a mock can be handed directly. Wraps the
  /// whole `MaterialApp`, not just `home`, with `RepositoryProvider` (see
  /// slot_picker_screen_test.dart's `pumpPicker` doc for why that scoping
  /// matters once anything reads the provider during a widget's own build).
  Future<void> pumpRealDraftScreen(WidgetTester tester, _FakeGift gift) async {
    await tester.pumpWidget(
      RepositoryProvider<GiftRepository>.value(
        value: gift,
        child: MaterialApp(
          home: DraftScreen(
            recipientPersonId: _recipientPersonId,
            recipientName: _recipientName,
            product: _product,
            slot: _slot,
            occasionDate: _occasionDate,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // 1 (fix round 1, item 1). The recipient's ACTUAL name renders, not an
  // id-based label -- `giftDraftRecipientTemplate` was 'Recipient #%s' until
  // this fix round; a stale id-based label must not silently pass here.
  testWidgets(
      "the recipient's actual name renders on the draft screen, not an "
      'id-based label', (tester) async {
    await pumpView(
      tester,
      const Stream<DraftState>.empty(),
      initialState: const DraftIdle(),
    );

    expect(
      find.text(
        AppStrings.giftDraftRecipientTemplate.replaceFirst(
          '%s',
          _recipientName,
        ),
      ),
      findsOneWidget,
    );
    // The regression this guards: a label built from the id alone (what
    // shipped before this fix round) must not be present alongside, or
    // instead of, the name.
    expect(find.textContaining('#$_recipientPersonId'), findsNothing);
  });

  // 2 (Amendment B3). On success, the hold notice renders BOTH strings and
  // the see-my-gifts action -- built via a StreamController, not an
  // `initialState`, because BlocConsumer's `listener` (which shows the
  // dialog) only fires on a state CHANGE delivered through the stream, never
  // for the state the widget was mounted with.
  testWidgets(
      'the success state renders the hold-notice title, body, and the '
      'see-my-gifts action', (tester) async {
    final controller = StreamController<DraftState>();
    addTearDown(controller.close);
    await pumpView(
      tester,
      controller.stream,
      initialState: const DraftSaving(),
    );

    controller.add(DraftCreated(_gift()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.giftHoldNoticeTitle), findsOneWidget);
    expect(find.text(AppStrings.giftHoldNoticeBody), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, AppStrings.giftSeeMyGifts),
      findsOneWidget,
    );
  });

  // 3 (Amendment B3, the enforceable guard). The rendered notice must not
  // contain forward-looking payment language -- this is what makes the
  // honesty rule a regression that actually fails a build, rather than a
  // comment a later edit can drift away from unnoticed.
  testWidgets(
      'the hold notice contains no forward-looking payment language',
      (tester) async {
    final controller = StreamController<DraftState>();
    addTearDown(controller.close);
    await pumpView(
      tester,
      controller.stream,
      initialState: const DraftSaving(),
    );

    controller.add(DraftCreated(_gift()));
    await tester.pumpAndSettle();

    final title =
        tester.widget<Text>(find.text(AppStrings.giftHoldNoticeTitle)).data ??
            '';
    final body =
        tester.widget<Text>(find.text(AppStrings.giftHoldNoticeBody)).data ??
            '';
    final lower = '$title $body'.toLowerCase();
    expect(lower, isNot(contains('coming soon')));
    expect(lower, isNot(contains('payment')));
    expect(lower, isNot(contains('checkout will')));
  });

  // 4. A 23514 (slot just filled) renders ITS OWN message, not the generic
  // failure -- through the REAL DraftCubit and its real error-code mapping,
  // not a pre-built DraftError state a mock can be handed regardless of
  // whether that mapping exists. This is what makes reverting
  // draft_cubit.dart's 23514 branch actually fail this test (see the
  // break-and-fail transcript in task-7-report.md).
  testWidgets(
      'tapping create with a 23514 failure renders giftSlotJustFilled, not '
      'the generic message', (tester) async {
    final gift = _FakeGift(
      createDraftError: const ServerFailure('slot full', code: '23514'),
    );
    await pumpRealDraftScreen(tester, gift);

    await tester.tap(find.byKey(const Key('gift_create')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.giftSlotJustFilled), findsOneWidget);
    expect(find.text(AppStrings.somethingWentWrong), findsNothing);
  });

  // 5. A 45005 (does not celebrate this person) renders ITS OWN message --
  // same reasoning as test 4, through the real DraftCubit.
  testWidgets(
      'tapping create with a 45005 failure renders giftNotCelebrating, not '
      'the generic message', (tester) async {
    final gift = _FakeGift(
      createDraftError:
          const ServerFailure('not celebrating', code: '45005'),
    );
    await pumpRealDraftScreen(tester, gift);

    await tester.tap(find.byKey(const Key('gift_create')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.giftNotCelebrating), findsOneWidget);
    expect(find.text(AppStrings.somethingWentWrong), findsNothing);
  });

  // Whole-branch review §8 fold-in: DraftError.slotFull was set by
  // DraftCubit (test 4 above) but never read by this screen -- either it had
  // to start driving something, or it had to go; draft_cubit_test.dart
  // already asserts on it directly (`.having((s) => s.slotFull, ...)`), so
  // removing the field would have broken a passing test for no gain. This
  // is what it now drives: a real way back to a live slot, gated on exactly
  // that flag and nothing else.
  testWidgets(
      'a slotFull DraftError shows a way back to a live slot, and tapping '
      'it pops back to the caller', (tester) async {
    whenListen(
      cubit,
      const Stream<DraftState>.empty(),
      initialState:
          const DraftError(AppStrings.giftSlotJustFilled, slotFull: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          // Keyed, and found by that key rather than by type: MaterialApp
          // supplies its OWN root Navigator, so find.byType(Navigator)
          // matches two and tester.state throws "Too many elements".
          key: const Key('caller_navigator'),
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => const Scaffold(key: Key('caller_screen')),
          ),
        ),
      ),
    );
    final navigator = tester.state<NavigatorState>(
      find.byKey(const Key('caller_navigator')),
    );
    navigator.push(
      MaterialPageRoute(
        builder: (_) => BlocProvider<DraftCubit>.value(
          value: cubit,
          child: DraftView(
            recipientPersonId: _recipientPersonId,
            recipientName: _recipientName,
            product: _product,
            slot: _slot,
            occasionDate: _occasionDate,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gift_pick_another_slot')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gift_pick_another_slot')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('caller_screen')), findsOneWidget);
    expect(find.byType(DraftView), findsNothing);
  });

  // The flip side: a non-slotFull DraftError (any other failure, including
  // 45005 above) must NOT show this action -- there is no "another slot" to
  // pick, and offering one would be a lie.
  testWidgets(
      'a non-slotFull DraftError does not show the way back to a live slot',
      (tester) async {
    await pumpView(
      tester,
      const Stream<DraftState>.empty(),
      initialState: const DraftError(AppStrings.somethingWentWrong),
    );

    expect(find.byKey(const Key('gift_pick_another_slot')), findsNothing);
  });

  // 6. The message field is capped at 280 characters, matching
  // `gifts_message_length` -- enforced client-side so an over-length
  // message is unreachable through the UI rather than round-tripping to the
  // database to be rejected.
  testWidgets('the message field is capped at 280 characters', (tester) async {
    await pumpView(
      tester,
      const Stream<DraftState>.empty(),
      initialState: const DraftIdle(),
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('gift_message_field')),
    );
    expect(field.maxLength, 280);
  });

  // 7. Tapping "Reserve this slot" calls DraftCubit.create with exactly the
  // recipient, product, slot and occasion date this screen was given, and
  // a null message when the field is left empty -- a callback test on a
  // fake/mock's call, not merely that the button renders (house rule).
  testWidgets(
      'tapping gift_create calls DraftCubit.create with the recipient, '
      'product, slot and occasion date this screen was given', (tester) async {
    await pumpView(
      tester,
      const Stream<DraftState>.empty(),
      initialState: const DraftIdle(),
    );

    await tester.tap(find.byKey(const Key('gift_create')));
    await tester.pump();

    verify(
      () => cubit.create(
        recipientPersonId: _recipientPersonId,
        productId: _product.id,
        slotId: _slot.id,
        occasionDate: _occasionDate,
        message: null,
      ),
    ).called(1);
  });

  // 8. Tapping "See my gifts" in the hold notice actually navigates to
  // '/gifts' -- arrival, not merely that the button exists (house rule).
  // Needs a real GoRouter, the same reason catalog_screen_test.dart's back
  // affordance test does.
  testWidgets(
      'tapping "See my gifts" in the hold notice actually navigates to '
      '/gifts', (tester) async {
    final controller = StreamController<DraftState>();
    addTearDown(controller.close);
    whenListen(cubit, controller.stream, initialState: const DraftSaving());
    final router = GoRouter(
      initialLocation: '/draft',
      routes: [
        GoRoute(
          path: '/draft',
          builder: (_, __) => BlocProvider<DraftCubit>.value(
            value: cubit,
            child: DraftView(
              recipientPersonId: _recipientPersonId,
              recipientName: _recipientName,
              product: _product,
              slot: _slot,
              occasionDate: _occasionDate,
            ),
          ),
        ),
        GoRoute(
          path: '/gifts',
          builder: (_, __) => const Scaffold(
            key: Key('gifts_destination'),
            body: Text('my gifts'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    controller.add(DraftCreated(_gift()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gifts_destination')), findsNothing);

    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.giftSeeMyGifts),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gifts_destination')), findsOneWidget);
  });
}
