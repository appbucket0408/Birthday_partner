import 'wish.dart';

class FeedEntry {
  const FeedEntry({
    required this.wish,
    this.subjectName,
    this.canOpenSubject = true,
    this.authorPersonId,
    this.canDelete = false,
  });

  final Wish wish;
  final String? subjectName;
  final bool canOpenSubject;

  /// Null when the author has no person row (never claimed one).
  final int? authorPersonId;

  /// The viewer wrote it, or it is on the viewer's own wall.
  final bool canDelete;
}
