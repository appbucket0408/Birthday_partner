import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/settings/settings_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/push_repository.dart';
import 'package:birthday_app/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real fakes, not mocks -- same pattern as
/// test/features/settings/settings_cubit_test.dart.
class _FakeSettings implements SettingsRepository {
  final wishNotificationWrites = <bool>[];

  @override
  Future<void> setRemindersEnabled(bool enabled) async {}

  @override
  Future<void> setWishNotificationsEnabled(bool enabled) async =>
      wishNotificationWrites.add(enabled);
}

class _FakePush implements PushRepository {
  @override
  Future<PushPermission> currentPermission() async =>
      PushPermission.granted;

  @override
  Future<void> deleteThisDeviceToken() async {}

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

  @override
  String? get currentUserId => 'fake-user-id';

  @override
  Future<void> sendOtp(String phoneE164) async =>
      throw UnimplementedError('not used by SettingsScreen');

  @override
  Future<void> verifyOtp({
    required String phoneE164,
    required String token,
  }) async => throw UnimplementedError('not used by SettingsScreen');

  @override
  Future<int> claimProfile() async =>
      throw UnimplementedError('not used by SettingsScreen');

  @override
  Future<Profile> loadProfile() async => const Profile(
    id: 'p1',
    handle: 'handle',
    displayName: 'Name',
    remindersEnabled: true,
    birthday: Birthday(month: 1, day: 1),
  );

  @override
  Future<void> completeProfile({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  }) async => throw UnimplementedError('not used by SettingsScreen');

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

void main() {
  // Re-review finding: '/settings' is a top-level GoRoute reached via
  // context.go, which replaces the whole page stack -- Navigator.canPop()
  // is false once here, so with no explicit leading control this screen was
  // a reachable dead-end (no back arrow, no other navigation in the whole
  // settings feature). This only asserts the control exists and is
  // enabled -- there is no GoRouter in this harness (same limitation noted
  // on TimelineScreen's bare-MaterialApp tests), so the navigation itself
  // (that it actually lands on '/timeline') is NOT exercised here.
  testWidgets('the settings screen renders an enabled back control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AuthRepository>.value(value: _FakeAuth()),
            RepositoryProvider<PushRepository>.value(value: _FakePush()),
          ],
          child: SettingsScreen(repository: _FakeSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final back = tester.widget<IconButton>(
      find.byKey(const Key('settings_back_button')),
    );
    expect(back.onPressed, isNotNull);
  });

  testWidgets('the New wishes switch shows the saved value and writes a flip', (
    tester,
  ) async {
    final settings = _FakeSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AuthRepository>.value(value: _FakeAuth()),
            RepositoryProvider<PushRepository>.value(value: _FakePush()),
          ],
          child: SettingsScreen(repository: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const Key('wish_notifications_switch'));
    expect(find.text(AppStrings.settingsWishNotifications), findsOneWidget);
    // _FakeAuth's profile leaves it at its default: on.
    expect(tester.widget<SwitchListTile>(finder).value, isTrue);

    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(settings.wishNotificationWrites, [false]);
    expect(tester.widget<SwitchListTile>(finder).value, isFalse);
  });
}
