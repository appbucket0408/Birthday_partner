import '../../models/app_notification.dart';

sealed class NotificationsState {
  const NotificationsState();
}

final class NotificationsLoading extends NotificationsState {
  const NotificationsLoading();
}

final class NotificationsEmpty extends NotificationsState {
  const NotificationsEmpty();
}

/// [items] keep the `seen` flag they had when loaded, so what was new when
/// the screen opened stays highlighted while it is open, even though opening
/// it marked everything seen on the server.
final class NotificationsLoaded extends NotificationsState {
  const NotificationsLoaded(
    this.items, {
    required this.hasMore,
    this.loadingMore = false,
    this.moreFailed = false,
  });

  final List<AppNotification> items;
  final bool hasMore;
  final bool loadingMore;
  final bool moreFailed;
}

final class NotificationsError extends NotificationsState {
  const NotificationsError(this.message);
  final String message;
}
