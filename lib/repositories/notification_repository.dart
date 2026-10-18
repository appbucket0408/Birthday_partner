import '../models/app_notification.dart';

/// The in-app Notifications screen and the bell's count. Everything is
/// scoped server-side to the signed-in user (20261018000006).
abstract interface class NotificationRepository {
  /// Newest first; [before] pages back from the oldest one already shown.
  Future<List<AppNotification>> list({DateTime? before, int limit = 50});

  /// How many have not been on screen yet: the bell's badge.
  Future<int> unseenCount();

  /// Marks every one seen. Called when the screen opens.
  Future<void> markAllSeen();
}
