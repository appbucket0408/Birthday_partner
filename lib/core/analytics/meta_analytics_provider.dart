import 'package:flutter/widgets.dart';
import 'package:flutter_meta_appads_sdk/flutter_meta_appads_sdk.dart';

import 'analytics_provider.dart';
import 'analytics_user.dart';
import 'app_event.dart';

class MetaAnalyticsProvider implements AnalyticsProvider {
  final _sdk = FlutterMetaAppAdsSdk();
  Future<void>? _initFuture;

  /// Every Advanced Matching field [identify] may set; [clearUser] blanks them.
  static const _matchingFields = [
    FBUserDataType.phone,
    FBUserDataType.dateOfBirth,
    FBUserDataType.city,
    FBUserDataType.country,
    FBUserDataType.externalId,
  ];

  static const _standardParams = {
    AppParam.method: FBStandardParameter.parameterNameRegistrationMethod,
  };

  @override
  String get name => 'Meta';

  @override
  NavigatorObserver? get navigatorObserver => null;

  @override
  Future<void> init() => _ensureInitialized();

  /// The SDK hashes these on device before they leave the phone.
  @override
  Future<void> identify(AnalyticsUser user) async {
    await _ensureInitialized();
    final data = {
      FBUserDataType.phone: user.phone,
      FBUserDataType.dateOfBirth: _dateOfBirth(user),
      FBUserDataType.city: user.city,
      FBUserDataType.country: 'in',
      FBUserDataType.externalId: user.id,
    };
    for (final MapEntry(:key, :value) in data.entries) {
      final normalized = value?.trim().toLowerCase();
      if (normalized == null || normalized.isEmpty) continue;
      await _sdk.setUserData(
        FBSetUserDataCommand(type: key, value: normalized),
      );
    }
  }

  /// The SDK never removes keys, so '' overwrites the previous user's data.
  @override
  Future<void> clearUser() async {
    await _ensureInitialized();
    for (final field in _matchingFields) {
      await _sdk.setUserData(FBSetUserDataCommand(type: field, value: ''));
    }
  }

  @override
  Future<void> logEvent(AppEvent event, Map<String, Object> params) async {
    if (!event.toMeta) return;
    await _ensureInitialized();
    if (event.metaStandard case final standard?) {
      await _sdk.logStandardEvent(
        FBLogStandardEventCommand(
          event: standard,
          parameters: {
            for (final MapEntry(:key, :value) in params.entries)
              if (_standardParams[key] case final param?) param: '$value',
          },
        ),
      );
      return;
    }
    await _sdk.logEvents(
      FBLogEventCommand(
        eventName: event.eventName,
        eventParameters: params.map((k, v) => MapEntry(k, '$v')),
      ),
    );
  }

  /// A failed init is dropped so the next call retries it.
  Future<void> _ensureInitialized() =>
      _initFuture ??= _sdk.initSdk().catchError((Object e) {
        _initFuture = null;
        throw e;
      });

  /// Meta wants YYYYMMDD; skipped when the user gave no year.
  static String? _dateOfBirth(AnalyticsUser user) {
    final b = user.birthday;
    if (b == null || b.year == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${b.year}${two(b.month)}${two(b.day)}';
  }
}
