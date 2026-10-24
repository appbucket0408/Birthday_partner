import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logger.dart';
import '../../repositories/app_update_repository.dart';

/// This build's [UpdateStatus], app-level. [UpdateStatus.required] covers
/// every route with ForceUpdateScreen, deep links and pushes included;
/// [UpdateStatus.optional] shows the dismissible prompt once. Starts
/// [UpdateStatus.upToDate] so a slow fetch never holds up launch.
class ForceUpdateCubit extends Cubit<UpdateStatus> {
  ForceUpdateCubit(this._updates) : super(UpdateStatus.upToDate);

  final AppUpdateRepository _updates;
  StreamSubscription<UpdateStatus>? _sub;

  Future<void> check() async {
    _sub ??= _updates.statusChanges.listen(
      (status) {
        if (!isClosed) emit(status);
      },
      onError: (Object e, StackTrace s) =>
          Log.error('remote config listener failed', e, s),
    );
    final status = await _updates.check();
    if (!isClosed) emit(status);
  }

  /// "Later" on the optional prompt. Never applies to a required update.
  Future<void> later() async {
    if (state != UpdateStatus.optional) return;
    emit(UpdateStatus.upToDate);
    try {
      await _updates.snoozeOptional();
    } catch (e, s) {
      Log.error('snooze update failed', e, s);
    }
  }

  Future<void> openStore() async {
    try {
      await _updates.openStore();
    } catch (e, s) {
      Log.error('open store failed', e, s);
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
