import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/settings/settings_cubit.dart';
import 'package:birthday_app/features/settings/settings_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/push_repository.dart';
import 'package:birthday_app/repositories/settings_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real fakes, not mocks -- same pattern as
/// test/features/timeline/timeline_cubit_test.dart's `_FakeGraph`.
///
/// [calls] is shared with [_FakeAuth] so the two repositories' calls can be
/// interleaved into one ordered list -- that shared list is what lets the
/// signOut ordering test (assertion 3) assert across a repository boundary,
/// not just within one fake.
class _FakeSettings implements SettingsRepository {
  _FakeSettings({
    required this.calls,
    this.setRemindersEnabledError,
    this.setWishNotificationsEnabledError,
  });

  final List<String> calls;
  Object? setRemindersEnabledError;
  Object? setWishNotificationsEnabledError;

  int setRemindersEnabledCalls = 0;
  final wishNotificationWrites = <bool>[];

  @override
  Future<void> setRemindersEnabled(bool enabled) async {
    setRemindersEnabledCalls++;
    if (setRemindersEnabledError != null) throw setRemindersEnabledError!;
  }

  @override
  Future<void> setWishNotificationsEnabled(bool enabled) async {
    wishNotificationWrites.add(enabled);
    if (setWishNotificationsEnabledError != null) {
      throw setWishNotificationsEnabledError!;
    }
  }
}

/// The device-token half of what _FakeSettings used to fake. It keeps the
/// SAME shared [calls] list, so the sign-out ordering assertion goes on
/// asserting across a repository boundary -- now the boundary that actually
/// exists.
class _FakePush implements PushRepository {
  @override
  Future<void> openNotificationSettings() async {}

  _FakePush({required this.calls});
  @override
  Future<PushPermission> currentPermission() async =>
      PushPermission.granted;


  final List<String> calls;
  int deleteThisDeviceTokenCalls = 0;

  @override
  Future<void> deleteThisDeviceToken() async {
    calls.add('deleteThisDeviceToken');
    deleteThisDeviceTokenCalls++;
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> registerThisDevice() async {}

  @override
  Stream<String> get notificationRoutes => const Stream.empty();

  @override
  Future<String?> initialRoute() async => null;
}

class _FakeAuth implements AuthRepository {
  @override
  bool get hasVerifiedPhone => true;

  @override
  Future<void> sendEmailOtp(String email) async =>
      throw UnimplementedError('not used here');

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async =>
      throw UnimplementedError('not used here');

  @override
  Future<void> sendPhoneLink(String phoneE164) async =>
      throw UnimplementedError('not used here');

  @override
  Future<void> verifyPhoneLink({
    required String phoneE164,
    required String token,
  }) async =>
      throw UnimplementedError('not used here');

  _FakeAuth({
    required this.calls,
    this.profile,
    this.loadProfileError,
    this.signOutError,
    this.deleteAccountError,
  });

  final List<String> calls;
  Profile? profile;
  Object? loadProfileError;
  Object? signOutError;
  Object? deleteAccountError;

  int signOutCalls = 0;
  int deleteAccountCalls = 0;

  @override
  String? get currentUserId => 'fake-user-id';

  @override
  Future<void> sendOtp(String phoneE164) async =>
      throw UnimplementedError('not used by SettingsCubit');

  @override
  Future<void> verifyOtp({
    required String phoneE164,
    required String token,
  }) async => throw UnimplementedError('not used by SettingsCubit');

  @override
  Future<int> claimProfile() async =>
      throw UnimplementedError('not used by SettingsCubit');

  @override
  Future<Profile> loadProfile() async {
    if (loadProfileError != null) throw loadProfileError!;
    return profile!;
  }

  @override
  Future<void> completeProfile({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  }) async => throw UnimplementedError('not used by SettingsCubit');

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    signOutCalls++;
    if (signOutError != null) throw signOutError!;
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
    deleteAccountCalls++;
    if (deleteAccountError != null) throw deleteAccountError!;
  }
}

Profile _profile({
  bool remindersEnabled = true,
  bool wishNotificationsEnabled = true,
}) => Profile(
  id: 'p1',
  handle: 'handle',
  displayName: 'Name',
  remindersEnabled: remindersEnabled,
  wishNotificationsEnabled: wishNotificationsEnabled,
);

