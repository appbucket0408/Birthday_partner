import '../../models/feed_entry.dart';

sealed class FeedState {
  const FeedState();
}

final class FeedLoading extends FeedState {
  const FeedLoading();
}

final class FeedEmpty extends FeedState {
  const FeedEmpty();
}

final class FeedLoaded extends FeedState {
  const FeedLoaded(
    this.entries, {
    required this.hasMore,
    this.loadingMore = false,
    this.moreFailed = false,
    this.error,
  });

  final List<FeedEntry> entries;
  final bool hasMore;
  final bool loadingMore;
  final bool moreFailed;
  final String? error;
}

final class FeedError extends FeedState {
  const FeedError(this.message);

  final String message;
}
