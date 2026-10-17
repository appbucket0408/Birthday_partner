import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/connections/connections_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/birthday_stat.dart';
import 'package:birthday_app/models/celebration.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/repositories/graph_repository.dart';
import 'package:birthday_app/repositories/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real fakes driving the real ConnectionsCubit, like the timeline tests.
class _FakeGraph implements GraphRepository {
  _FakeGraph(this.mine);

  List<Celebration> mine;
  final stopped = <int>[];
  final backed = <int>[];
  Object? backError;
  int _nextId = 100;

  @override
  Future<List<Celebration>> celebrations() async => mine;

  @override
  Future<Set<int>> celebratesMe() async => {};

  @override
  Future<void> celebrateBack(int personId) async {
    if (backError != null) throw backError!;
    backed.add(personId);
    mine = [...mine, Celebration(id: _nextId++, person: _person(personId))];
  }

  @override
  Future<void> stopCelebrating(int celebrationId) async =>
      stopped.add(celebrationId);
}

class _FakeProfile implements ProfileRepository {
  _FakeProfile(this.fans);

  final List<Person> fans;

  @override
  Future<List<Person>> celebrates() async => fans;

  @override
  Future<List<BirthdayStat>> stats() async => const [];
}

Person _person(int id, {String? name, Birthday? birthday}) => Person(
      id: id,
      displayName: name ?? 'Person $id',
      isClaimed: true,
      birthday: birthday ?? Birthday(month: 3, day: id),
    );

Future<_FakeGraph> _pump(
  WidgetTester tester, {
  required List<Person> iCelebrate,
  required List<Person> celebrateMe,
  ConnectionsTab tab = ConnectionsTab.iCelebrate,
}) async {
  final graph = _FakeGraph([
    for (final p in iCelebrate) Celebration(id: p.id * 10, person: p),
  ]);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<GraphRepository>.value(value: graph),
        RepositoryProvider<ProfileRepository>.value(
          value: _FakeProfile(celebrateMe),
        ),
      ],
      child: MaterialApp(home: ConnectionsScreen(initialTab: tab)),
    ),
  );
  await tester.pumpAndSettle();
  return graph;
}

void main() {
  final ann = _person(1, name: 'Ann');
  final bob = _person(2, name: 'Bob');
  final cid = _person(3, name: 'Cid');

  testWidgets('both tabs carry their counts', (tester) async {
    await _pump(tester, iCelebrate: [ann, bob], celebrateMe: [bob, cid]);

    expect(find.text('${AppStrings.profileCelebrating} · 2'), findsOneWidget);
    expect(find.text('${AppStrings.profileCelebrates} · 2'), findsOneWidget);
  });

  testWidgets('I celebrate: rows by name, mutuals marked "Celebrates you"',
      (tester) async {
    await _pump(tester, iCelebrate: [bob, ann], celebrateMe: [bob]);

    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('Ann'), lessThan(top('Bob')));
    expect(find.text('🎂 1 March'), findsOneWidget);
    expect(find.text('🎂 2 March'), findsOneWidget);
    // Bob celebrates back, on his own line; Ann does not.
    expect(find.byKey(const Key('celebrates_you_2')), findsOneWidget);
    expect(find.byKey(const Key('celebrates_you_1')), findsNothing);
  });

  testWidgets('I celebrate: "Celebrating" asks, then stops celebrating',
      (tester) async {
    final graph = await _pump(tester, iCelebrate: [ann], celebrateMe: []);

    await tester.tap(find.byKey(const Key('celebrating_1')));
    await tester.pumpAndSettle();
    expect(
      find.text(
          AppStrings.connectionsStopTitleTemplate.replaceFirst('%s', 'Ann')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('connections_stop_confirm')));
    await tester.pumpAndSettle();

    expect(graph.stopped, [10]);
    expect(find.text('Ann'), findsNothing);
  });

  testWidgets('cancelling the sheet changes nothing', (tester) async {
    final graph = await _pump(tester, iCelebrate: [ann], celebrateMe: []);

    await tester.tap(find.byKey(const Key('celebrating_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();

    expect(graph.stopped, isEmpty);
    expect(find.text('Ann'), findsOneWidget);
  });

  testWidgets(
      'Celebrate me: people to celebrate back come first, and the button '
      'turns into "Celebrating"', (tester) async {
    final graph = await _pump(
      tester,
      iCelebrate: [ann],
      celebrateMe: [ann, cid],
      tab: ConnectionsTab.celebrateMe,
    );

    // Cid is not celebrated back yet, so is listed before Ann.
    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('Cid'), lessThan(top('Ann')));
    expect(find.byKey(const Key('celebrate_back_3')), findsOneWidget);
    expect(find.byKey(const Key('celebrating_1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('celebrate_back_3')));
    await tester.pumpAndSettle();

    expect(graph.backed, [3]);
    expect(find.byKey(const Key('celebrate_back_3')), findsNothing);
    expect(find.byKey(const Key('celebrating_3')), findsOneWidget);
    expect(find.text('${AppStrings.profileCelebrating} · 2'), findsOneWidget);
  });

  testWidgets('a failed celebrate back keeps the button and says why',
      (tester) async {
    final graph = await _pump(
      tester,
      iCelebrate: [],
      celebrateMe: [cid],
      tab: ConnectionsTab.celebrateMe,
    );
    graph.backError = const ServerFailure('not allowed');

    await tester.tap(find.byKey(const Key('celebrate_back_3')));
    await tester.pumpAndSettle();

    expect(find.text('not allowed'), findsOneWidget);
    expect(find.byKey(const Key('celebrate_back_3')), findsOneWidget);
  });

  testWidgets('search filters by name, and says when nothing matches',
      (tester) async {
    await _pump(tester, iCelebrate: [ann, bob], celebrateMe: []);

    await tester.enterText(find.byKey(const Key('connections_search')), 'bo');
    await tester.pump();
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Ann'), findsNothing);

    await tester.enterText(find.byKey(const Key('connections_search')), 'zz');
    await tester.pump();
    expect(
      find.text(AppStrings.connectionsNoMatchesTemplate.replaceFirst('%s', 'zz')),
      findsOneWidget,
    );
  });

  testWidgets('an empty "I celebrate" offers Add people', (tester) async {
    await _pump(tester, iCelebrate: [], celebrateMe: []);

    expect(find.text(AppStrings.profileCelebratingEmpty), findsOneWidget);
    expect(find.byKey(const Key('connections_add_people')), findsOneWidget);
  });

  // With a large system font the label must shrink, not be cut off.
  testWidgets('"Celebrate back" fits its button with a large system font',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      iCelebrate: [],
      celebrateMe: [cid],
      tab: ConnectionsTab.celebrateMe,
    );

    final button = tester.getRect(find.byKey(const Key('celebrate_back_3')));
    final label = tester.getRect(find.text(AppStrings.celebrateBack));
    expect(button.left <= label.left && label.right <= button.right, isTrue,
        reason: 'label $label spills out of button $button');
  });
}
