import 'wish.dart';

class FeedEntry {
  const FeedEntry({required this.wish, this.subjectName});

  final Wish wish;
  final String? subjectName;
}
