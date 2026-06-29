import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/artist_stats.dart';
import 'api_providers.dart';

/// Drives the artist dashboard for one user. The aggregate stats + a page of the
/// per-post table arrive together; `goToPage` re-fetches with `page`/`page_size`
/// offset paging (the dashboard endpoint is page-numbered, not cursor-based).
class ArtistDashboardController extends StateNotifier<AsyncValue<ArtistDashboard>> {
  final Ref ref;
  final String userKey;
  int page = 1;
  static const int pageSize = 20;

  ArtistDashboardController(this.ref, this.userKey) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await ref
          .read(statsApiProvider)
          .artistDashboard(userKey, page: page, pageSize: pageSize);
      state = AsyncValue.data(data);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> goToPage(int p) async {
    if (p < 1) return;
    page = p;
    await load();
  }
}

final artistDashboardProvider = StateNotifierProvider.autoDispose
    .family<ArtistDashboardController, AsyncValue<ArtistDashboard>, String>(
        (ref, userKey) => ArtistDashboardController(ref, userKey));
