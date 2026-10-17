import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/onboarding/otp_screen.dart';
import 'package:birthday_app/features/onboarding/phone_cubit.dart';
import 'package:birthday_app/features/onboarding/phone_state.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPhoneCubit extends MockCubit<PhoneState> implements PhoneCubit {}

void main() {
  late _MockPhoneCubit cubit;
  setUp(() {
    cubit = _MockPhoneCubit();
    // Unstubbed calls to a Future<void>-returning mock method return null,
    // not a Future, and the widget under test awaits nothing here but does
    // call these synchronously from onChanged/onPressed -- stub them so a
    // verified call doesn't also throw a type error.
    when(() => cubit.submitCode(any())).thenAnswer((_) async {});
    when(() => cubit.resend()).thenAnswer((_) async {});
  });

  Widget wrap() => MaterialApp(
    home: BlocProvider<PhoneCubit>.value(
      value: cubit,
      child: const OtpScreen(),
    ),
  );

  testWidgets('a six-digit entry submits automatically', (tester) async {
    whenListen(
      cubit,
      const Stream<PhoneState>.empty(),
      initialState: const PhoneCodeSent('+919999000001'),
    );
    await tester.pumpWidget(wrap());

    await tester.enterText(find.byKey(const Key('otp_field')), '12345');
    verifyNever(() => cubit.submitCode(any()));

    await tester.enterText(find.byKey(const Key('otp_field')), '123456');
    verify(() => cubit.submitCode('123456')).called(1);
  });

  testWidgets('resend is disabled during the cooldown', (tester) async {
    whenListen(
      cubit,
      const Stream<PhoneState>.empty(),
      initialState: const PhoneCodeSent('+919999000001'),
    );
    await tester.pumpWidget(wrap());

    final button = tester.widget<TextButton>(
      find.byKey(const Key('resend_button')),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('30'), findsOneWidget);
  });

  // The screen the user is thrown to on a wrong code is the screen they must
  // be able to retry from, with their number still on it.
  testWidgets('a rejected code keeps the user here with the error shown', (
    tester,
  ) async {
    whenListen(
      cubit,
      const Stream<PhoneState>.empty(),
      initialState: const PhoneCodeSent(
        '+919999000001',
        error: AppStrings.otpIncorrect,
      ),
    );
    await tester.pumpWidget(wrap());

    expect(find.text(AppStrings.otpIncorrect), findsOneWidget);
    expect(find.textContaining('+919999000001'), findsOneWidget);
  });

  testWidgets('a returning user sees "Welcome back" with their name',
      (tester) async {
    whenListen(
      cubit,
      const Stream<PhoneState>.empty(),
      initialState: const PhoneVerified(welcomeName: 'Sachin'),
    );
    await tester.pumpWidget(wrap());

    expect(find.byKey(const Key('welcome_back')), findsOneWidget);
    expect(
      find.text(AppStrings.welcomeBackTemplate.replaceFirst('%s', 'Sachin')),
      findsOneWidget,
    );
  });

  testWidgets('Verify is enabled only once all six digits are in',
      (tester) async {
    whenListen(
      cubit,
      const Stream<PhoneState>.empty(),
      initialState: const PhoneCodeSent('me@example.com'),
    );
    await tester.pumpWidget(wrap());

    FilledButton verify() =>
        tester.widget(find.byKey(const Key('otp_verify_button')));
    expect(verify().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('otp_field')), '123');
    await tester.pump();
    expect(verify().onPressed, isNull);
  });

  testWidgets('"Change" goes back to the sign-in screen', (tester) async {
    whenListen(
      cubit,
      const Stream<PhoneState>.empty(),
      initialState: const PhoneCodeSent('+919999000001'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BlocProvider<PhoneCubit>.value(
                  value: cubit,
                  child: const OtpScreen(),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(OtpScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('otp_change_button')));
    await tester.pumpAndSettle();
    expect(find.byType(OtpScreen), findsNothing);
  });
}
