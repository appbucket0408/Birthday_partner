import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/analytics.dart';
import '../../core/app_strings.dart';
import '../../core/photo_picker.dart';
import '../../core/result.dart';
import '../../models/birthday.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/avatar_repository.dart';
import 'profile_setup_state.dart';

class ProfileSetupCubit extends Cubit<ProfileSetupState> {
  ProfileSetupCubit(this._auth, this._avatars)
      : super(const ProfileSetupIdle());
  final AuthRepository _auth;
  final AvatarRepository _avatars;

  Future<void> submit({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
    PhotoPicked? photo,
  }) async {
    // A save already in flight owns this attempt. The button disables on
    // ProfileSetupSaving, but that only takes effect a microtask after this
    // state propagates -- the cubit, not the widget, is the source of truth
    // for what is in flight, so the guard belongs here too.
    if (state is ProfileSetupSaving) return;

    emit(const ProfileSetupSaving());
    try {
      // Safety net for an email sign-up whose phone was verified but whose
      // claim never ran (the app was closed in between): claiming is
      // idempotent, and finishing sign-up without it would leave the account
      // with no person behind it.
      if (_auth.hasVerifiedPhone) await _auth.claimProfile();
      await _auth.completeProfile(
        handle: handle,
        displayName: displayName,
        city: city,
        birthday: birthday,
      );
      Analytics.log(AppEvent.signUp, {AppParam.method: 'phone'}).ignore();
      // After the profile, not before: completeProfile is what can reject
      // the handle, and uploading first would re-upload on every rename.
      if (photo != null) {
        try {
          await _avatars.upload(photo.bytes, extension: photo.extension);
        } on AppFailure {
          emit(const ProfileSetupError(AppStrings.photoUploadFailed));
          return;
        }
      }
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
