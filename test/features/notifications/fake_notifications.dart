import 'package:birthday_app/models/app_notification.dart';
import 'package:birthday_app/repositories/notification_repository.dart';

/// A real fake, not a mock, shared by the notifications tests.
class FakeNotifications implements NotificationRepository {
  FakeNotifications({List<AppNotification>? items, this.unseen = 0})
      : items = items ?? [];

  List<AppNotification> items;
  int unseen;
  Object? listError;
  Object? markError;
  final calls = <String>[];

  @override
  Future<List<AppNotification>> list({DateTime? before, int limit = 50}) async {
    calls.add(before == null ? 'list' : 'list-before');
    if (listError != null) throw listError!;
    final older = before == null
        ? items
        : items.where((n) => n.createdAt.isBefore(before)).toList();
    return older.take(limit).toList();
  }

  @override
  Future<int> unseenCount() async {
    calls.add('count');
    return unseen;
  }

  @override
  Future<void> markAllSeen() async {
    calls.add('markAllSeen');
    if (markError != null) throw markError!;
    unseen = 0;
  }
}

AppNotification reminderN(
  int id, {
  String name = 'Asha',
  int offset = 1,
  bool seen = false,
  DateTime? at,
}) =>
    AppNotification(
      id: id,
      kind: AppNotificationKind.reminder,
      createdAt: at ?? DateTime.utc(2026, 10, 18, 9).subtract(Duration(hours: id)),
      seen: seen,
      personId: 40 + id,
      subjectName: name,
      offsetDays: offset,
    );

AppNotification wishN(
  int id, {
  String? author = 'Ravi',
  bool seen = false,
}) =>
    AppNotification(
      id: id,
      kind: AppNotificationKind.wish,
      createdAt: DateTime.utc(2026, 10, 18, 9).subtract(Duration(hours: id)),
      seen: seen,
      personId: 7,
      wishId: 900 + id,
      subjectName: 'Me',
      authorName: author,
    );
