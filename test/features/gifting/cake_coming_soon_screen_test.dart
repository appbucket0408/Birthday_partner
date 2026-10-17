import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/gifting/cake_coming_soon_screen.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/repositories/gift_interest_repository.dart';
import 'package:birthday_app/repositories/person_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePeople implements PersonRepository {
  @override
  Future<Person> person(int personId) async =>
      Person(id: personId, displayName: 'b_08', isClaimed: true);

  @override
  Future<int> celebratorCount(int personId) async => 1;
}

class _FakeInterest implements GiftInterestRepository {
  _FakeInterest({this.registered = false, this.error});

  bool registered;
  final Object? error;
  final calls = <int>[];

  @override
  Future<bool> isRegistered(int personId) async => registered;

  @override
  Future<void> register(int personId) async {
    calls.add(personId);
    if (error != null) throw error!;
    registered = true;
  }
}

Future<_FakeInterest> _pump(
  WidgetTester tester, {
  bool registered = false,
  Object? error,
}) async {
  final interest = _FakeInterest(registered: registered, error: error);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<PersonRepository>.value(value: _FakePeople()),
        RepositoryProvider<GiftInterestRepository>.value(value: interest),
      ],
      child: const MaterialApp(home: CakeComingSoonScreen(personId: 8)),
    ),
  );
  await tester.pumpAndSettle();
  return interest;
}

void main() {
  testWidgets('previews cake gifting for this person, marked coming soon',
      (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('cake_coming_soon_badge')), findsOneWidget);
    expect(
      find.text(AppStrings.cakeTitleTemplate.replaceFirst('%s', 'b_08')),
      findsOneWidget,
    );
    expect(find.text(AppStrings.cakeFeatureFreshTitle), findsOneWidget);
    expect(find.byKey(const Key('cake_notify_me')), findsOneWidget);
  });

  testWidgets('Notify me registers interest and confirms', (tester) async {
    final interest = await _pump(tester);

    await tester.tap(find.byKey(const Key('cake_notify_me')));
    await tester.pumpAndSettle();

    expect(interest.calls, [8]);
    expect(find.byKey(const Key('cake_registered')), findsOneWidget);
    expect(find.text(AppStrings.cakeRegisteredTitle), findsOneWidget);
    expect(find.byKey(const Key('cake_notify_me')), findsNothing);
  });

  testWidgets('coming back after registering shows "on the list" straight away',
      (tester) async {
    await _pump(tester, registered: true);

    expect(find.byKey(const Key('cake_registered')), findsOneWidget);
    expect(find.byKey(const Key('cake_notify_me')), findsNothing);
  });

  testWidgets('a failed registration keeps the button and says why',
      (tester) async {
    await _pump(tester, error: const ServerFailure('offline'));

    await tester.tap(find.byKey(const Key('cake_notify_me')));
    await tester.pumpAndSettle();

    expect(find.text('offline'), findsOneWidget);
    expect(find.byKey(const Key('cake_notify_me')), findsOneWidget);
  });
}
