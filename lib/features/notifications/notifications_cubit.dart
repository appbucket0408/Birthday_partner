import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/logger.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/notification_repository.dart';
import 'notifications_state.dart';

/// The Notifications screen. Same load / loadMore shape as FeedCubit.
class NotificationsCubit extends Cubit<NotificationsState> with ReentrancyGuard {
  NotificationsCubit(this._notifications, {this.pageSize = 50})
      : super(const NotificationsLoading());

  final NotificationRepository _notifications;
  final int pageSize;

  /// Loads the newest page, then marks everything seen: opening the list is
  /// looking at all of it. The page is fetched FIRST, so its `seen` flags
  /// still say what was new and the screen can highlight it.
  Future<void> load() => guard('fetch', () async {
        emit(const NotificationsLoading());
        try {
          final page = await _notifications.list(limit: pageSize);
          emit(
            page.isEmpty
                ? const NotificationsEmpty()
                : NotificationsLoaded(page, hasMore: page.length == pageSize),
          );
        } on AppFailure catch (f) {
          emit(NotificationsError(f.message));
          return;
        } catch (_) {
          emit(const NotificationsError(AppStrings.somethingWentWrong));
          return;
        }
        try {
          await _notifications.markAllSeen();
        } catch (e, s) {
          // The list is on screen either way; the worst case is the bell
          // still showing a count until the next visit.
          Log.error('marking notifications seen failed', e, s);
        }
      });

  Future<void> loadMore() async {
    final current = state;
    if (current is! NotificationsLoaded ||
        !current.hasMore ||
        current.loadingMore) {
      return;
    }
    await guard('fetch', () async {
      emit(
        NotificationsLoaded(current.items, hasMore: true, loadingMore: true),
      );
      try {
        final page = await _notifications.list(
          before: current.items.last.createdAt,
          limit: pageSize,
        );
        emit(
          NotificationsLoaded(
            [...current.items, ...page],
            hasMore: page.length == pageSize,
          ),
        );
      } catch (_) {
        emit(
          NotificationsLoaded(current.items, hasMore: true, moreFailed: true),
        );
      }
    });
  }
}
