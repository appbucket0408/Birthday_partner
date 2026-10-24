import 'wish.dart';

class FeedEntry {
  const FeedEntry({
    required this.wish,
    this.subjectName,
    this.canOpenSubject = true,
    this.authorPersonId,
  });

  final Wish wish;
  final String? subjectName;
  final bool canOpenSubject;

  /// Null when the author has no person row (never claimed one).
  final int? authorPersonId;
}
