import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logger.dart';
import '../../repositories/notification_repository.dart';

/// The bell's unread count, shared by every tab's app bar (provided once in
/// HomeShell). Refreshed when a tab comes into view and when the
/// Notifications screen closes; a failed refresh keeps the last count rather
/// than flashing it away.
class NotificationBadgeCubit extends Cubit<int> {
  NotificationBadgeCubit(this._notifications) : super(0);

  final NotificationRepository _notifications;
  bool _inFlight = false;

  Future<void> refresh() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final count = await _notifications.unseenCount();
      if (!isClosed) emit(count);
    } catch (e, s) {
      Log.error('unseen notification count failed', e, s);
    } finally {
      _inFlight = false;
    }
  }

  /// The screen opened and marked everything seen.
  void clear() => emit(0);
}
