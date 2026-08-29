import '../api/api_params.dart';

/// One year of the profile's track record, from public.my_birthday_stats().
///
/// [birthdaysCelebrated] counts DISTINCT people wished that year, which differs
/// from [wishesSent] once a cake post and a typed message can both land on the
/// same person in the same year. Dormant until M3 -- the function already
/// computes it distinctly.
class BirthdayStat {
  const BirthdayStat({
    required this.year,
    required this.wishesSent,
    required this.wishesReceived,
    required this.birthdaysCelebrated,
  });

  final int year;
  final int wishesSent;
  final int wishesReceived;
  final int birthdaysCelebrated;

  factory BirthdayStat.fromRow(Map<String, dynamic> row) => BirthdayStat(
        year: row[ApiParams.statYear] as int,
        wishesSent: row[ApiParams.wishesSent] as int,
        wishesReceived: row[ApiParams.wishesReceived] as int,
        birthdaysCelebrated: row[ApiParams.birthdaysCelebrated] as int,
      );
}
