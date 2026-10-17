import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/gift_interest_repository.dart';
import '../../repositories/person_repository.dart';

sealed class CakeComingSoonState {
  const CakeComingSoonState();
}

final class CakeComingSoonLoading extends CakeComingSoonState {
  const CakeComingSoonLoading();
}

/// [registered] is whether the user already asked to be notified for this
/// person. [saving] covers the Notify me tap; [error] is a transient message
/// from a failed one -- the page stays as it was.
final class CakeComingSoonReady extends CakeComingSoonState {
  const CakeComingSoonReady({
    required this.name,
    required this.registered,
    this.saving = false,
    this.error,
  });

  final String name;
  final bool registered;
  final bool saving;
  final String? error;
}

/// The "Send a cake" destination until gifting is live: who it is for, and
/// whether the user has asked to be told when it launches.
class CakeComingSoonCubit extends Cubit<CakeComingSoonState>
    with ReentrancyGuard {
  CakeComingSoonCubit(this._people, this._interest, this.personId)
      : super(const CakeComingSoonLoading());

  final PersonRepository _people;
  final GiftInterestRepository _interest;
  final int personId;

  /// Neither lookup is worth an error screen: without the name the page
  /// says "your friend", and an unknown registration shows the button.
  Future<void> load() => guard('load', () async {
        String name = AppStrings.cakeYourFriend;
        bool registered = false;
        try {
          name = (await _people.person(personId)).displayName;
        } catch (_) {}
        try {
          registered = await _interest.isRegistered(personId);
        } catch (_) {}
        emit(CakeComingSoonReady(name: name, registered: registered));
      });

  Future<void> notifyMe() => guard('notify', () async {
        final s = state;
        if (s is! CakeComingSoonReady || s.registered) return;
        emit(CakeComingSoonReady(name: s.name, registered: false, saving: true));
        try {
          await _interest.register(personId);
          emit(CakeComingSoonReady(name: s.name, registered: true));
        } on AppFailure catch (f) {
          emit(CakeComingSoonReady(
            name: s.name,
            registered: false,
            error: f.message,
          ));
        } catch (_) {
          emit(CakeComingSoonReady(
            name: s.name,
            registered: false,
            error: AppStrings.somethingWentWrong,
          ));
        }
      });
}
