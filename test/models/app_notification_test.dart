import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/models/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromRow reads a my_notifications row', () {
    final n = AppNotification.fromRow({
      'id': 3,
      'kind': 'wish',
      'created_at': '2026-10-18T09:00:00Z',
      'seen': false,
      'person_id': 7,
      'wish_id': 99,
      'subject_name': 'Me',
      'author_name': 'Asha',
      'offset_days': null,
      'occasion_date': null,
    });
    expect(n.kind, AppNotificationKind.wish);
    expect(n.wishId, 99);
    expect(n.seen, isFalse);
    expect(n.createdAt, DateTime.utc(2026, 10, 18, 9));
  });

  test('an unknown kind is kept, not dropped, and shown generically', () {
    final n = AppNotification.fromRow({
      'id': 1,
      'kind': 'anniversary',
      'created_at': '2026-10-18T09:00:00Z',
      'seen': true,
      'person_id': 7,
    });
    expect(n.kind, AppNotificationKind.other);
    expect(n.text, AppStrings.notificationOther);
  });

  group('text says what the push said', () {
    AppNotification reminder(int? offset) => AppNotification(
          id: 1,
          kind: AppNotificationKind.reminder,
          createdAt: DateTime.utc(2026),
          seen: true,
          personId: 4,
          subjectName: 'Asha',
          offsetDays: offset,
        );

    test('today, tomorrow, in N days', () {
      expect(reminder(0).text, "It's Asha's birthday today.");
      expect(reminder(1).text, "Asha's birthday is tomorrow.");
      expect(reminder(7).text, "Asha's birthday is in 7 days.");
    });

    test('a wish names its author, or Someone', () {
      AppNotification wish(String? author) => AppNotification(
            id: 1,
            kind: AppNotificationKind.wish,
            createdAt: DateTime.utc(2026),
            seen: true,
            personId: 7,
            wishId: 9,
            authorName: author,
          );
      expect(wish('Ravi').text, 'Ravi left you a birthday wish.');
      expect(wish('  ').text, 'Someone left you a birthday wish.');
      expect(wish(null).displayName, 'Someone');
    });
  });

  group('route goes where the push would', () {
    test('a reminder opens the birthday person', () {
      final n = AppNotification(
        id: 1,
        kind: AppNotificationKind.reminder,
        createdAt: DateTime.utc(2026),
        seen: true,
        personId: 42,
        offsetDays: 0,
      );
      expect(n.route, '/person/42');
    });

    test('a wish opens my wall with the wish on top', () {
      final n = AppNotification(
        id: 1,
        kind: AppNotificationKind.wish,
        createdAt: DateTime.utc(2026),
        seen: true,
        personId: 7,
        wishId: 99,
      );
      expect(n.route, '/person/7?wish=99');
    });
  });
}
