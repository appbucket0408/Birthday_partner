import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/date_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateLabels.ago', () {
    final now = DateTime(2026, 10, 18, 15, 30);
    String ago(DateTime d) => DateLabels.ago(d, now);

    test('under a minute is "Just now"', () {
      expect(ago(now.subtract(const Duration(seconds: 40))),
          AppStrings.feedJustNow);
    });

    test('minutes, then hours, within today', () {
      expect(ago(now.subtract(const Duration(minutes: 12))), '12m');
      expect(ago(DateTime(2026, 10, 18, 9)), '6h');
    });

    test('yesterday by the calendar, even under 24 hours ago', () {
      expect(ago(DateTime(2026, 10, 17, 23, 50)), AppStrings.feedYesterday);
    });

    test('older dates drop the year only when it is this year', () {
      expect(ago(DateTime(2026, 10, 2)), '2 October');
      expect(ago(DateTime(2025, 12, 31)), '31 December 2025');
    });
  });
}
