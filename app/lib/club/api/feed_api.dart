import '../models/page.dart';
import '../models/post.dart';
import 'club_api_client.dart';

/// Read-only artwork feeds (all cursor-paginated → `Page<Post>`).
class FeedApi {
  final ClubApiClient client;
  FeedApi(this.client);

  Future<Page<Post>> _posts(String path, Map<String, dynamic> query) {
    query.removeWhere((_, v) => v == null);
    return client.guard(() async {
      final resp = await client.dio.get(path, queryParameters: query);
      return Page<Post>.fromJson((resp.data as Map).cast<String, dynamic>(), Post.fromJson);
    });
  }

  Future<Page<Post>> recent({String? cursor, int limit = 30}) =>
      _posts('/post/recent', {'cursor': cursor, 'limit': limit});

  Future<Page<Post>> promoted({String? cursor, int limit = 30}) =>
      _posts('/feed/promoted', {'cursor': cursor, 'limit': limit});

  Future<Page<Post>> following({String? cursor, int limit = 30}) =>
      _posts('/feed/following', {'cursor': cursor, 'limit': limit});

  Future<Page<Post>> hashtag(String tag, {String? cursor, int limit = 30}) =>
      _posts('/hashtags/${Uri.encodeComponent(tag)}/posts', {'cursor': cursor, 'limit': limit});

  /// A user's gallery — `GET /post?owner_id={user_key}` (note: owner_id is the UUID).
  Future<Page<Post>> byOwner(String ownerUserKey, {String? cursor, int limit = 30}) => _posts('/post', {
        'owner_id': ownerUserKey,
        'cursor': cursor,
        'limit': limit,
        'sort': 'created_at',
        'order': 'desc',
      });
}
