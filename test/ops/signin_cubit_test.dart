import 'dart:async';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/ops/signin/signin_cubit.dart';
import 'package:birthday_app/ops/signin/signin_state.dart';
import 'package:birthday_app/repositories/staff_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake that records calls, so assertions can be about what the cubit DID
/// rather than what a mock was told to return.
class _FakeStaffAuth implements StaffAuthRepository {
  _FakeStaffAuth({
    this.signInError,
    this.staff = true,
    this.gate,
  });

  Object? signInError;
  bool staff;

  /// When set, `signIn` suspends on this until it is completed, so two calls
  /// can genuinely overlap. ReentrancyGuard claims its key synchronously
  /// before the first await, so a test that awaited the first call would
  /// prove nothing.
  Completer<void>? gate;

  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    if (gate != null) await gate!.future;
    if (signInError != null) throw signInError!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<bool> isStaff() async => staff;
}

void main() {
  test('1. a staff sign-in ends in SignInReady', () async {
    final auth = _FakeStaffAuth(staff: true);
    final cubit = SignInCubit(auth);

    final emitted = <SignInState>[];
    cubit.stream.listen(emitted.add);

    await cubit.submit(email: 'ops@example.com', password: 'pw');

    expect(emitted.first, isA<SignInBusy>());
    expect(cubit.state, isA<SignInReady>());
  });

  test(
      '2. a NON-staff sign-in is refused AND signed out, leaving no usable '
      'session', () async {
    final auth = _FakeStaffAuth(staff: false);
    final cubit = SignInCubit(auth);

    await cubit.submit(email: 'nobody@example.com', password: 'pw');

    expect(cubit.state, isA<SignInRefused>());
    expect((cubit.state as SignInRefused).message, AppStrings.opsNotStaff);
    // The assertion that matters: refusing in the UI while leaving the
    // session alive would hand a non-staff caller an authenticated client.
    // RLS would still refuse every read, but the console must not be the
    // thing that created that situation.
    expect(auth.signOutCalls, 1);
  });

  test('3. an AuthFailure surfaces its own message', () async {
    final auth = _FakeStaffAuth(
      signInError: const AuthFailure('Invalid login credentials'),
    );
    final cubit = SignInCubit(auth);

    await cubit.submit(email: 'ops@example.com', password: 'wrong');

    expect(cubit.state, isA<SignInError>());
    expect((cubit.state as SignInError).message, 'Invalid login credentials');
    expect((cubit.state as SignInError).message,
        isNot(contains('Instance of')));
  });

  test('4. a non-AppFailure falls back to the generic message', () async {
    final auth = _FakeStaffAuth(signInError: StateError('boom'));
    final cubit = SignInCubit(auth);

    await cubit.submit(email: 'ops@example.com', password: 'pw');

    expect(cubit.state, isA<SignInError>());
    // The exact string, not isA<SignInError>() alone -- that would pass for
    // the AppFailure branch too, and could not tell '$e' from this.
    expect(
      (cubit.state as SignInError).message,
      AppStrings.somethingWentWrong,
    );
  });

  test('5. a second submit while the first is in flight is ignored', () async {
    final gate = Completer<void>();
    final auth = _FakeStaffAuth(gate: gate);
    final cubit = SignInCubit(auth);

    // Both fired WITHOUT awaiting the first: the guard claims its key
    // synchronously, so awaiting would release it and prove nothing.
    final first = cubit.submit(email: 'ops@example.com', password: 'pw');
    final second = cubit.submit(email: 'ops@example.com', password: 'pw');

    gate.complete();
    await Future.wait([first, second]);

    expect(auth.signInCalls, 1);
  });
}
