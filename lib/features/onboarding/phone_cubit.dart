import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../repositories/auth_repository.dart';
import 'phone_state.dart';

class PhoneCubit extends Cubit<PhoneState> {
  PhoneCubit(this._auth) : super(const PhoneIdle());
  final AuthRepository _auth;

  String? _phoneE164;

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
    _phoneE164 = e164;

    emit(const PhoneSending());
    try {
      await _auth.sendOtp(e164);
      emit(PhoneCodeSent(e164));
    } on AppFailure catch (f) {
      emit(PhoneError(f.message));
    }
  }

  Future<void> submitCode(String token) async {
    final phone = _phoneE164;
    if (phone == null) return;
    // A verification already in flight owns this attempt. Without this
    // guard, editing the field during the async gap -- a correction, or a
    // delayed SMS autofill overwrite -- fires a second concurrent
    // verifyOtp/claimProfile.
    if (state is PhoneVerifying) return;

    emit(PhoneVerifying(phone));
    try {
      await _auth.verifyOtp(phoneE164: phone, token: token);
      await _auth.claimProfile();
      emit(const PhoneVerified());
    } on ServerFailure catch (f) {
      // 409: this account already claimed a different number. A distinct
      // message, because "try again" is not the remedy.
      emit(
        PhoneCodeSent(
          phone,
          error: f.code == '409' ? AppStrings.claimConflict : f.message,
        ),
      );
    } on AppFailure catch (f) {
      emit(PhoneCodeSent(phone, error: f.message));
    }
  }

  Future<void> resend() async {
    final phone = _phoneE164;
    if (phone == null) return;
    try {
      await _auth.sendOtp(phone);
      emit(PhoneCodeSent(phone));
    } on AppFailure catch (f) {
      emit(PhoneCodeSent(phone, error: f.message));
    }
  }
}
