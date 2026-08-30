import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/profile/profile_cubit.dart';
import 'package:birthday_app/features/profile/profile_screen.dart';
import 'package:birthday_app/features/profile/profile_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/birthday_stat.dart';
import 'package:birthday_app/models/profile.dart';
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
      birthday: Birthday(month: 6, day: 1),
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

  // 1. All three header counts render their values.
  testWidgets('all three header counts render their values', (tester) async {
    await _pump(
      tester,
      cubit,
      ProfileLoaded(
        profile: _profile(),
        celebratingCount: 3,
        celebratesCount: 5,
        wishesReceived: 7,
        stats: const [],
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('profile_celebrating_tile')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('profile_celebrates_tile')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('profile_wishes_received_tile')),
        matching: find.text('7'),
      ),
      findsOneWidget,
    );
    expect(find.text(AppStrings.profileCelebrating), findsOneWidget);
    expect(find.text(AppStrings.profileCelebrates), findsOneWidget);
    expect(find.text(AppStrings.profileWishesReceived), findsOneWidget);
  });

  // 2. The track record renders one row per year, newest first.
  testWidgets('the track record renders one row per year, newest first',
      (tester) async {
    await _pump(
      tester,
      cubit,
      ProfileLoaded(
        profile: _profile(),
        celebratingCount: 0,
        celebratesCount: 0,
        wishesReceived: 0,
        stats: const [
          BirthdayStat(
            year: 2026,
            wishesSent: 2,
            wishesReceived: 3,
            birthdaysCelebrated: 2,
          ),
          BirthdayStat(
            year: 2025,
            wishesSent: 4,
            wishesReceived: 6,
            birthdaysCelebrated: 3,
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('profile_stat_2026')), findsOneWidget);
    expect(find.byKey(const Key('profile_stat_2025')), findsOneWidget);

    // "newest first" means the 2026 row renders above the 2025 row.
    final y2026Top = tester.getTopLeft(find.text('2026')).dy;
    final y2025Top = tester.getTopLeft(find.text('2025')).dy;
    expect(y2026Top, lessThan(y2025Top));
  });

  // 3. The empty track record shows profileTrackRecordEmpty.
  testWidgets('the empty track record shows profileTrackRecordEmpty',
      (tester) async {
    await _pump(
      tester,
      cubit,
      ProfileLoaded(
        profile: _profile(),
        celebratingCount: 0,
        celebratesCount: 0,
        wishesReceived: 0,
        stats: const [],
      ),
    );

    expect(find.text(AppStrings.profileTrackRecordEmpty), findsOneWidget);
  });

  // 4. The back affordance is present and enabled.
  testWidgets('the back affordance is present and enabled', (tester) async {
    await _pump(
      tester,
      cubit,
      ProfileLoaded(
        profile: _profile(),
        celebratingCount: 0,
        celebratesCount: 0,
        wishesReceived: 0,
        stats: const [],
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('profile_back_button')),
    );
    expect(button.onPressed, isNotNull);
  });

  // The back affordance must also survive the loading state -- '/profile'
  // is reached with context.go regardless of what the cubit ends up
  // emitting, so it must not depend on ProfileLoaded.
  testWidgets('the back affordance is present during ProfileLoading too',
      (tester) async {
    await _pump(tester, cubit, const ProfileLoading());

    final button = tester.widget<IconButton>(
      find.byKey(const Key('profile_back_button')),
    );
    expect(button.onPressed, isNotNull);
  });
}