void main() {
  // 1. toggleReminders(false) emits saving then the new value.
  blocTest<SettingsCubit, SettingsState>(
    'toggleReminders(false) emits saving then the new value',
    build: () => SettingsCubit(_FakeSettings(calls: []), _FakeAuth(calls: []), _FakePush(calls: [])),
    seed: () => const SettingsLoaded(remindersEnabled: true),
    act: (c) => c.toggleReminders(false),
    expect: () => [
      isA<SettingsLoaded>()
          .having((s) => s.remindersEnabled, 'remindersEnabled', false)
          .having((s) => s.savingReminders, 'savingReminders', true),
      isA<SettingsLoaded>()
          .having((s) => s.remindersEnabled, 'remindersEnabled', false)
          .having((s) => s.savingReminders, 'savingReminders', false)
          .having((s) => s.error, 'error', isNull),
    ],
  );

  // 2. A failed toggle reverts the switch rather than leaving the UI
  //    showing a value the server did not accept.
  blocTest<SettingsCubit, SettingsState>(
    'a failed toggle reverts the switch to the last-known-good value',
    build: () => SettingsCubit(
      _FakeSettings(
        calls: [],
        setRemindersEnabledError: const ServerFailure('boom'),
      ),
      _FakeAuth(calls: []),
      _FakePush(calls: []),
    ),
    seed: () => const SettingsLoaded(remindersEnabled: true),
    act: (c) => c.toggleReminders(false),
    expect: () => [
      isA<SettingsLoaded>()
          .having((s) => s.remindersEnabled, 'remindersEnabled', false)
          .having((s) => s.savingReminders, 'savingReminders', true),
      isA<SettingsLoaded>()
          // Reverted to `true` -- the pre-toggle value -- not left on the
          // `false` the server rejected.
          .having((s) => s.remindersEnabled, 'remindersEnabled', true)
          .having((s) => s.error, 'error', AppStrings.somethingWentWrong),
    ],
  );

  // 3. signOut() deletes the device token BEFORE clearing the session.
  //    Assert the call order with a fake that records it: a signed-out
  //    device that keeps its token keeps receiving someone else's
  //    reminders, and after the session is gone the row can no longer be
  //    deleted by this client. This is the assertion worth writing
  //    carefully -- ordering is the whole of it.
  test(
    'signOut deletes the device token before clearing the session',
    () async {
      final calls = <String>[];
      final settings = _FakeSettings(calls: calls);
      final auth = _FakeAuth(calls: calls);
      final cubit = SettingsCubit(settings, auth, _FakePush(calls: calls));

      await cubit.signOut();

      expect(calls, ['deleteThisDeviceToken', 'signOut']);
      expect(cubit.state, isA<SettingsSignedOut>());
    },
  );

  // A failed signOut still only calls deleteThisDeviceToken() once -- the
  // session-clearing step never runs if the token delete throws, so no
  // account is ever left half signed-out with its token gone.
  test(
    'a failed deleteThisDeviceToken aborts signOut before signOut() runs',
    () async {
      final calls = <String>[];
      final auth = _FakeAuth(calls: calls);
      final cubit = SettingsCubit(_FakeSettings(calls: calls), auth, _FailingDeleteTokenPush());

      await cubit.signOut();

      expect(calls, isEmpty);
      expect(auth.signOutCalls, 0);
    },
  );

  // Even though deleteThisDeviceToken() succeeds, a signOut() whose
  // AuthRepository.signOut() call itself throws must not be reported as a
  // success -- the loaded screen stays up with an error rather than
  // emitting SettingsSignedOut for a sign-out that did not actually happen.
  test(
    'a failed AuthRepository.signOut surfaces the generic message',
    () async {
      final calls = <String>[];
      final auth = _FakeAuth(
        calls: calls,
        signOutError: const ServerFailure('boom'),
      );
      final cubit = SettingsCubit(_FakeSettings(calls: calls), auth, _FakePush(calls: calls));
      cubit.emit(const SettingsLoaded(remindersEnabled: true));

      await cubit.signOut();

      // The token was still deleted before the failing signOut() call --
      // this failure happens strictly after the ordering this task cares
      // about, not instead of it.
      expect(calls, ['deleteThisDeviceToken', 'signOut']);
      final state = cubit.state;
      expect(state, isA<SettingsLoaded>());
      expect((state as SettingsLoaded).error, AppStrings.somethingWentWrong);
    },
  );

  // 4. deleteAccount() calls the Edge Function and then signs out. From the
  //    cubit's side that whole two-step body lives inside
  //    AuthRepository.deleteAccount() (Task 5) -- this cubit only delegates
  //    to it once and reports the outcome as SettingsSignedOut, the same
  //    terminal state signOut() reaches.
  test(
    'deleteAccount calls AuthRepository.deleteAccount and signs out',
    () async {
      final auth = _FakeAuth(calls: []);
      final cubit = SettingsCubit(_FakeSettings(calls: []), auth, _FakePush(calls: []));

      await cubit.deleteAccount();

      expect(auth.deleteAccountCalls, 1);
      expect(cubit.state, isA<SettingsSignedOut>());
    },
  );

  // Not one of the brief's three, but the same defensiveness pattern as
  // TimelineCubit's failure-path tests: a failed deleteAccount must surface
  // the generic message and stay on the loaded screen, not crash out of the
  // cubit or silently sign the user out.
  test(
    'a failed deleteAccount surfaces the generic message and stays put',
    () async {
      final auth = _FakeAuth(
        calls: [],
        deleteAccountError: const ServerFailure('boom'),
      );
      final cubit = SettingsCubit(_FakeSettings(calls: []), auth, _FakePush(calls: []));
      cubit.emit(const SettingsLoaded(remindersEnabled: true));

      await cubit.deleteAccount();

      final state = cubit.state;
      expect(state, isA<SettingsLoaded>());
      expect((state as SettingsLoaded).error, AppStrings.somethingWentWrong);
    },
  );

  // load() populates the switch from AuthRepository.loadProfile() --
  // SettingsRepository has no read of its own, per the task-13 brief's
  // interface split (it only ever writes reminders_enabled and the device
  // token).
  test('load reads remindersEnabled off the profile', () async {
    final cubit = SettingsCubit(
      _FakeSettings(calls: []),
      _FakeAuth(calls: [], profile: _profile(remindersEnabled: false)),
      _FakePush(calls: []),
    );

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<SettingsLoaded>());
    expect((state as SettingsLoaded).remindersEnabled, isFalse);
  });

  // B4: this is the same trap as TimelineCubit.load -- a failed load() must
  // never surface Object.toString()'s default "Instance of 'ServerFailure'"
  // to the user. AppFailure carries a human [message]; the cubit must read
  // it, not stringify the exception with '$e'.
  test('load surfaces a ServerFailure\'s own message, never "Instance of"',
      () async {
    final cubit = SettingsCubit(
      _FakeSettings(calls: []),
      _FakeAuth(
        calls: [],
        loadProfileError: const ServerFailure('boom from the server'),
      ),
      _FakePush(calls: []),
    );

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<SettingsLoadError>());
    final message = (state as SettingsLoadError).message;
    expect(message, 'boom from the server');
    expect(message, isNot(contains('Instance of')));
  });

  // The flip side: something that is NOT a modelled AppFailure must fall
  // back to the generic message rather than leaking an arbitrary
  // exception's toString to the user.
  test('load falls back to the generic message for a non-AppFailure error',
      () async {
    final cubit = SettingsCubit(
      _FakeSettings(calls: []),
      _FakeAuth(calls: [], loadProfileError: StateError('unexpected')),
      _FakePush(calls: []),
    );

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<SettingsLoadError>());
    expect(
      (state as SettingsLoadError).message,
      AppStrings.somethingWentWrong,
    );
  });

  // Re-entrancy: mirrors TimelineCubit's per-action guard. A fast
  // double-tap on "Sign out" must not fire two token deletes.
  test('a second signOut call while one is in flight is ignored', () async {
    final calls = <String>[];
    final cubit = SettingsCubit(
      _FakeSettings(calls: calls),
      _FakeAuth(calls: calls),
      _FakePush(calls: calls),
    );

    final first = cubit.signOut();
    final second = cubit.signOut();
    await Future.wait([first, second]);

    expect(calls.where((c) => c == 'deleteThisDeviceToken').length, 1);
  });

  group('the New wishes switch', () {
    test('load reads wishNotificationsEnabled off the profile', () async {
      final cubit = SettingsCubit(
        _FakeSettings(calls: []),
        _FakeAuth(
          calls: [],
          profile: _profile(wishNotificationsEnabled: false),
        ),
        _FakePush(calls: []),
      );

      await cubit.load();

      final state = cubit.state as SettingsLoaded;
      expect(state.wishNotificationsEnabled, isFalse);
      expect(state.remindersEnabled, isTrue);
    });

    late _FakeSettings settings;
    blocTest<SettingsCubit, SettingsState>(
      'toggleWishNotifications(false) emits saving then the new value, '
      'and writes it',
      build: () {
        settings = _FakeSettings(calls: []);
        return SettingsCubit(
          settings,
          _FakeAuth(calls: []),
          _FakePush(calls: []),
        );
      },
      seed: () => const SettingsLoaded(remindersEnabled: true),
      act: (c) => c.toggleWishNotifications(false),
      expect: () => [
        isA<SettingsLoaded>()
            .having((s) => s.wishNotificationsEnabled, 'wish', false)
            .having((s) => s.savingWishNotifications, 'saving', true),
        isA<SettingsLoaded>()
            .having((s) => s.wishNotificationsEnabled, 'wish', false)
            .having((s) => s.savingWishNotifications, 'saving', false)
            .having((s) => s.error, 'error', isNull),
      ],
      verify: (_) => expect(settings.wishNotificationWrites, [false]),
    );

    blocTest<SettingsCubit, SettingsState>(
      'a failed wish toggle reverts to the last-known-good value',
      build: () => SettingsCubit(
        _FakeSettings(
          calls: [],
          setWishNotificationsEnabledError: const ServerFailure('boom'),
        ),
        _FakeAuth(calls: []),
        _FakePush(calls: []),
      ),
      seed: () => const SettingsLoaded(remindersEnabled: true),
      act: (c) => c.toggleWishNotifications(false),
      expect: () => [
        isA<SettingsLoaded>()
            .having((s) => s.wishNotificationsEnabled, 'wish', false),
        isA<SettingsLoaded>()
            .having((s) => s.wishNotificationsEnabled, 'wish', true)
            .having((s) => s.error, 'error', AppStrings.somethingWentWrong),
      ],
    );

    // Two switches share one state. Rebuilding it from scratch on each emit
    // -- what the single-switch cubit did -- would reset the other switch.
    blocTest<SettingsCubit, SettingsState>(
      'each switch leaves the other alone',
      build: () => SettingsCubit(
        _FakeSettings(calls: []),
        _FakeAuth(calls: []),
        _FakePush(calls: []),
      ),
      seed: () => const SettingsLoaded(
        remindersEnabled: false,
        wishNotificationsEnabled: false,
      ),
      act: (c) async {
        await c.toggleReminders(true);
        await c.toggleWishNotifications(true);
      },
      verify: (c) {
        final s = c.state as SettingsLoaded;
        expect(s.remindersEnabled, isTrue);
        expect(s.wishNotificationsEnabled, isTrue);
      },
      expect: () => [
        isA<SettingsLoaded>()
            .having((s) => s.wishNotificationsEnabled, 'wish untouched', false),
        isA<SettingsLoaded>()
            .having((s) => s.wishNotificationsEnabled, 'wish untouched', false),
        isA<SettingsLoaded>()
            .having((s) => s.remindersEnabled, 'reminders untouched', true),
        isA<SettingsLoaded>()
            .having((s) => s.remindersEnabled, 'reminders untouched', true),
      ],
    );
  });
}

/// A [PushRepository] whose [deleteThisDeviceToken] always throws, isolated
/// from [_FakePush] so its error path can be tested without giving every
/// other test an error-prone deleteThisDeviceToken.
class _FailingDeleteTokenPush implements PushRepository {
  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<PushPermission> currentPermission() async =>
      PushPermission.granted;

  @override
  Future<void> deleteThisDeviceToken() async {
    throw const ServerFailure('device token delete failed');
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> registerThisDevice() async {}

  @override
  Stream<String> get notificationRoutes => const Stream.empty();

  @override
  Future<String?> initialRoute() async => null;

}
