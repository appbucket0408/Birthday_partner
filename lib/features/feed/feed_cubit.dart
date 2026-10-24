import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/analytics.dart';
import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/wish_repository.dart';
import 'feed_state.dart';

class FeedCubit extends Cubit<FeedState> with ReentrancyGuard {
  FeedCubit(this._wishes, {this.pageSize = 20}) : super(const FeedLoading());

  final WishRepository _wishes;
  final int pageSize;
  bool _scrollLogged = false;

  /// Logs feed_scrolled once per visit; [refresh] starts a new visit.
  void userScrolled() {
    final current = state;
    if (_scrollLogged || current is! FeedLoaded) return;
    _scrollLogged = true;
    Analytics.log(
      AppEvent.feedScrolled,
      {AppParam.postsLoaded: current.entries.length},
    ).ignore();
  }

  Future<void> load() => guard('fetch', () async {
        emit(const FeedLoading());
        try {
          final page = await _wishes.feed(limit: pageSize);
          emit(
            page.isEmpty
                ? const FeedEmpty()
                : FeedLoaded(page, hasMore: page.length == pageSize),
          );
        } on AppFailure catch (f) {
          emit(FeedError(f.message));
        } catch (_) {
          emit(const FeedError(AppStrings.somethingWentWrong));
        }
      });

  /// Pull-to-refresh, and the tab coming back into view: reloads the newest
  /// page without blanking a list that is already on screen.
  Future<void> refresh() async {
    _scrollLogged = false;
    final current = state;
    if (current is! FeedLoaded) return load();
    await guard('fetch', () async {
      try {
        final page = await _wishes.feed(limit: pageSize);
        emit(
          page.isEmpty
              ? const FeedEmpty()
              : FeedLoaded(page, hasMore: page.length == pageSize),
        );
      } catch (_) {
        emit(
          FeedLoaded(
            current.entries,
            hasMore: current.hasMore,
            error: AppStrings.somethingWentWrong,
          ),
        );
      }
    });
  }

  Future<void> loadMore() async {
    final current = state;
    if (current is! FeedLoaded || !current.hasMore || current.loadingMore) {
      return;
    }
    await guard('fetch', () async {
      emit(FeedLoaded(current.entries, hasMore: true, loadingMore: true));
      try {
        final page = await _wishes.feed(
          before: current.entries.last.wish.createdAt,
          limit: pageSize,
        );
        emit(
          FeedLoaded(
            [...current.entries, ...page],
            hasMore: page.length == pageSize,
          ),
        );
      } catch (_) {
        emit(FeedLoaded(current.entries, hasMore: true, moreFailed: true));
      }
    });
  }
}
