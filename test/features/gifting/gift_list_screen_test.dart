import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/gifting/gift_list_cubit.dart';
import 'package:birthday_app/features/gifting/gift_list_screen.dart';
import 'package:birthday_app/features/gifting/gift_list_state.dart';
import 'package:birthday_app/models/gift.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

/// A mocked GiftListCubit -- same pattern as
/// test/features/gifting/draft_screen_test.dart's `_MockDraftCubit`.
/// gift_list_cubit_test.dart already covers the cubit's own branching
/// (newest-first order, the injected-clock hold-expiry flag, error mapping,
/// re-entrancy); this file is about what the SCREEN does with each state.
class _MockGiftListCubit extends MockCubit<GiftListState>
    implements GiftListCubit {}

Gift _gift({
  int id = 1,
  GiftStatus status = GiftStatus.draft,
  String? deliveryCity,
}) =>
    Gift(
      id: id,
      recipientPersonId: 2,
      productId: 3,
      slotId: 4,
      occasionDate: DateTime(2026, 6, 15),
      amountMinor: 84905,
      status: status,
      deliveryCity: deliveryCity,
    );

void main() {
  late _MockGiftListCubit cubit;

  setUp(() {
    cubit = _MockGiftListCubit();
    when(() => cubit.load()).thenAnswer((_) async {});
  });

  Future<void> pumpView(WidgetTester tester, GiftListState state) async {
    whenListen(cubit, const Stream<GiftListState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<GiftListCubit>.value(
          value: cubit,
          child: const GiftListView(),
        ),
      ),
    );
    await tester.pump();
  }

  // 1. Loading renders a spinner, nothing else.
  testWidgets('GiftListLoading renders a spinner', (tester) async {
    await pumpView(tester, const GiftListLoading());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('gift_list_empty')), findsNothing);
  });

  // 2. An empty Loaded state renders giftListEmpty, not a blank list.
  testWidgets('an empty GiftListLoaded renders giftListEmpty', (tester) async {
    await pumpView(tester, const GiftListLoaded([], {}));

    expect(find.text(AppStrings.giftListEmpty), findsOneWidget);
  });

  // 3. A gift with a null deliveryCity renders giftCityPending -- the
  // common case in this phase (spec §6: delivery_city is null until
  // confirmation, and nothing in this phase confirms). Rendering nothing
  // here would look like a bug, not the honest state it is.
  testWidgets(
      'a gift with a null deliveryCity renders giftCityPending, not a '
      'blank line', (tester) async {
    final gift = _gift();
    await pumpView(tester, GiftListLoaded([gift], const {}));

    final cityText =
        tester.widget<Text>(find.byKey(Key('gift_list_city_${gift.id}')));
    expect(cityText.data, AppStrings.giftCityPending);
  });

  // 4. A gift with a non-null deliveryCity renders giftCityTemplate with
  // the city substituted in, not giftCityPending.
  testWidgets(
      'a gift with a non-null deliveryCity renders giftCityTemplate with '
      'the city substituted', (tester) async {
    final gift = _gift(deliveryCity: 'Gurugram');
    await pumpView(tester, GiftListLoaded([gift], const {}));

    final cityText =
        tester.widget<Text>(find.byKey(Key('gift_list_city_${gift.id}')));
    expect(cityText.data, 'Delivering to Gurugram');
    expect(find.text(AppStrings.giftCityPending), findsNothing);
  });

  // 5. A gift whose id is in expiredIds renders giftHoldExpired; one that
  // is not does not. The cubit test already proves expiredIds is computed
  // correctly against the injected clock -- this proves the SCREEN reacts
  // to that set, per gift, rather than a per-screen flag.
  testWidgets(
      'giftHoldExpired renders only for a gift id present in expiredIds',
      (tester) async {
    final expired = _gift(id: 1);
    final notExpired = _gift(id: 2);
    await pumpView(
      tester,
      GiftListLoaded([expired, notExpired], const {1}),
    );
    // Both rows fit on-screen at the default test surface size, so no
    // resize is needed here (unlike the 12-row status test below).

    expect(
      find.byKey(const Key('gift_list_hold_expired_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('gift_list_hold_expired_2')),
      findsNothing,
    );
  });

  // 6. Every GiftStatus (all 11 DB states plus unknown) renders a distinct,
  // non-empty label -- proving the switch in gift_list_screen.dart actually
  // covers every branch of the enum rather than falling through to one
  // shared default.
  testWidgets('every GiftStatus renders a distinct status label',
      (tester) async {
    // Twelve three-line rows do not all fit in the default test surface,
    // and ListView is a Sliver underneath -- an off-viewport row has no
    // Element at all (not merely offstage), so skipOffstage cannot help
    // here the way it does for a plain Column. Enlarge the surface instead
    // of scrolling, so every row builds at once.
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gifts = [
      for (final status in GiftStatus.values)
        _gift(id: status.index, status: status),
    ];
    await pumpView(tester, GiftListLoaded(gifts, const {}));

    final labels = <String>{};
    for (final gift in gifts) {
      final finder = find.byKey(Key('gift_list_status_${gift.id}'));
      expect(finder, findsOneWidget);
      final text = tester.widget<Text>(finder).data!;
      expect(text, isNotEmpty);
      labels.add(text);
    }
    expect(labels.length, GiftStatus.values.length);
  });

  // 7. GiftListError renders the message and a retry that calls load() --
  // a call-count assertion on the mock, not merely that a button exists.
  testWidgets('GiftListError renders the message and retry calls load()',
      (tester) async {
    await pumpView(tester, const GiftListError('server exploded'));

    expect(find.text('server exploded'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, AppStrings.retry));
    await tester.pump();

    verify(() => cubit.load()).called(1);
  });

  // 8. The back affordance actually navigates to '/profile' -- arrival,
  // not merely that the button exists (house rule). Needs a real GoRouter,
  // the same reason catalog_screen_test.dart's back affordance test does.
  testWidgets(
      'the back affordance actually navigates to /profile, not merely a '
      'wired-looking button', (tester) async {
    whenListen(
      cubit,
      const Stream<GiftListState>.empty(),
      initialState: const GiftListLoaded([], {}),
    );
    final router = GoRouter(
      initialLocation: '/gifts',
      routes: [
        GoRoute(
          path: '/gifts',
          builder: (_, __) => BlocProvider<GiftListCubit>.value(
            value: cubit,
            child: const GiftListView(),
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, __) => const Scaffold(
            key: Key('profile_destination'),
            body: Text('profile'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile_destination')), findsNothing);

    await tester.tap(find.byKey(const Key('gift_list_back_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile_destination')), findsOneWidget);
  });
}
