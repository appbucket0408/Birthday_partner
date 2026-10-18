import 'wish.dart';

class FeedEntry {
  const FeedEntry({
    required this.wish,
    this.subjectName,
    this.canOpenSubject = true,
  });

  final Wish wish;
  final String? subjectName;
  final bool canOpenSubject;
}
