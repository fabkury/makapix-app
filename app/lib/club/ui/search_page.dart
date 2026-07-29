import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hashtag.dart';
import '../models/post.dart';
import '../state/api_providers.dart';
import '../state/paged.dart';
import 'artwork_detail_page.dart';
import 'hashtag_feed_page.dart';
import 'profile_page.dart';
import 'widgets/common.dart';

// Cursor-paged search feeds. autoDispose: keyed by the raw query (and sort) —
// without it, every query ever typed would be cached for the app's lifetime;
// the keep-alive tab widgets keep only the currently-watched key live. [audit F-19]
final _artworkSearchProvider = StateNotifierProvider.autoDispose
    .family<PagedNotifier<Post>, PagedState<Post>, String>((ref, q) {
  final api = ref.watch(searchApiProvider);
  final n = PagedNotifier<Post>((cursor) => api.searchPosts(q, cursor: cursor));
  n.loadInitial();
  return n;
});

final _userSearchProvider = StateNotifierProvider.autoDispose
    .family<PagedNotifier<PostOwner>, PagedState<PostOwner>, ({String q, String sort})>((ref, k) {
  final api = ref.watch(searchApiProvider);
  final n =
      PagedNotifier<PostOwner>((cursor) => api.browseUsers(k.q, sort: k.sort, cursor: cursor));
  n.loadInitial();
  return n;
});

final _hashtagSearchProvider = StateNotifierProvider.autoDispose
    .family<PagedNotifier<HashtagStat>, PagedState<HashtagStat>, ({String q, String sort})>(
        (ref, k) {
  final api = ref.watch(searchApiProvider);
  final n = PagedNotifier<HashtagStat>(
      (cursor) => api.hashtagStats(k.q, sort: k.sort, cursor: cursor));
  n.loadInitial();
  return n;
});

/// The Search page, embedded as the last swipeable page of the Club home's PageView (it has no
/// Scaffold/AppBar of its own — the home top bar stays). The query field, active tab, sorts, and
/// results survive swiping away and back (keep-alive). The Artworks/Users/Hashtags tabs switch by
/// tap only: a swipeable TabBarView would capture horizontal drags and trap the user on this page.
/// Users and Hashtags double as browsable directories: with an empty query they list everyone /
/// every tag under the chosen sort (website parity). All three tabs infinite-scroll.
/// [searchFocus] is owned by the home page so the top-bar Search icon can focus the field (swipe
/// arrivals deliberately don't pop the keyboard).
class SearchView extends ConsumerStatefulWidget {
  final FocusNode? searchFocus;
  const SearchView({super.key, this.searchFocus});
  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late final TabController _tab = TabController(length: 3, vsync: this);
  final _field = TextEditingController();
  String _q = '';
  String _userSort = 'alphabetical';
  String _tagSort = 'popularity';

  @override
  void dispose() {
    _tab.dispose();
    _field.dispose();
    super.dispose();
  }

  void _run() => setState(() => _q = _field.text.trim());

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    return Column(children: [
      CenteredContent(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: TextField(
            controller: _field,
            focusNode: widget.searchFocus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: 'Search Makapix Club…',
              border: InputBorder.none,
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _run),
            ),
          ),
        ),
      ),
      TabBar(
        controller: _tab,
        tabs: const [Tab(text: 'Artworks'), Tab(text: 'Users'), Tab(text: 'Hashtags')],
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          // Tap-only tabs: see the class doc — the page itself must stay swipeable.
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _ArtworksTab(query: _q), // full-bleed adaptive grid
            CenteredContent(
                child: _UsersTab(
              query: _q,
              sort: _userSort,
              onSortChanged: (s) => setState(() => _userSort = s),
            )),
            CenteredContent(
                child: _HashtagsTab(
              query: _q,
              sort: _tagSort,
              onSortChanged: (s) => setState(() => _tagSort = s),
            )),
          ],
        ),
      ),
    ]);
  }
}

/// One row of sort ChoiceChips shared by the Users and Hashtags tabs.
class _SortChips extends StatelessWidget {
  final List<(String, String)> options; // (value, label)
  final String value;
  final ValueChanged<String> onChanged;
  const _SortChips({required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(spacing: 6, children: [
          for (final (v, label) in options)
            ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              selected: value == v,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onChanged(v),
            ),
        ]),
      );
}

