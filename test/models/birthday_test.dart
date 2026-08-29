import 'package:birthday_app/models/birthday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextOccurrence', () {
    test('returns this year when the birthday is still ahead', () {
      final b = Birthday(month: 4, day: 15);
      expect(b.nextOccurrence(DateTime(2026, 1, 10)), DateTime(2026, 4, 15));
    });

    test('returns today when the birthday is today', () {
      final b = Birthday(month: 4, day: 15);
      expect(b.nextOccurrence(DateTime(2026, 4, 15)), DateTime(2026, 4, 15));
    });

    test('rolls to next year once the birthday has passed', () {
      final b = Birthday(month: 4, day: 15);
      expect(b.nextOccurrence(DateTime(2026, 4, 16)), DateTime(2027, 4, 15));
    });

    // The December-to-January wraparound that the reminder fan-out is tested
    // for in pgTAP. The client must agree with it.
    test('handles the December to January wraparound', () {
      final b = Birthday(month: 1, day: 4);
      expect(b.nextOccurrence(DateTime(2026, 12, 28)), DateTime(2027, 1, 4));
    });

    test('a Feb 29 birthday falls on Feb 28 in a non-leap year', () {
      final b = Birthday(month: 2, day: 29);
      expect(b.nextOccurrence(DateTime(2027, 1, 1)), DateTime(2027, 2, 28));
    });

    test('a Feb 29 birthday stays on Feb 29 in a leap year', () {
      final b = Birthday(month: 2, day: 29);
      expect(b.nextOccurrence(DateTime(2028, 1, 1)), DateTime(2028, 2, 29));
    });

    test('1900 is not a leap year and 2000 is', () {
      expect(Birthday.isLeapYear(1900), isFalse);
      expect(Birthday.isLeapYear(2000), isTrue);
      expect(Birthday.isLeapYear(2027), isFalse);
      expect(Birthday.isLeapYear(2028), isTrue);
    });
  });

  group('groupFrom', () {
    final b = Birthday(month: 4, day: 15);

    test('today', () {
      expect(b.groupFrom(DateTime(2026, 4, 15)), TimelineGroup.today);
    });

    test('tomorrow and day seven are this week', () {
      expect(b.groupFrom(DateTime(2026, 4, 14)), TimelineGroup.thisWeek);
      expect(b.groupFrom(DateTime(2026, 4, 8)), TimelineGroup.thisWeek);
    });

    test('day eight is this month', () {
      expect(b.groupFrom(DateTime(2026, 4, 7)), TimelineGroup.thisMonth);
    });

    test('day thirty-one is this month and day thirty-two is later', () {
      expect(b.groupFrom(DateTime(2026, 3, 15)), TimelineGroup.thisMonth);
      expect(b.groupFrom(DateTime(2026, 3, 14)), TimelineGroup.later);
    });
  });

  group('fromRow', () {
    test('returns null when the person has no birthday recorded', () {
      expect(
        Birthday.fromRow({'birth_month': null, 'birth_day': null}),
        isNull,
      );
    });

    test('reads month and day without a year', () {
      final b = Birthday.fromRow({
        'birth_month': 4,
        'birth_day': 15,
        'birth_year': null,
      });
      expect(b, isNotNull);
      expect(b!.month, 4);
      expect(b.day, 15);
      expect(b.year, isNull);
    });
  });

  group('occasionYear', () {
    test('on the birthday itself, it is this year', () {
      const b = Birthday(month: 4, day: 15);
      expect(b.occasionYear(DateTime(2026, 4, 15)), 2026);
    });

    test('a few days after, it is still this year', () {
      const b = Birthday(month: 4, day: 15);
      expect(b.occasionYear(DateTime(2026, 4, 20)), 2026);
    });

    test('a few days before, it is this year too', () {
      const b = Birthday(month: 4, day: 15);
      expect(b.occasionYear(DateTime(2026, 4, 10)), 2026);
    });

    // The case the rule exists for: a December birthday wished in January is
    // a belated wish for LAST December, not an early one for next.
    test('a December birthday wished in January belongs to last December', () {
      const b = Birthday(month: 12, day: 25);
      expect(b.occasionYear(DateTime(2027, 1, 5)), 2026);
    });

    test('the same birthday wished in December belongs to this December', () {
      const b = Birthday(month: 12, day: 25);
      expect(b.occasionYear(DateTime(2026, 12, 20)), 2026);
    });

    // Exactly halfway is a tie, and ties go to the past -- a wish is far more
    // often belated than six months early. 2028 is a leap year, so a Jan 1
    // birthday splits it into two equal 183-day halves: Jul 2 2028 is exactly
    // 183 days after Jan 1 2028 and exactly 183 days before Jan 1 2029. (A
    // non-leap year has an odd length, so no date ever ties exactly.)
    test('a tie resolves to the past', () {
      const b = Birthday(month: 1, day: 1);
      expect(b.occasionYear(DateTime(2028, 7, 2)), 2028);
    });

    // The Feb 29 rule already in this class applies unchanged, so the client
    // and the reminder fan-out continue to agree.
    test('a Feb 29 birthday resolves through Feb 28 in a non-leap year', () {
      const b = Birthday(month: 2, day: 29);
      expect(b.occasionYear(DateTime(2027, 3, 1)), 2027);
    });
  });
}
