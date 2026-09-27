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
}
