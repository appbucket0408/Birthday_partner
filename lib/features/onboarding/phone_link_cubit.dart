import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/auth_repository.dart';

sealed class PhoneLinkState {
  const PhoneLinkState();
}

/// Nothing sent yet. [error] is a rejected number (bad format, or already on
/// another account).
final class PhoneLinkIdle extends PhoneLinkState {
  const PhoneLinkIdle({this.error});
  final String? error;
}

final class PhoneLinkSending extends PhoneLinkState {
  const PhoneLinkSending();
}

/// [error] is a rejected code; the user stays here with the number intact.
final class PhoneLinkCodeSent extends PhoneLinkState {
  const PhoneLinkCodeSent(this.phoneE164, {this.error});
  final String phoneE164;
  final String? error;
}

final class PhoneLinkVerifying extends PhoneLinkState {
  const PhoneLinkVerifying(this.phoneE164);
  final String phoneE164;
}

/// Verified AND claimed: the account now owns its person row, which is what
/// lets sign-up finish.
final class PhoneLinkDone extends PhoneLinkState {
  const PhoneLinkDone(this.phoneE164);
  final String phoneE164;
}

/// Sign-up's phone step for an account that signed in by email.
///
/// Friends find each other by phone, and `claim_profile` only links a
/// session to a person through a VERIFIED phone. Typing a number is not
/// enough -- that would let anyone take over the birthday profile behind
/// someone else's number -- so this texts a code to it, verifies it as a
/// phone change on the signed-in account, then claims.
class PhoneLinkCubit extends Cubit<PhoneLinkState> with ReentrancyGuard {
  PhoneLinkCubit(this._auth) : super(const PhoneLinkIdle());
  final AuthRepository _auth;

  String? _phoneE164;

  // Set once the code is accepted. A code is single-use, so if the claim
  // after it fails, a retry must claim again WITHOUT re-verifying.
  bool _verified = false;

  /// Same normalisation as [PhoneCubit.submitPhone], for the same reason:
  /// three spellings of one number would be three people.
  Future<void> send(String raw, {String isoCode = 'IN'}) =>
      guard('send', () async {
        final callerCountry = IsoCode.values.byName(isoCode);
        final PhoneNumber parsed;
        try {
          parsed = PhoneNumber.parse(raw, callerCountry: callerCountry);
        } catch (_) {
          emit(const PhoneLinkIdle(error: AppStrings.phoneInvalid));
          return;
        }
        if (!parsed.isValid()) {
          emit(const PhoneLinkIdle(error: AppStrings.phoneInvalid));
          return;
        }
        final e164 = '+${parsed.countryCode}${parsed.nsn}';
        _phoneE164 = e164;
        _verified = false;

        emit(const PhoneLinkSending());
        try {
          await _auth.sendPhoneLink(e164);
          emit(PhoneLinkCodeSent(e164));
        } on AppFailure catch (f) {
          emit(PhoneLinkIdle(error: f.message));
        }
      });

  Future<void> verify(String token) => guard('verify', () async {
        final phone = _phoneE164;
        if (phone == null) return;
        emit(PhoneLinkVerifying(phone));
        try {
          if (!_verified) {
            await _auth.verifyPhoneLink(phoneE164: phone, token: token);
            _verified = true;
          }
          await _auth.claimProfile();
          emit(PhoneLinkDone(phone));
        } on ServerFailure catch (f) {
          emit(
            PhoneLinkCodeSent(
              phone,
              error: f.code == '409' ? AppStrings.claimConflict : f.message,
            ),
          );
        } on AppFailure catch (f) {
          emit(PhoneLinkCodeSent(phone, error: f.message));
        }
      });

  /// Back to entering a number, e.g. after a typo in it.
  void editNumber() => emit(const PhoneLinkIdle());
}
