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
    final parsed = PhoneNumber.parse(
      raw,
      callerCountry: IsoCode.values.byName(isoCode),
    );
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
