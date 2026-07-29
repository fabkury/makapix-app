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

  /// User directory (`GET /user/browse`), cursor-paged.
  /// [sort]: `alphabetical` · `recent` · `reputation` (server-validated set).
  Future<Page<PostOwner>> browseUsers(String q,
          {String sort = 'alphabetical', String? cursor}) =>
      client.guard(() async {
        final resp = await client.dio.get('/user/browse', queryParameters: {
          if (q.isNotEmpty) 'q': q,
          'sort': sort,
          'limit': 40,
          'cursor': ?cursor,
        });
        return Page<PostOwner>.fromJson(
            (resp.data as Map).cast<String, dynamic>(), PostOwner.fromJson);
      });

  /// Hashtag directory with stats (`GET /hashtags/stats`), cursor-paged.
  /// [sort]: `popularity` · `alphabetical` · `recent` (server-validated set).
  Future<Page<HashtagStat>> hashtagStats(String q,
          {String sort = 'popularity', String? cursor}) =>
      client.guard(() async {
        final resp = await client.dio.get('/hashtags/stats', queryParameters: {
          if (q.isNotEmpty) 'q': q,
          'sort': sort,
          'limit': 30,
          'cursor': ?cursor,
        });
        final data = resp.data;
        if (data is Map) {
          return Page<HashtagStat>.fromJson(
              data.cast<String, dynamic>(), HashtagStat.fromJson);
        }
        // Defensive: a bare list is a single page.
        final list = (data is List ? data : const [])
            .map((e) => HashtagStat.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        return Page(items: list);
      });

  /// Top trending hashtags for the header bar. Server-driven "rotation": the
  /// endpoint returns a random sample of the top-trending tags on a shared 2h
  /// cache, so the set changes on re-fetch, not on any client timer. Lives under
  /// the unversioned `/api` root (not `/api/v1`), so it uses [dioRoot].
  Future<List<String>> topHashtags() => client.guard(() async {
        final resp = await client.dioRoot.get('/hashtags/top');
        return parseTopHashtags(resp.data);
      });

  /// Artwork text search via `/search`, cursor-paged. Pulls post-shaped
  /// entries out of the (possibly tagged-union) item list defensively.
  Future<Page<Post>> searchPosts(String q, {String? cursor}) {
    if (q.isEmpty) return Future.value(const Page(items: []));
    return client.guard(() async {
      final resp = await client.dio.get('/search', queryParameters: {
        'q': q,
        'types': ['posts'],
        'limit': 40,
        'cursor': ?cursor,
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
      return Page(items: posts, nextCursor: data['next_cursor'] as String?);
    });
  }
}
