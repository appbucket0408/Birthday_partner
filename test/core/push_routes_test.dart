import 'package:birthday_app/core/push_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a valid payload routes to the person page', () {
    expect(routeForPayload({'person_id': '42'}), '/person/42');
  });

  test('a missing person_id routes nowhere', () {
    expect(routeForPayload({}), isNull);
  });

  test('a non-numeric person_id routes nowhere', () {
    // The payload is attacker-influenced in exactly the same way the name
    // is. A path segment built from unchecked text is how a tap becomes a
    // navigation to somewhere the sender chose.
    expect(routeForPayload({'person_id': '../settings'}), isNull);
    expect(routeForPayload({'person_id': 'abc'}), isNull);
    expect(routeForPayload({'person_id': ''}), isNull);
  });

  test('a negative or zero id routes nowhere', () {
    expect(routeForPayload({'person_id': '-1'}), isNull);
    expect(routeForPayload({'person_id': '0'}), isNull);
  });

  group('a wish payload', () {
    test('routes to the wall with the wish opened', () {
      expect(
        routeForPayload({'person_id': '7', 'wish_id': '99'}),
        '/person/7?wish=99',
      );
    });

    test('rebuilds the query from the parsed id, never the raw text', () {
      // '99&admin=1' is not an integer, so nothing of it reaches the route.
      expect(
        routeForPayload({'person_id': '7', 'wish_id': '99&admin=1'}),
        '/person/7',
      );
    });

    test('a malformed wish_id still lands on the wall', () {
      for (final bad in ['', 'abc', '0', '-5', '../settings']) {
        expect(
          routeForPayload({'person_id': '7', 'wish_id': bad}),
          '/person/7',
          reason: 'wish_id "$bad"',
        );
      }
      expect(routeForPayload({'person_id': '7', 'wish_id': 99}), '/person/7');
    });

    test('a wish_id without a valid person_id routes nowhere', () {
      expect(routeForPayload({'wish_id': '99'}), isNull);
      expect(routeForPayload({'person_id': 'x', 'wish_id': '99'}), isNull);
    });

    test('a tapped foreground banner routes the same way', () {
      final payload = localPayloadFor({'person_id': '7', 'wish_id': '99'});
      expect(routeForLocalPayload(payload), '/person/7?wish=99');
    });
  });
}
