import 'dart:async';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/force_update/force_update_cubit.dart';
import 'package:birthday_app/features/force_update/force_update_screen.dart';
import 'package:birthday_app/features/force_update/soft_update_dialog.dart';
import 'package:birthday_app/repositories/app_update_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real fake, not a mock -- same pattern as the other feature tests.
class _FakeUpdates implements AppUpdateRepository {
  _FakeUpdates({this.status = UpdateStatus.upToDate, this.openStoreError});

  UpdateStatus status;
  Object? openStoreError;
  int openStoreCalls = 0;
  int snoozeCalls = 0;
  final changes = StreamController<UpdateStatus>.broadcast();

  @override
  Future<UpdateStatus> check() async => status;

  @override
  Stream<UpdateStatus> get statusChanges => changes.stream;

  @override
  Future<void> snoozeOptional() async => snoozeCalls++;

  @override
  Future<void> openStore() async {
    openStoreCalls++;
    if (openStoreError != null) throw openStoreError!;
  }
}

void main() {
  group('ForceUpdateCubit', () {
    test('starts upToDate so launch never waits on the check', () {
      final cubit =
          ForceUpdateCubit(_FakeUpdates(status: UpdateStatus.required));
      expect(cubit.state, UpdateStatus.upToDate);
    });

    blocTest<ForceUpdateCubit, UpdateStatus>(
      'emits what the check finds',
      build: () => ForceUpdateCubit(_FakeUpdates(status: UpdateStatus.optional)),
      act: (c) => c.check(),
      expect: () => [UpdateStatus.optional],
    );

    final live = _FakeUpdates();
    blocTest<ForceUpdateCubit, UpdateStatus>(
      'follows a minimum raised while the app is open',
      build: () => ForceUpdateCubit(live),
      act: (c) async {
        await c.check();
        live.changes.add(UpdateStatus.required);
      },
      expect: () => [UpdateStatus.upToDate, UpdateStatus.required],
    );

    final snoozable = _FakeUpdates(status: UpdateStatus.optional);
    blocTest<ForceUpdateCubit, UpdateStatus>(
      'later() dismisses an optional update and snoozes it',
      build: () => ForceUpdateCubit(snoozable),
      act: (c) async {
        await c.check();
        await c.later();
      },
      expect: () => [UpdateStatus.optional, UpdateStatus.upToDate],
      verify: (_) => expect(snoozable.snoozeCalls, 1),
    );

    final forced = _FakeUpdates(status: UpdateStatus.required);
    blocTest<ForceUpdateCubit, UpdateStatus>(
      'later() cannot dismiss a required update',
      build: () => ForceUpdateCubit(forced),
      act: (c) async {
        await c.check();
        await c.later();
      },
      expect: () => [UpdateStatus.required],
      verify: (_) => expect(forced.snoozeCalls, 0),
    );

    test('a failing store launch is swallowed, not thrown', () async {
      final updates = _FakeUpdates(openStoreError: Exception('no store'));
      await ForceUpdateCubit(updates).openStore();
      expect(updates.openStoreCalls, 1);
    });
  });

  group('ForceUpdateScreen', () {
    testWidgets('the button opens the store', (tester) async {
      final updates = _FakeUpdates(status: UpdateStatus.required);
      await tester.pumpWidget(
        BlocProvider(
          create: (_) => ForceUpdateCubit(updates),
          child: const MaterialApp(home: ForceUpdateScreen()),
        ),
      );
      expect(find.text(AppStrings.forceUpdateTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('force_update_button')));
      await tester.pump();
      expect(updates.openStoreCalls, 1);
    });
  });

  group('showSoftUpdateDialog', () {
    Future<Future<bool>> open(WidgetTester tester) async {
      late Future<bool> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showSoftUpdateDialog(context),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.softUpdateTitle), findsOneWidget);
      return result;
    }

    testWidgets('Update completes true', (tester) async {
      final result = await open(tester);
      await tester.tap(find.byKey(const Key('soft_update_button')));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('Later completes false', (tester) async {
      final result = await open(tester);
      await tester.tap(find.byKey(const Key('soft_update_later')));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('a tap outside counts as later', (tester) async {
      final result = await open(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });
}
