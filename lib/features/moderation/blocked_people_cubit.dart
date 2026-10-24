import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../models/blocked_person.dart';
import '../../repositories/moderation_repository.dart';

sealed class BlockedPeopleState {
  const BlockedPeopleState();
}

final class BlockedPeopleLoading extends BlockedPeopleState {
  const BlockedPeopleLoading();
}

final class BlockedPeopleLoaded extends BlockedPeopleState {
  const BlockedPeopleLoaded(this.people, {this.error});

  final List<BlockedPerson> people;

  /// Transient, shown once.
  final String? error;
}

final class BlockedPeopleError extends BlockedPeopleState {
  const BlockedPeopleError(this.message);

  final String message;
}

class BlockedPeopleCubit extends Cubit<BlockedPeopleState>
    with ReentrancyGuard {
  BlockedPeopleCubit(this._repo) : super(const BlockedPeopleLoading());

  final ModerationRepository _repo;

  Future<void> load() => guard('load', () async {
    emit(const BlockedPeopleLoading());
    try {
      emit(BlockedPeopleLoaded(await _repo.blockedPeople()));
    } on AppFailure catch (f) {
      emit(BlockedPeopleError(f.message));
    } catch (_) {
      emit(const BlockedPeopleError(AppStrings.somethingWentWrong));
    }
  });

  Future<void> unblock(String profileId) => guard('unblock', () async {
    final current = state;
    if (current is! BlockedPeopleLoaded) return;
    try {
      await _repo.unblock(profileId);
      emit(
        BlockedPeopleLoaded([
          for (final p in current.people)
            if (p.profileId != profileId) p,
        ]),
      );
    } catch (_) {
      emit(
        BlockedPeopleLoaded(current.people, error: AppStrings.unblockFailed),
      );
    }
  });
}