/// Shared list scaffolding: initial spinner / error / empty / infinite scroll.
Widget _pagedBody<T>({
  required PagedState<T> s,
  required PagedNotifier<T> n,
  required ScrollController controller,
  required String emptyMessage,
  required Widget Function(BuildContext, T) row,
}) {
  if (s.error != null && s.items.isEmpty) {
    return ClubErrorRetry(message: s.error!, onRetry: n.refresh);
  }
  if (!s.initialized && s.loading) {
    return const Center(child: CircularProgressIndicator());
  }
  if (s.items.isEmpty) return ClubEmpty(message: emptyMessage);
  return RefreshIndicator(
    onRefresh: n.refresh,
    child: ListView.builder(
      controller: controller,
      itemCount: s.items.length + (s.atEnd ? 0 : 1),
      itemBuilder: (ctx, i) {
        if (i >= s.items.length) {
          return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        return row(ctx, s.items[i]);
      },
    ),
  );
}

class _ArtworksTab extends ConsumerStatefulWidget {
  final String query;
  const _ArtworksTab({required this.query});
  @override
  ConsumerState<_ArtworksTab> createState() => _ArtworksTabState();
}

class _ArtworksTabState extends ConsumerState<_ArtworksTab>
    with AutomaticKeepAliveClientMixin {
  final _sc = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 400 &&
          widget.query.isNotEmpty) {
        ref.read(_artworkSearchProvider(widget.query).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.query.isEmpty) {
      return const Center(
          child: Text('Type to search.', style: TextStyle(color: Colors.white38)));
    }
    final s = ref.watch(_artworkSearchProvider(widget.query));
    final n = ref.read(_artworkSearchProvider(widget.query).notifier);
    if (s.error != null && s.items.isEmpty) {
      return ClubErrorRetry(message: s.error!, onRetry: n.refresh);
    }
    if (!s.initialized && s.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.items.isEmpty) return const ClubEmpty(message: 'No artworks found.');
    final posts = s.items;
    return GridView.builder(
      controller: _sc,
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 132, mainAxisSpacing: 4, crossAxisSpacing: 4),
      itemCount: posts.length + (s.atEnd ? 0 : 1),
      // Keyed by post id so a new result set can't recycle a tile's
      // decoded artwork into a different post's slot (stale frames
      // while the new artwork loads).
      findChildIndexCallback: (key) {
        if (key is! ValueKey<int>) return null;
        final ix = posts.indexWhere((p) => p.id == key.value);
        return ix >= 0 ? ix : null;
      },
      itemBuilder: (ctx, i) {
        if (i >= posts.length) {
          return const Center(
              child: SizedBox(
                  height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)));
        }
        return GestureDetector(
          key: ValueKey<int>(posts[i].id),
          onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute(
                  builder: (_) => ArtworkDetailPage(
                        sqid: posts[i].sqid,
                        // Paged source: swiping through results in the detail
                        // pager keeps pulling further pages.
                        feed: pagedArtworkSource(
                          _artworkSearchProvider(widget.query),
                          _artworkSearchProvider(widget.query).notifier,
                          name: 'Search',
                        ),
                      ))),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              // Cells are square (default aspect ratio); the backdrop shows
              // through as letterbox/pillarbox bars for non-square art.
              child: ColoredBox(
                  color: kArtworkBackdrop,
                  child: PixelArtImage(
                      url: posts[i].artUrl,
                      frameCount: posts[i].frameCount,
                      width: posts[i].width,
                      height: posts[i].height))),
        );
      },
    );
  }
}

class _UsersTab extends ConsumerStatefulWidget {
  final String query;
  final String sort;
  final ValueChanged<String> onSortChanged;
  const _UsersTab({required this.query, required this.sort, required this.onSortChanged});
  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> with AutomaticKeepAliveClientMixin {
  final _sc = ScrollController();

  @override
  bool get wantKeepAlive => true;

  ({String q, String sort}) get _key => (q: widget.query, sort: widget.sort);

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 400) {
        ref.read(_userSearchProvider(_key).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = ref.watch(_userSearchProvider(_key));
    final n = ref.read(_userSearchProvider(_key).notifier);
    return Column(children: [
      _SortChips(
        options: const [
          ('alphabetical', 'A–Z'),
          ('recent', 'Newest'),
          ('reputation', 'Reputation'),
        ],
        value: widget.sort,
        onChanged: widget.onSortChanged,
      ),
      Expanded(
        child: _pagedBody<PostOwner>(
          s: s,
          n: n,
          controller: _sc,
          emptyMessage: 'No users found.',
          row: (ctx, u) => ListTile(
            leading: HandleAvatar(url: u.avatarUrl, handle: u.handle, radius: 18),
            title: Text(u.handle),
            subtitle: (u.tagline != null && u.tagline!.isNotEmpty) ? Text(u.tagline!) : null,
            trailing: Text('rep ${u.reputation}',
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
            onTap: () => Navigator.push(
                ctx, MaterialPageRoute(builder: (_) => ProfilePage(sqid: u.sqid))),
          ),
        ),
      ),
    ]);
  }
}

class _HashtagsTab extends ConsumerStatefulWidget {
  final String query;
  final String sort;
  final ValueChanged<String> onSortChanged;
  const _HashtagsTab({required this.query, required this.sort, required this.onSortChanged});
  @override
  ConsumerState<_HashtagsTab> createState() => _HashtagsTabState();
}

class _HashtagsTabState extends ConsumerState<_HashtagsTab>
    with AutomaticKeepAliveClientMixin {
  final _sc = ScrollController();

  @override
  bool get wantKeepAlive => true;

  ({String q, String sort}) get _key => (q: widget.query, sort: widget.sort);

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 400) {
        ref.read(_hashtagSearchProvider(_key).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = ref.watch(_hashtagSearchProvider(_key));
    final n = ref.read(_hashtagSearchProvider(_key).notifier);
    return Column(children: [
      _SortChips(
        options: const [
          ('popularity', 'Popular'),
          ('alphabetical', 'A–Z'),
          ('recent', 'Recent'),
        ],
        value: widget.sort,
        onChanged: widget.onSortChanged,
      ),
      Expanded(
        child: _pagedBody<HashtagStat>(
          s: s,
          n: n,
          controller: _sc,
          emptyMessage: 'No hashtags found.',
          row: (ctx, t) => ListTile(
            leading: const Icon(Icons.tag),
            title: Text('#${t.tag}'),
            subtitle: Text('${t.artworkCount} artworks · ${t.reactionCount} reactions'),
            onTap: () => Navigator.push(
                ctx, MaterialPageRoute(builder: (_) => HashtagFeedPage(tag: t.tag))),
          ),
        ),
      ),
    ]);
  }
}
