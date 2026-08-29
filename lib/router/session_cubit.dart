import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/logger.dart';
import '../repositories/auth_repository.dart';
import 'session_state.dart';

/// The single source of truth for which part of the app the user belongs in.
///
/// The completion signal is `profiles.birth_month is not null`. The handle and
/// display name cannot be used: private.handle_new_user sets both to
/// placeholders at signup, so both are non-null on a brand new account.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._auth) : super(const SessionUnknown());
  final AuthRepository _auth;

  Future<void> load() async {
    if (_auth.currentUserId == null) {
      emit(const SessionSignedOut());
      return;
    }
    try {
      final profile = await _auth.loadProfile();
      emit(profile.hasCompletedOnboarding
          ? SessionReady(profile)
          : const SessionNeedsSetup());
    } catch (e, s) {
      // A session we cannot resolve is worse than no session: the user would
      // sit on a splash with no way forward. Signing out is recoverable.
      Log.error('session load failed', e, s);
      emit(const SessionSignedOut());
    }
  }

  Future<void> onSignedIn() => load();

  Future<void> onProfileCompleted() => load();

  Future<void> signOut() async {
    await _auth.signOut();
    emit(const SessionSignedOut());
  }
}
