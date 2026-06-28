import '../models/hashtag.dart';
import '../models/page.dart';
import '../models/post.dart';
import 'club_api_client.dart';

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
