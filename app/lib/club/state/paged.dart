import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/page.dart';

/// Immutable state for an infinite, cursor-paginated list.
class PagedState<T> {
  final List<T> items;
  final String? cursor;
  final bool loading;
  final bool atEnd;
  final String? error;
  final bool initialized;

  const PagedState({
    this.items = const [],
    this.cursor,
    this.loading = false,
    this.atEnd = false,
    this.error,
    this.initialized = false,
  });

  PagedState<T> copyWith({
    List<T>? items,
    bool? loading,
    bool? atEnd,
    bool? initialized,
    String? error,
    bool clearError = false,
  }) =>
      PagedState<T>(
        items: items ?? this.items,
        cursor: cursor,
        loading: loading ?? this.loading,
        atEnd: atEnd ?? this.atEnd,
        error: clearError ? null : (error ?? this.error),
        initialized: initialized ?? this.initialized,
      );
}

typedef PageFetcher<T> = Future<Page<T>> Function(String? cursor);

/// Drives a [PagedState] from a [PageFetcher]: load-initial, refresh, load-more.
/// A null `next_cursor` (or an unimplemented server cursor) means `atEnd`.
class PagedNotifier<T> extends StateNotifier<PagedState<T>> {
  final PageFetcher<T> fetch;

  /// Called with each successfully fetched page's items (post feeds prefetch artwork here).
  final void Function(List<T> items)? onPage;

  PagedNotifier(this.fetch, {this.onPage}) : super(PagedState<T>());

  Future<void> loadInitial() async {
    if (state.initialized && state.items.isNotEmpty) return;
    state = state.copyWith(loading: true, clearError: true);
    await _load(reset: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    await _load(reset: true);
  }

  Future<void> loadMore() async {
    if (state.loading || state.atEnd) return;
    state = state.copyWith(loading: true);
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    try {
      final page = await fetch(reset ? null : state.cursor);
      if (page.items.isNotEmpty) onPage?.call(page.items);
      final items = reset ? page.items : <T>[...state.items, ...page.items];
      state = PagedState<T>(
        items: items,
        cursor: page.nextCursor,
        loading: false,
        atEnd: page.nextCursor == null,
        initialized: true,
      );
    } on ClubError catch (e) {
      state = state.copyWith(loading: false, error: e.message, initialized: true);
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Failed to load.', initialized: true);
    }
  }
}
