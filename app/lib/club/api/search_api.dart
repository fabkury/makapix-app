import '../models/hashtag.dart';
import '../models/page.dart';
import '../models/post.dart';
import 'club_api_client.dart';

/// Pull the bare tag list out of a `/hashtags/top` response defensively. The
/// server sends `{ "hashtags": ["cat", ...], "cached_until": ... }`; anything
/// else (missing key, wrong shape) yields an empty list. Pure — unit-tested.
List<String> parseTopHashtags(Object? data) {
  final list = data is Map ? (data['hashtags'] as List?) : (data is List ? data : null);
  return (list ?? const []).map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
}

/// Search across artworks / users / hashtags. The unified `/search` is
/// auth+trigram and its item shape is parsed defensively (verify on device).
class SearchApi {
  final ClubApiClient client;
  SearchApi(this.client);

  Future<List<PostOwner>> browseUsers(String q, {String sort = 'alphabetical'}) => client.guard(() async {
        final resp = await client.dio.get('/user/browse', queryParameters: {
          if (q.isNotEmpty) 'q': q,
          'sort': sort,
          'limit': 40,
        });
        return Page<PostOwner>.fromJson((resp.data as Map).cast<String, dynamic>(), PostOwner.fromJson)
            .items;
      });

  Future<List<HashtagStat>> hashtagStats(String q) => client.guard(() async {
        final resp = await client.dio.get('/hashtags/stats', queryParameters: {
          if (q.isNotEmpty) 'q': q,
          'limit': 20,
        });
        final data = resp.data;
        final list = data is Map ? (data['items'] as List?) : (data is List ? data : null);
        return (list ?? const [])
            .map((e) => HashtagStat.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  /// Top trending hashtags for the header bar. Server-driven "rotation": the
  /// endpoint returns a random sample of the top-trending tags on a shared 2h
  /// cache, so the set changes on re-fetch, not on any client timer. Lives under
  /// the unversioned `/api` root (not `/api/v1`), so it uses [dioRoot].
  Future<List<String>> topHashtags() => client.guard(() async {
        final resp = await client.dioRoot.get('/hashtags/top');
        return parseTopHashtags(resp.data);
      });

  /// Artwork text search via `/search`. Pulls post-shaped entries out of the
  /// (possibly tagged-union) item list defensively.
  Future<List<Post>> searchPosts(String q) {
    if (q.isEmpty) return Future.value(const []);
    return client.guard(() async {
      final resp = await client.dio.get('/search', queryParameters: {
        'q': q,
        'types': ['posts'],
        'limit': 40,
      });
      final data = (resp.data as Map).cast<String, dynamic>();
      final items = (data['items'] as List?) ?? (data['posts'] as List?) ?? const [];
      final posts = <Post>[];
      for (final e in items) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final candidate = (m['post'] as Map?)?.cast<String, dynamic>() ?? m;
        if (candidate['public_sqid'] != null && candidate['art_url'] != null) {
          posts.add(Post.fromJson(candidate));
        }
      }
      return posts;
    });
  }
}
