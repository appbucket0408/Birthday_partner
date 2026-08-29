import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../models/birthday.dart';
import '../../repositories/auth_repository.dart';
import 'profile_setup_state.dart';

class ProfileSetupCubit extends Cubit<ProfileSetupState> {
  ProfileSetupCubit(this._auth) : super(const ProfileSetupIdle());
  final AuthRepository _auth;

  Future<void> submit({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  }) async {
    emit(const ProfileSetupSaving());
    try {
      await _auth.completeProfile(
        handle: handle,
        displayName: displayName,
        city: city,
        birthday: birthday,
      );
      emit(const ProfileSetupDone());
    } on ServerFailure catch (f) {
      // 23505 is the unique index on profiles.handle.
      if (f.code == '23505') {
        emit(
          const ProfileSetupError(
            AppStrings.setupHandleTaken,
            handleTaken: true,
          ),
        );
      } else {
        emit(ProfileSetupError(f.message));
      }
    } on AppFailure catch (f) {
      emit(ProfileSetupError(f.message));
    }
  }
}
