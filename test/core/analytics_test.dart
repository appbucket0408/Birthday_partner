import 'package:birthday_app/core/analytics.dart';
import 'package:birthday_app/core/analytics/analytics_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProvider implements AnalyticsProvider {
  _FakeProvider(this.name, {this.fails = false, this.navigatorObserver});

  @override
  final String name;
  final bool fails;
  @override
  final NavigatorObserver? navigatorObserver;

  final calls = <String>[];
  final events = <(AppEvent, Map<String, Object>)>[];
  AnalyticsUser? user;

  Future<void> _record(String call) async {
    calls.add(call);
    if (fails) throw Exception('$name down');
  }

  @override
  Future<void> init() => _record('init');

  @override
  Future<void> identify(AnalyticsUser user) {
    this.user = user;
    return _record('identify');
  }

  @override
  Future<void> clearUser() {
    user = null;
    return _record('clearUser');
  }

  @override
  Future<void> logEvent(AppEvent event, Map<String, Object> params) {
    events.add((event, params));
    return _record('log');
  }
}

void main() {
  tearDown(Analytics.reset);

  test('is a no-op before init', () async {
    expect(Analytics.enabled, isFalse);
    expect(Analytics.navigatorObservers, isEmpty);
    await Analytics.log(AppEvent.signUp);
    await Analytics.identify(const AnalyticsUser(id: 'u1'));
    await Analytics.clearUser();
  });

  test('init starts every provider', () async {
    final a = _FakeProvider('a'), b = _FakeProvider('b');
    await Analytics.init([a, b]);
    expect(Analytics.enabled, isTrue);
    expect(a.calls, ['init']);
    expect(b.calls, ['init']);
  });

  test('log fans the event and params out to every provider', () async {
    final a = _FakeProvider('a'), b = _FakeProvider('b');
    await Analytics.init([a, b]);
    await Analytics.log(AppEvent.inviteSent, {AppParam.source: 'profile'});
    for (final p in [a, b]) {
      expect(p.events.single.$1, AppEvent.inviteSent);
      expect(p.events.single.$2, {AppParam.source: 'profile'});
    }
  });

  test('one failing provider never blocks the others or throws', () async {
    final broken = _FakeProvider('broken', fails: true);
    final ok = _FakeProvider('ok');
    await Analytics.init([broken, ok]);
    await Analytics.log(AppEvent.wishPosted);
    await Analytics.identify(const AnalyticsUser(id: 'u1'));
    expect(ok.events, hasLength(1));
    expect(ok.user?.id, 'u1');
  });

  test('identify and clearUser reach every provider', () async {
    final a = _FakeProvider('a'), b = _FakeProvider('b');
    await Analytics.init([a, b]);
    await Analytics.identify(const AnalyticsUser(id: 'u1', phone: '91999'));
    expect([a.user?.phone, b.user?.phone], ['91999', '91999']);
    await Analytics.clearUser();
    expect([a.user, b.user], [null, null]);
  });

  test('collects only the observers providers offer', () async {
    final observer = NavigatorObserver();
    await Analytics.init([
      _FakeProvider('a', navigatorObserver: observer),
      _FakeProvider('b'),
    ]);
    expect(Analytics.navigatorObservers, [observer]);
  });
}
