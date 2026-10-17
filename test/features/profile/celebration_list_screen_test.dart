import 'package:birthday_app/features/profile/celebration_list_screen.dart';
import 'package:birthday_app/models/person.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Person _person(int id, {String? displayName}) => Person(
      id: id,
      displayName: displayName ?? 'Person $id',
      isClaimed: false,
    );

/// [navigable] is deliberately nullable and, when omitted, NOT passed to
/// the widget at all -- so the omitting test exercises the constructor's
/// own default, exactly as `/profile/celebrates` does in app_router.dart
/// (it never passes `navigable`). Defaulting the parameter here to `false`
/// would make the "default" test pass no matter what the widget's real
/// default is, defeating the point of pinning it.
Future<void> _pump(
  WidgetTester tester, {
  required List<Person> people,
  bool? navigable,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: navigable == null
          ? CelebrationListScreen(
              title: 'Title',
              emptyMessage: 'Empty',
              fetchPeople: () async => people,
            )
          : CelebrationListScreen(
              title: 'Title',
              emptyMessage: 'Empty',
              fetchPeople: () async => people,
              navigable: navigable,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Requirement 4 (spec §7.3) is a PRODUCT choice, not a privacy boundary:
  // `private.can_see_person` grants sight of someone you celebrate, or
  // someone who celebrates you -- a Celebrates row is the latter, and that
  // branch alone already grants the viewer sight of it. A Celebrates row
  // that navigated would NOT error and would NOT show a page the viewer has
  // no right to see; it is withheld because a Celebrates row is a different
  // relationship (someone who added you) from the one this list is about,
  // not because RLS would refuse it. See `celebration_list_screen.dart`'s
  // class doc.
  //
  // Today that choice reduces to one boolean default (`navigable` defaults
  // false) plus one call site passing `true`
  // (`/profile/celebrating` in app_router.dart). These two tests pin the
  // widget's own default and that passing `true` works; they do NOT pin
  // that `/profile/celebrates` omits `navigable` -- that route-level gap is
  // covered by test/router/app_router_test.dart instead, since it requires
  // building the route, not just the widget.
  testWidgets(
    'a row is NOT navigable by default (the Celebrates call site '
    'never passes navigable)',
    (tester) async {
      await _pump(tester, people: [_person(1)]);

      final tile = tester.widget<ListTile>(
        find.byKey(const Key('celebration_list_person_1')),
      );
      expect(tile.onTap, isNull);
    },
  );

  testWidgets(
    'a row IS navigable when navigable is true (Celebrating)',
    (tester) async {
      await _pump(tester, people: [_person(1)], navigable: true);

      final tile = tester.widget<ListTile>(
        find.byKey(const Key('celebration_list_person_1')),
      );
      expect(tile.onTap, isNotNull);
    },
  );
}
