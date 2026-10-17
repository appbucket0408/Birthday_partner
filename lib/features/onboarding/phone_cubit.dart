import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../repositories/auth_repository.dart';
import 'phone_state.dart';

class PhoneCubit extends Cubit<PhoneState> {
  PhoneCubit(this._auth) : super(const PhoneIdle());
  final AuthRepository _auth;

  /// Where the last code went: an E.164 number, or an email address when
  /// [_isEmail]. Kept here, not in state, so a resend or a retry after an
  /// error never depends on which state happens to be current.
  String? _destination;
  bool _isEmail = false;

  // Deliberately loose: the server is the real check (it has to deliver the
  // mail). This only catches the typos worth stopping before a round trip.
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> submitEmail(String raw) async {
    final email = raw.trim().toLowerCase();
    if (!_emailPattern.hasMatch(email)) {
      emit(const PhoneError(AppStrings.emailInvalid));
      return;
    }
    _destination = email;
    _isEmail = true;

    emit(const PhoneSending());
    try {
      await _auth.sendEmailOtp(email);
      emit(PhoneCodeSent(email));
    } on AppFailure catch (f) {
      emit(PhoneError(f.message));
    }
  }

  /// Normalises to E.164 on the device before anything is sent.
  ///
  /// This matters more than it looks: people.phone_e164_hash is a bare HMAC,
  /// so three spellings of one number are three rows and three separate
  /// social graphs. docs/db.md records this as a rule the backend paid for.
  Future<void> submitPhone(String raw, {String isoCode = 'IN'}) async {
    // PhoneNumber.parse itself throws PhoneNumberException on some inputs
    // rather than returning an invalid-but-parsed number -- '+09876543210'
    // (an Indian number typed with the trunk '0' after the '+') is an
    // ordinary typo, not garbage input. Wrapped the same way as the other
    // two call sites of this same library method: contacts_repository_impl
    // .dart's _toE164 and ImportCubit._regionIsoCode.
    // Hoisted out of the try below: IsoCode.values.byName(isoCode) throws on
    // an isoCode this app never issues -- a programming error, not a user
    // typo -- and must not be swallowed into "that phone number doesn't
    // look right". The only caller today passes the 'IN' default, so this
    // is latent, but the try block below exists solely to catch failures in
    // parsing the user's own input.
    final callerCountry = IsoCode.values.byName(isoCode);
    final PhoneNumber parsed;
    try {
      parsed = PhoneNumber.parse(raw, callerCountry: callerCountry);
    } catch (_) {
      emit(const PhoneError(AppStrings.phoneInvalid));
      return;
    }
    if (!parsed.isValid()) {
      emit(const PhoneError(AppStrings.phoneInvalid));
      return;
    }
    final e164 = '+${parsed.countryCode}${parsed.nsn}';
    _destination = e164;
    _isEmail = false;

    emit(const PhoneSending());
    try {
      await _auth.sendOtp(e164);
      emit(PhoneCodeSent(e164));
    } on AppFailure catch (f) {
      emit(PhoneError(f.message));
    }
  }

  Future<void> submitCode(String token) async {
    final destination = _destination;
    if (destination == null) return;
    // A verification already in flight owns this attempt. Without this
    // guard, editing the field during the async gap -- a correction, or a
    // delayed SMS autofill overwrite -- fires a second concurrent
    // verifyOtp/claimProfile.
    if (state is PhoneVerifying) return;

    emit(PhoneVerifying(destination));
    try {
      if (_isEmail) {
        await _auth.verifyEmailOtp(email: destination, token: token);
      } else {
        await _auth.verifyOtp(phoneE164: destination, token: token);
      }
      // An email account has nothing to claim until it has verified a phone
      // -- claim_profile refuses it. Sign-up does that step, then claims.
      // A returning email user who already linked one claims here exactly
      // like a phone user (claiming is idempotent).
      if (_auth.hasVerifiedPhone) await _auth.claimProfile();
      emit(PhoneVerified(welcomeName: await _returningName()));
    } on ServerFailure catch (f) {
      // 409: this account already claimed a different number. A distinct
      // message, because "try again" is not the remedy.
      emit(
        PhoneCodeSent(
          destination,
          error: f.code == '409' ? AppStrings.claimConflict : f.message,
        ),
      );
    } on AppFailure catch (f) {
      emit(PhoneCodeSent(destination, error: f.message));
    }
  }

  /// The display name of a user who has already finished sign-up, for the
  /// "Welcome back" greeting; null for a new one. Only a greeting: a failure
  /// here must not undo a successful sign-in, so it reads as "new user" and
  /// the session's own load decides where to go.
  Future<String?> _returningName() async {
    try {
      final profile = await _auth.loadProfile();
      return profile.hasCompletedOnboarding ? profile.displayName : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> resend() async {
    final destination = _destination;
    if (destination == null) return;
    try {
      if (_isEmail) {
        await _auth.sendEmailOtp(destination);
      } else {
        await _auth.sendOtp(destination);
      }
      emit(PhoneCodeSent(destination));
    } on AppFailure catch (f) {
      emit(PhoneCodeSent(destination, error: f.message));
    }
  }
}
