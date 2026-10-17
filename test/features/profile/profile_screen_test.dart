import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/profile/profile_cubit.dart';
import 'package:birthday_app/features/profile/profile_screen.dart';
import 'package:birthday_app/features/profile/profile_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/models/wish.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// A mocked ProfileCubit -- same pattern as
/// test/features/person/person_screen_test.dart's `_MockPersonCubit`.
class _MockProfileCubit extends MockCubit<ProfileState>
    implements ProfileCubit {}

Profile _profile() => const Profile(
      id: 'user-1',
      handle: 'u1',
      displayName: 'Me',
      remindersEnabled: true,
      city: 'Jaipur',
      birthday: Birthday(month: 6, day: 1),
    );

ProfileLoaded _loaded({
  int celebrating = 0,
  int celebrates = 0,
  int received = 0,
  int sent = 0,
  List<Wish> wall = const [],
}) =>
    ProfileLoaded(
      profile: _profile(),
      celebratingCount: celebrating,
      celebratesCount: celebrates,
      wishesReceived: received,
      wishesSent: sent,
      stats: const [],
      wall: wall,
    );

Wish _wish(int id, {String? author}) => Wish(
      id: id,
      authorProfileId: 'friend-$id',
      subjectPersonId: 99,
      body: 'Happy birthday $id',
      occasionYear: 2026,
      createdAt: DateTime(2026, 6, 1),
      authorName: author,
    );

Finder _inTile(String key, String text) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.text(text),
    );

Future<void> _pump(
  WidgetTester tester,
  _MockProfileCubit cubit,
  ProfileState state,
) async {
  whenListen(cubit, Stream.value(state), initialState: state);
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<ProfileCubit>.value(
        value: cubit,
        child: const ProfileView(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late _MockProfileCubit cubit;

  setUp(() {
    cubit = _MockProfileCubit();
  });

  testWidgets('all four counts render their values', (tester) async {
    await _pump(
      tester,
      cubit,
      _loaded(celebrating: 3, celebrates: 5, received: 7, sent: 9),
    );

    expect(_inTile('profile_celebrating_tile', '3'), findsOneWidget);
    expect(_inTile('profile_celebrates_tile', '5'), findsOneWidget);
    expect(_inTile('profile_wishes_received_tile', '7'), findsOneWidget);
    expect(_inTile('profile_wishes_sent_tile', '9'), findsOneWidget);
    expect(find.text(AppStrings.profileWishesReceived), findsOneWidget);
    expect(find.text(AppStrings.profileWishesSent), findsOneWidget);
  });

  testWidgets('the header shows the handle, name, birthday and city',
      (tester) async {
    await _pump(tester, cubit, _loaded());

    expect(find.text('@u1'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('🎂 1 June · Jaipur'), findsOneWidget);
  });

  testWidgets('the wall renders one square per wish, with its author',
      (tester) async {
    await _pump(
      tester,
      cubit,
      _loaded(wall: [_wish(1, author: 'Priya'), _wish(2)]),
    );

    expect(find.byKey(const Key('profile_wish_1')), findsOneWidget);
    expect(find.byKey(const Key('profile_wish_2')), findsOneWidget);
    expect(find.text('Happy birthday 1'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    // An author outside the viewer's graph renders unattributed.
    expect(find.text(AppStrings.profileWishAuthorUnknown), findsOneWidget);
  });

  testWidgets('an empty wall shows the empty message', (tester) async {
    await _pump(tester, cubit, _loaded());

    expect(find.byKey(const Key('profile_wall_empty')), findsOneWidget);
    expect(find.byKey(const Key('profile_wall')), findsNothing);
  });

  // Settings' only entry point is this button, so it must survive every
  // state -- a failed or slow load must not strand the user without a way
  // to sign out.
  for (final (name, state) in [
    ('loaded', _loaded()),
    ('loading', const ProfileLoading()),
    ('error', const ProfileError('boom')),
  ]) {
    testWidgets('the settings button is present while $name', (tester) async {
      await _pump(tester, cubit, state);

      final button = tester.widget<IconButton>(
        find.byKey(const Key('settings_button')),
      );
      expect(button.onPressed, isNotNull);
      expect(button.tooltip, AppStrings.settingsTitle);
    });
  }

  testWidgets('each wish card shows the sender below the message',
      (tester) async {
    await _pump(tester, cubit, _loaded(wall: [_wish(1, author: 'Priya')]));

    final card = find.byKey(const Key('profile_wish_1'));
    final author = find.descendant(of: card, matching: find.text('Priya'));
    final body =
        find.descendant(of: card, matching: find.text('Happy birthday 1'));
    expect(
      tester.getTopLeft(author).dy,
      greaterThan(tester.getTopLeft(body).dy),
    );
  });

  testWidgets('the wall heading carries the number of wishes', (tester) async {
    await _pump(tester, cubit, _loaded(wall: [_wish(1), _wish(2)]));

    expect(
      find.text('${AppStrings.profileWishWall} · 2'),
      findsOneWidget,
    );
  });
}
