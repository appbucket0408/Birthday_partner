import 'package:birthday_app/repositories/app_update_repository.dart';
import 'package:birthday_app/repositories/app_update_repository_impl.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockConfig extends Mock implements FirebaseRemoteConfig {}

void main() {
  late _MockConfig config;
  late AppUpdateRepositoryImpl repo;

  setUpAll(() {
    registerFallbackValue(RemoteConfigSettings(
      fetchTimeout: Duration.zero,
      minimumFetchInterval: Duration.zero,
    ));
  });

  /// This install is build 5; Remote Config says [min] and [latest].
  void given({required int min, required int latest}) {
    when(() => config.getInt(AppUpdateRepositoryImpl.minSupportedBuildKey))
        .thenReturn(min);
    when(() => config.getInt(AppUpdateRepositoryImpl.latestBuildKey))
        .thenReturn(latest);
  }

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Candlewish',
      packageName: 'app.candlewish',
      version: '1.0.0',
      buildNumber: '5',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    config = _MockConfig();
    when(() => config.setConfigSettings(any())).thenAnswer((_) async {});
    when(() => config.setDefaults(any())).thenAnswer((_) async {});
    when(() => config.fetchAndActivate()).thenAnswer((_) async => true);
    repo = AppUpdateRepositoryImpl(config);
  });

  test('below the minimum is required', () async {
    given(min: 6, latest: 7);
    expect(await repo.check(), UpdateStatus.required);
  });

  test('below the latest only is optional', () async {
    given(min: 3, latest: 6);
    expect(await repo.check(), UpdateStatus.optional);
  });

  test('at the latest is up to date', () async {
    given(min: 0, latest: 5);
    expect(await repo.check(), UpdateStatus.upToDate);
  });

  test('a failed fetch falls back to the activated values', () async {
    when(() => config.fetchAndActivate()).thenThrow(Exception('offline'));
    given(min: 0, latest: 0);
    expect(await repo.check(), UpdateStatus.upToDate);
  });

  test('later hides the optional update', () async {
    given(min: 0, latest: 6);
    await repo.snoozeOptional();
    expect(await repo.check(), UpdateStatus.upToDate);
  });

  test('a newer latest build brings the prompt back', () async {
    given(min: 0, latest: 6);
    await repo.snoozeOptional();
    given(min: 0, latest: 7);
    expect(await repo.check(), UpdateStatus.optional);
  });

  test('the snooze runs out after a few days', () async {
    given(min: 0, latest: 6);
    final expired = DateTime.now()
        .subtract(AppUpdateRepositoryImpl.snoozeFor + const Duration(hours: 1));
    SharedPreferences.setMockInitialValues({
      'update_snoozed_build': 6,
      'update_snoozed_at_ms': expired.millisecondsSinceEpoch,
    });
    expect(await repo.check(), UpdateStatus.optional);
  });

  test('a snooze never hides a required update', () async {
    given(min: 0, latest: 6);
    await repo.snoozeOptional();
    given(min: 6, latest: 6);
    expect(await repo.check(), UpdateStatus.required);
  });
}
