import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/person/person_cubit.dart';
import 'package:birthday_app/features/person/person_screen.dart';
import 'package:birthday_app/features/person/person_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/models/wish.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// A mocked PersonCubit -- same pattern as
/// test/features/onboarding/otp_screen_test.dart's `_MockPhoneCubit`. Using
/// a mock rather than a real PersonCubit-plus-fake-repositories lets each
/// test drop straight into the exact PersonLoaded shape it wants to assert
/// against, including states (like `posting`) that are awkward to reach by
/// driving a real cubit through fakes.
class _MockPersonCubit extends MockCubit<PersonState> implements PersonCubit {}

Person _person(int id, {Birthday? birthday}) => Person(
      id: id,
      displayName: 'Person $id',
      isClaimed: false,
      birthday: birthday,
    );

Wish _wish(int id, {String? authorName, int occasionYear = 2026}) => Wish(
      id: id,
      authorProfileId: 'author-$id',
      subjectPersonId: 1,
      body: 'Happy birthday!',
      occasionYear: occasionYear,
      createdAt: DateTime(2026, 1, 1),
      authorName: authorName,
    );

/// 15 Apr 2026, for the birthday countdown.
DateTime _fixedNow() => DateTime(2026, 4, 15);

Future<void> _pump(
  WidgetTester tester,
  _MockPersonCubit cubit,
  PersonState state,
) async {
  whenListen(cubit, Stream.value(state), initialState: state);
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<PersonCubit>.value(
        value: cubit,
        child: const PersonView(personId: 1, now: _fixedNow),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late _MockPersonCubit cubit;

  setUp(() {
    cubit = _MockPersonCubit();
  });

  // 1. A wish by an unconnected author renders AppStrings.wishAuthorUnknown.
  testWidgets(
      'a wish by an unconnected author renders AppStrings.wishAuthorUnknown',
      (tester) async {
    await _pump(
      tester,
      cubit,
      PersonLoaded(
        person: _person(1, birthday: const Birthday(month: 4, day: 15)),
        celebratorCount: 2,
        wishes: [_wish(1, authorName: null)],
        viewerCelebrates: true,
      ),
    );

    expect(
      find.textContaining(AppStrings.wishAuthorUnknown),
      findsOneWidget,
    );
  });

  // 2. The celebrator count uses the singular string when the count is 1.
  testWidgets(
      'the celebrator count uses the singular string when the count is 1',
      (tester) async {
    await _pump(
      tester,
      cubit,
      PersonLoaded(
        person: _person(1, birthday: const Birthday(month: 4, day: 15)),
        celebratorCount: 1,
        wishes: const [],
        viewerCelebrates: true,
      ),
    );

    expect(find.text(AppStrings.personCelebratorCountOne), findsOneWidget);
    expect(
      find.text(
        AppStrings.personCelebratorCountTemplate.replaceFirst('%s', '1'),
      ),
      findsNothing,
    );
  });

  // 2b: the plural template is used for any other count, so the singular
  // string is not just always shown regardless of count.
  testWidgets('the celebrator count uses the plural template when count != 1',
      (tester) async {
    await _pump(
      tester,
      cubit,
      PersonLoaded(
        person: _person(1, birthday: const Birthday(month: 4, day: 15)),
        celebratorCount: 4,
        wishes: const [],
        viewerCelebrates: true,
      ),
    );

    expect(
      find.text(
        AppStrings.personCelebratorCountTemplate.replaceFirst('%s', '4'),
      ),
      findsOneWidget,
    );
    expect(find.text(AppStrings.personCelebratorCountOne), findsNothing);
  });

  // 3. The compose FAB is absent when the person has no birthday.
  testWidgets('the compose FAB is absent when the person has no birthday',
      (tester) async {
    await _pump(
      tester,
      cubit,
      PersonLoaded(
        person: _person(1),
        celebratorCount: 3,
        wishes: const [],
        viewerCelebrates: true,
      ),
    );

    expect(find.byKey(const Key('wish_write_button')), findsNothing);
    expect(find.text(AppStrings.personNoBirthday), findsOneWidget);
  });

  // 3b: the FAB IS present when the person does have a birthday, so
  // assertion 3 is proving an absence, not a widget that never renders.
  testWidgets('the compose FAB is present when the person has a birthday',
      (tester) async {
    await _pump(
      tester,
      cubit,
      PersonLoaded(
        person: _person(1, birthday: const Birthday(month: 4, day: 15)),
        celebratorCount: 3,
        wishes: const [],
        viewerCelebrates: true,
      ),
    );

    expect(find.byKey(const Key('wish_write_button')), findsOneWidget);
  });

  // 3c (fix round 1): the FAB is absent when viewerCelebrates is false, even
  // though the person DOES have a birthday -- the literal text of the
  // brief's condition ("the person has a birthday AND the viewer celebrates
  // them"), and the one case nothing previously proved. Without this, the
  // app would show "Write a wish" to someone whose insert
  // wishes_insert_own will refuse -- they write a message, tap post, and
  // get an error they can do nothing about.
  testWidgets(
      'the compose FAB is absent when the viewer does not celebrate this '
      'person, even with a birthday present', (tester) async {
    await _pump(
      tester,
      cubit,
      PersonLoaded(
        person: _person(1, birthday: const Birthday(month: 4, day: 15)),
        celebratorCount: 3,
        wishes: const [],
        viewerCelebrates: false,
      ),
    );

    expect(find.byKey(const Key('wish_write_button')), findsNothing);
  });

  // 3d (task 5). "Send a cake" is shown under the SAME condition as the
  // compose FAB (_canComposeFor) -- absent when the person has no birthday.
  testWidgets(
      '"Send a cake" is absent when the person has no birthday',
      (tester) async {
    await _pump(
      tester,
      cubit,
      PersonLoaded(
        person: _person(1),
        celebratorCount: 3,
        wishes: const [],
        viewerCelebrates: true,
      ),
    );

    expect(find.byKey(const Key('gift_send_cake_button')), findsNothing);
  });

  // 3e: present when both conditions hold, so 3d is proving an absence, not
  // a row that never renders.
  testWidgets(
      '"Send a cake" is present when the person has a birthday and the '
      'viewer celebrates them', (tester) async {
    await _pump(
      tester,
      cubit,
      PersonLoaded(
        person: _person(1, birthday: const Birthday(month: 4, day: 15)),
        celebratorCount: 3,
        wishes: const [],
        viewerCelebrates: true,
      ),
    );

    expect(find.byKey(const Key('gift_send_cake_button')), findsOneWidget);
  });

  // 3f: absent when viewerCelebrates is false, even with a birthday present
  // -- offering it otherwise leads to a 45005 the user cannot act on.
  testWidgets(
      '"Send a cake" is absent when the viewer does not celebrate this '
      'person, even with a birthday present', (tester) async {
    await _pump(
      tester,
      cubit,
      PersonLoaded(
        person: _person(1, birthday: const Birthday(month: 4, day: 15)),
        celebratorCount: 3,
        wishes: const [],
        viewerCelebrates: false,
      ),
    );

    expect(find.byKey(const Key('gift_send_cake_button')), findsNothing);
  });

  // 4. The back affordance is present and enabled.
  testWidgets('the back affordance is present and enabled', (tester) async {
    await _pump(
      tester,
      cubit,
      PersonLoaded(
        person: _person(1, birthday: const Birthday(month: 4, day: 15)),
        celebratorCount: 1,
        wishes: const [],
        viewerCelebrates: true,
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('person_back_button')),
    );
    expect(button.onPressed, isNotNull);
  });

  // The back affordance must also survive the loading and error states --
  // '/person/:personId' is reached with context.go regardless of what the
  // cubit ends up emitting, so it must not depend on PersonLoaded.
  testWidgets('the back affordance is present during PersonLoading too',
      (tester) async {
    await _pump(tester, cubit, const PersonLoading());

    final button = tester.widget<IconButton>(
      find.byKey(const Key('person_back_button')),
    );
    expect(button.onPressed, isNotNull);
  });

  group('header', () {
    PersonLoaded loaded(Birthday? birthday, {List<Wish> wishes = const []}) =>
        PersonLoaded(
          person: _person(1, birthday: birthday),
          celebratorCount: 6,
          wishes: wishes,
          viewerCelebrates: true,
        );

    for (final (birthday, date, countdown) in [
      (const Birthday(month: 4, day: 15), '🎂 15 April', AppStrings.personToday),
      (const Birthday(month: 4, day: 16), '🎂 16 April', AppStrings.personTomorrow),
      (const Birthday(month: 4, day: 25), '🎂 25 April', 'in 10 days'),
    ]) {
      testWidgets('shows "$date" with "$countdown"', (tester) async {
        await _pump(tester, cubit, loaded(birthday));
        expect(find.text(date), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('person_countdown')),
            matching: find.text(countdown),
          ),
          findsOneWidget,
        );
      });
    }

    // The name is in the header card; the top bar must not repeat it.
    testWidgets('the name appears once, in the header', (tester) async {
      await _pump(tester, cubit, loaded(const Birthday(month: 4, day: 25)));
      expect(find.text('Person 1'), findsOneWidget);
    });

    testWidgets('someone not on the app says so, and why', (tester) async {
      await _pump(tester, cubit, loaded(null));
      expect(find.text(AppStrings.personNoBirthday), findsOneWidget);
      expect(find.text(AppStrings.personNoBirthdayHint), findsOneWidget);
    });

    testWidgets('the wishes heading carries the count', (tester) async {
      await _pump(
        tester,
        cubit,
        loaded(const Birthday(month: 4, day: 25),
            wishes: [_wish(1), _wish(2)]),
      );
      expect(
        find.text('${AppStrings.personWishesTitle} · 2'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('wish_1')), findsOneWidget);
    });
  });

  for (final (celebratesViewer, matcher) in [
    (true, findsOneWidget),
    (false, findsNothing),
  ]) {
    testWidgets('"Celebrates you" badge when celebratesViewer=$celebratesViewer',
        (tester) async {
      await _pump(
        tester,
        cubit,
        PersonLoaded(
          person: _person(1, birthday: const Birthday(month: 4, day: 25)),
          celebratorCount: 1,
          wishes: const [],
          viewerCelebrates: true,
          celebratesViewer: celebratesViewer,
        ),
      );
      expect(find.byKey(const Key('person_celebrates_you')), matcher);
    });
  }

  group('wishing opens on the birthday only', () {
    PersonLoaded loadedOn(Birthday birthday) => PersonLoaded(
          person: _person(1, birthday: birthday),
          celebratorCount: 1,
          wishes: const [],
          viewerCelebrates: true,
        );

    testWidgets('on their birthday: Write a wish is there', (tester) async {
      // _fixedNow is 15 April.
      await _pump(tester, cubit, loadedOn(const Birthday(month: 4, day: 15)));

      expect(find.byKey(const Key('wish_write_button')), findsOneWidget);
      expect(find.byKey(const Key('wish_opens_on_birthday')), findsNothing);
    });

    testWidgets('any other day: hidden, with the reason, and the cake stays',
        (tester) async {
      await _pump(tester, cubit, loadedOn(const Birthday(month: 4, day: 25)));

      expect(find.byKey(const Key('wish_write_button')), findsNothing);
      expect(
        find.text(
          AppStrings.personWishOpensTemplate.replaceFirst('%s', '25 April'),
        ),
        findsOneWidget,
      );
      // A cake has to be ordered ahead, so it is offered every day.
      expect(find.byKey(const Key('gift_send_cake_button')), findsOneWidget);
    });
  });

  group('opened from a "new wish" notification', () {
    // The wall loads FROM a loading state, as it does on a real tap: the
    // listener acts only on the load that first produces the wall.
    Future<void> pumpOpening(
      WidgetTester tester,
      _MockPersonCubit cubit,
      PersonLoaded loaded, {
      required int openWishId,
    }) async {
      whenListen(
        cubit,
        Stream<PersonState>.value(loaded),
        initialState: const PersonLoading(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<PersonCubit>.value(
            value: cubit,
            child: PersonView(
              personId: 1,
              openWishId: openWishId,
              now: _fixedNow,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the wish it names is opened once the wall loads',
        (tester) async {
      await pumpOpening(
        tester,
        cubit,
        PersonLoaded(
          person: _person(1, birthday: const Birthday(month: 4, day: 15)),
          celebratorCount: 1,
          wishes: [_wish(5, authorName: 'Asha'), _wish(9, authorName: 'Ravi')],
          viewerCelebrates: false,
        ),
        openWishId: 9,
      );

      expect(find.byKey(const Key('wish_post_9')), findsOneWidget);
    });

    testWidgets('a wish deleted since leaves the user on their wall',
        (tester) async {
      await pumpOpening(
        tester,
        cubit,
        PersonLoaded(
          person: _person(1, birthday: const Birthday(month: 4, day: 15)),
          celebratorCount: 1,
          wishes: [_wish(5, authorName: 'Asha')],
          viewerCelebrates: false,
        ),
        openWishId: 9,
      );

      expect(find.byKey(const Key('person_header')), findsOneWidget);
      expect(find.byKey(const Key('wish_post_9')), findsNothing);
    });
  });
}
