import '../api/api_params.dart';
import '../core/app_strings.dart';
import '../core/push_routes.dart';

enum AppNotificationKind {
  reminder,
  wish,
  celebration,

  /// A kind this build does not know yet. Shown generically rather than
  /// dropped, so a newer server never makes the list look emptier than it is.
  other;

  static AppNotificationKind fromWire(String? value) => switch (value) {
        'reminder' => reminder,
        'wish' => wish,
        'celebration' => celebration,
        _ => other,
      };
}

/// One row of my_notifications (20261018000006): a reminder or wish
/// notification the outbox queued for the signed-in user, whether or not a
/// push ever reached a phone.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.seen,
    required this.personId,
    this.wishId,
    this.subjectName,
    this.authorName,
    this.offsetDays,
  });

  final int id;
  final AppNotificationKind kind;
  final DateTime createdAt;

  /// Whether it was already on screen the last time the list was opened.
  final bool seen;

  /// Where a tap goes: the birthday person for a reminder, the recipient's
  /// own person (their wall) for a wish.
  final int personId;
  final int? wishId;
  final String? subjectName;
  final String? authorName;
  final int? offsetDays;

  factory AppNotification.fromRow(Map<String, dynamic> row) => AppNotification(
        id: row[ApiParams.id] as int,
        kind: AppNotificationKind.fromWire(row[ApiParams.kind] as String?),
        createdAt: DateTime.parse(row[ApiParams.createdAt] as String),
        seen: row[ApiParams.seen] as bool,
        personId: row[ApiParams.personId] as int,
        wishId: row[ApiParams.wishId] as int?,
        subjectName: row[ApiParams.subjectName] as String?,
        authorName: row[ApiParams.authorName] as String?,
        offsetDays: row[ApiParams.offsetDays] as int?,
      );

  /// The same words the push used (drain_reminders' reminderBody and
  /// wishBody), so the list reads like the notifications it records.
  String get text {
    switch (kind) {
      case AppNotificationKind.wish:
        return AppStrings.notificationWishTemplate
            .replaceFirst('%s', _name(authorName));
      case AppNotificationKind.celebration:
        return AppStrings.notificationCelebrationTemplate
            .replaceFirst('%s', _name(subjectName));
      case AppNotificationKind.reminder:
        final name = _name(subjectName);
        return switch (offsetDays) {
          0 => AppStrings.notificationTodayTemplate.replaceFirst('%s', name),
          1 => AppStrings.notificationTomorrowTemplate.replaceFirst('%s', name),
          final days? => AppStrings.notificationInDaysTemplate
              .replaceFirst('%1', name)
              .replaceFirst('%2', '$days'),
          null => AppStrings.notificationOther,
        };
      case AppNotificationKind.other:
        return AppStrings.notificationOther;
    }
  }

  /// The name shown on the avatar and in [text].
  String get displayName => _name(
        kind == AppNotificationKind.wish ? authorName : subjectName,
      );

  /// Built by [routeForPayload], the one place a payload becomes a route, so
  /// a tap here validates and routes exactly like a tap on the push.
  String? get route => routeForPayload({
        'person_id': '$personId',
        if (kind == AppNotificationKind.wish && wishId != null)
          'wish_id': '$wishId',
      });

  static String _name(String? raw) {
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? AppStrings.notificationSomeone : trimmed;
  }
}
