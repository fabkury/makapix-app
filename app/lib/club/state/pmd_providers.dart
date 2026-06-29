import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/pmd.dart';
import 'api_providers.dart';

/// Bulk endpoints accept at most this many ids per request; selections above it
/// are chunked. (The delete UI additionally caps a single delete at 32.)
const int kPmdBatchMax = 128;
const int kPmdDeleteMax = 32;

List<List<int>> _chunk(List<int> ids, int size) {
  final out = <List<int>>[];
  for (var i = 0; i < ids.length; i += size) {
    out.add(ids.sublist(i, i + size > ids.length ? ids.length : i + size));
  }
  return out;
}

/// State for the PMD post list: a cursor-paged set of the user's posts plus the
/// current selection and a busy flag while a mutation is in flight.
class PmdState {
  final List<PmdPostItem> items;
  final String? cursor;
  final bool loading;
  final bool atEnd;
  final bool initialized;
  final String? error;
  final Set<int> selected;
  final bool busy;

  const PmdState({
    this.items = const [],
    this.cursor,
    this.loading = false,
    this.atEnd = false,
    this.initialized = false,
    this.error,
    this.selected = const {},
    this.busy = false,
  });

  PmdState copyWith({
    List<PmdPostItem>? items,
    String? cursor,
    bool keepCursor = false,
    bool? loading,
    bool? atEnd,
    bool? initialized,
    String? error,
    bool clearError = false,
    Set<int>? selected,
    bool? busy,
  }) =>
      PmdState(
        items: items ?? this.items,
        cursor: keepCursor ? this.cursor : cursor,
        loading: loading ?? this.loading,
        atEnd: atEnd ?? this.atEnd,
        initialized: initialized ?? this.initialized,
        error: clearError ? null : (error ?? this.error),
        selected: selected ?? this.selected,
        busy: busy ?? this.busy,
      );
}

class PmdController extends StateNotifier<PmdState> {
  final Ref ref;
  PmdController(this.ref) : super(const PmdState());

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
    state = state.copyWith(loading: true, keepCursor: true);
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    try {
      final page = await ref.read(pmdApiProvider).listPosts(cursor: reset ? null : state.cursor);
      final items = reset ? page.items : <PmdPostItem>[...state.items, ...page.items];
      state = PmdState(
        items: items,
        cursor: page.nextCursor,
        loading: false,
        atEnd: page.nextCursor == null,
        initialized: true,
        selected: reset ? const {} : state.selected,
      );
    } catch (e) {
      state = state.copyWith(
          loading: false, initialized: true, keepCursor: true, error: _msg(e, 'load your posts'));
    }
  }

  // ---- selection ----
  void toggle(int id) {
    final sel = {...state.selected};
    sel.contains(id) ? sel.remove(id) : sel.add(id);
    state = state.copyWith(selected: sel);
  }

  void selectAllLoaded() =>
      state = state.copyWith(selected: {for (final p in state.items) p.id});

  void clearSelection() => state = state.copyWith(selected: const {});

  // ---- mutations (await-then-apply; chunked at 128) ----

  Future<String?> hide() => _action('hide');
  Future<String?> unhide() => _action('unhide');
  Future<String?> delete() => _action('delete');

  Future<String?> _action(String action) async {
    final ids = state.selected.toList();
    if (ids.isEmpty) return null;
    state = state.copyWith(busy: true);
    try {
      for (final c in _chunk(ids, kPmdBatchMax)) {
        await ref.read(pmdApiProvider).batchAction(action, c);
      }
      final sel = state.selected;
      final List<PmdPostItem> items;
      if (action == 'delete') {
        items = state.items.where((p) => !sel.contains(p.id)).toList();
      } else {
        final hidden = action == 'hide';
        items = state.items
            .map((p) => sel.contains(p.id) ? p.copyWith(hiddenByUser: hidden) : p)
            .toList();
      }
      state = state.copyWith(items: items, selected: const {}, busy: false);
      return null;
    } catch (e) {
      state = state.copyWith(busy: false);
      await refresh(); // resync on partial failure
      return _msg(e, 'complete that action');
    }
  }

  Future<String?> setLicense(int? licenseId, String? identifier) async {
    final ids = state.selected.toList();
    if (ids.isEmpty) return null;
    state = state.copyWith(busy: true);
    try {
      for (final c in _chunk(ids, kPmdBatchMax)) {
        await ref.read(pmdApiProvider).batchLicense(c, licenseId);
      }
      final sel = state.selected;
      final items = state.items
          .map((p) => sel.contains(p.id)
              ? p.copyWith(licenseIdentifier: identifier, clearLicense: identifier == null)
              : p)
          .toList();
      state = state.copyWith(items: items, selected: const {}, busy: false);
      return null;
    } catch (e) {
      state = state.copyWith(busy: false);
      await refresh();
      return _msg(e, 'change the license');
    }
  }

  /// Queue a ZIP export of the current selection. Returns an error message, or
  /// null on success (caller refreshes the BDR list).
  Future<String?> requestDownload({
    required bool includeComments,
    required bool includeReactions,
    required bool sendEmail,
  }) async {
    final ids = state.selected.toList();
    if (ids.isEmpty) return 'Select at least one post.';
    if (ids.length > kPmdBatchMax) return 'Select at most $kPmdBatchMax posts per download.';
    state = state.copyWith(busy: true);
    try {
      await ref.read(pmdApiProvider).createBdr(
            ids,
            includeComments: includeComments,
            includeReactions: includeReactions,
            sendEmail: sendEmail,
          );
      state = state.copyWith(busy: false, selected: const {});
      return null;
    } catch (e) {
      state = state.copyWith(busy: false);
      return _msg(e, 'request the download');
    }
  }

  String _msg(Object e, String what) =>
      e is ClubError ? e.message : 'Could not $what.';
}

final pmdListProvider = StateNotifierProvider.autoDispose<PmdController, PmdState>(
    (ref) => PmdController(ref)..loadInitial());

/// The user's batch-download jobs, polled every 5s while any job is in progress.
class BdrListController extends StateNotifier<AsyncValue<List<Bdr>>> {
  final Ref ref;
  bool _polling = false;
  BdrListController(this.ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final items = await ref.read(pmdApiProvider).listBdr();
      state = AsyncValue.data(items);
      _maybePoll();
    } catch (e, st) {
      if (state is! AsyncData) state = AsyncValue.error(e, st);
    }
  }

  void _maybePoll() {
    final active = (state.value ?? const []).any((b) => b.inProgress);
    if (active && !_polling) {
      _polling = true;
      _loop();
    } else if (!active) {
      _polling = false;
    }
  }

  Future<void> _loop() async {
    while (_polling && mounted) {
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      try {
        final items = await ref.read(pmdApiProvider).listBdr();
        state = AsyncValue.data(items);
        if (!items.any((b) => b.inProgress)) _polling = false;
      } catch (_) {
        // keep last good state; try again next tick
      }
    }
  }
}

final bdrListProvider =
    StateNotifierProvider.autoDispose<BdrListController, AsyncValue<List<Bdr>>>(
        (ref) => BdrListController(ref));
