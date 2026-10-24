import 'package:birthday_app/core/analytics.dart';
import 'package:birthday_app/core/analytics/meta_analytics_provider.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:flutter_meta_appads_sdk/flutter_meta_appads_sdk_platform_interface.dart';
import 'package:flutter_meta_appads_sdk/pigeon_generated.dart' as pigeon;
import 'package:flutter_test/flutter_test.dart';

class _FakeMetaSdk extends FlutterMetaAppadsSdkPlatform {
  int inits = 0;
  final userData = <pigeon.FBUserDataType, String>{};
  final custom = <pigeon.FBLogEventRequest>[];
  final standard = <pigeon.FBLogStandardEventRequest>[];

  @override
  Future<void> initSdk({bool enableLogging = false}) async => inits++;

  @override
  Future<void> setUserData(pigeon.FBSetUserDataRequest request) async =>
      userData[request.type] = request.value;

  @override
  Future<void> logEvents(pigeon.FBLogEventRequest request) async =>
      custom.add(request);

  @override
  Future<void> logStandardEvent(
    pigeon.FBLogStandardEventRequest request,
  ) async =>
      standard.add(request);
}

void main() {
  late _FakeMetaSdk sdk;
  late MetaAnalyticsProvider meta;

  setUp(() {
    sdk = _FakeMetaSdk();
    FlutterMetaAppadsSdkPlatform.instance = sdk;
    meta = MetaAnalyticsProvider();
  });

  test('initialises the SDK once', () async {
    await meta.init();
    await meta.logEvent(AppEvent.inviteSent, const {});
    expect(sdk.inits, 1);
  });

  test('identify sends hashed-on-device matching fields', () async {
    await meta.identify(
      const AnalyticsUser(
        id: 'u1',
        phone: '919876543210',
        birthday: Birthday(month: 3, day: 9, year: 1998),
        city: ' New Delhi ',
      ),
    );
    expect(sdk.userData, {
      pigeon.FBUserDataType.phone: '919876543210',
      pigeon.FBUserDataType.dateOfBirth: '19980309',
      pigeon.FBUserDataType.city: 'new delhi',
      pigeon.FBUserDataType.country: 'in',
      pigeon.FBUserDataType.externalId: 'u1',
    });
  });

  test('a birthday without a year sends no date of birth', () async {
    await meta.identify(
      const AnalyticsUser(id: 'u1', birthday: Birthday(month: 3, day: 9)),
    );
    expect(sdk.userData, isNot(contains(pigeon.FBUserDataType.dateOfBirth)));
  });

  test('clearUser blanks every matching field', () async {
    await meta.identify(const AnalyticsUser(id: 'u1', phone: '91999'));
    await meta.clearUser();
    expect(sdk.userData.values, everyElement(isEmpty));
    expect(sdk.userData, hasLength(5));
  });

  test('sign up goes out as the standard registration event', () async {
    await meta.logEvent(AppEvent.signUp, {AppParam.method: 'phone'});
    final event = sdk.standard.single;
    expect(event.eventName, pigeon.FBStandardEvent.completedRegistration);
    expect(
      event.parameters.single.parameterName,
      pigeon.FBStandardParameter.parameterNameRegistrationMethod,
    );
    expect(event.parameters.single.value, 'phone');
    expect(sdk.custom, isEmpty);
  });

  test('ad events go out as custom events with string params', () async {
    await meta.logEvent(AppEvent.contactsImported, {AppParam.added: 12});
    expect(sdk.custom.single.eventName, 'contacts_imported');
    expect(sdk.custom.single.eventParameters, {AppParam.added: '12'});
  });

  test('events not meant for Meta are dropped', () async {
    await meta.logEvent(AppEvent.feedScrolled, {AppParam.postsLoaded: 3});
    await meta.logEvent(AppEvent.celebrateBack, {AppParam.source: 'person'});
    expect(sdk.custom, isEmpty);
    expect(sdk.standard, isEmpty);
  });
}
