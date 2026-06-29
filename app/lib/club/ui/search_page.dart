import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hashtag.dart';
import '../models/post.dart';
import '../state/api_providers.dart';
import 'artwork_detail_page.dart';
import 'hashtag_feed_page.dart';
import 'profile_page.dart';
import 'widgets/common.dart';

// autoDispose: these are keyed by the raw query string — without it, every query ever typed would
// be cached for the app's lifetime. [audit F-19]
final _artworkSearchProvider =
    FutureProvider.autoDispose.family<List<Post>, String>((ref, q) => ref.read(searchApiProvider).searchPosts(q));
final _userSearchProvider =
    FutureProvider.autoDispose.family<List<PostOwner>, String>((ref, q) => ref.read(searchApiProvider).browseUsers(q));
final _hashtagSearchProvider =
    FutureProvider.autoDispose.family<List<HashtagStat>, String>((ref, q) => ref.read(searchApiProvider).hashtagStats(q));

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  final _field = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _tab.dispose();
    _field.dispose();
    super.dispose();
  }

  void _run() => setState(() => _q = _field.text.trim());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _field,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            hintText: 'Search Makapix Club…',
            border: InputBorder.none,
            suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _run),
          ),
        ),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Artworks'), Tab(text: 'Users'), Tab(text: 'Hashtags')],
        ),
      ),
      body: _q.isEmpty
          ? const Center(child: Text('Type to search.', style: TextStyle(color: Colors.white38)))
          : TabBarView(controller: _tab, children: [
              _ArtworksTab(query: _q),
              _UsersTab(query: _q),
              _HashtagsTab(query: _q),
            ]),
    );
  }
}

class _ArtworksTab extends ConsumerWidget {
  final String query;
  const _ArtworksTab({required this.query});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_artworkSearchProvider(query)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const ClubEmpty(message: 'Search failed.'),
          data: (posts) => posts.isEmpty
              ? const ClubEmpty(message: 'No artworks found.')
              : GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 132, mainAxisSpacing: 4, crossAxisSpacing: 4),
                  itemCount: posts.length,
                  itemBuilder: (ctx, i) => GestureDetector(
                    onTap: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(
                            builder: (_) => ArtworkDetailPage(
                                  sqid: posts[i].sqid,
                                  feed: ArtworkFeedSource.fixed(posts),
                                ))),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: PixelArtImage(url: posts[i].artUrl)),
                  ),
                ),
        );
  }
}

class _UsersTab extends ConsumerWidget {
  final String query;
  const _UsersTab({required this.query});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_userSearchProvider(query)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const ClubEmpty(message: 'Search failed.'),
          data: (users) => users.isEmpty
              ? const ClubEmpty(message: 'No users found.')
              : ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (ctx, i) {
                    final u = users[i];
                    return ListTile(
                      leading: HandleAvatar(url: u.avatarUrl, handle: u.handle, radius: 18),
                      title: Text(u.handle),
                      subtitle: (u.tagline != null && u.tagline!.isNotEmpty) ? Text(u.tagline!) : null,
                      trailing: Text('rep ${u.reputation}', style: const TextStyle(fontSize: 11, color: Colors.white38)),
                      onTap: () =>
                          Navigator.push(ctx, MaterialPageRoute(builder: (_) => ProfilePage(sqid: u.sqid))),
                    );
                  },
                ),
        );
  }
}

class _HashtagsTab extends ConsumerWidget {
  final String query;
  const _HashtagsTab({required this.query});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_hashtagSearchProvider(query)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const ClubEmpty(message: 'Search failed.'),
          data: (tags) => tags.isEmpty
              ? const ClubEmpty(message: 'No hashtags found.')
              : ListView.builder(
                  itemCount: tags.length,
                  itemBuilder: (ctx, i) {
                    final t = tags[i];
                    return ListTile(
                      leading: const Icon(Icons.tag),
                      title: Text('#${t.tag}'),
                      subtitle: Text('${t.artworkCount} artworks · ${t.reactionCount} reactions'),
                      onTap: () => Navigator.push(
                          ctx, MaterialPageRoute(builder: (_) => HashtagFeedPage(tag: t.tag))),
                    );
                  },
                ),
        );
  }
}
