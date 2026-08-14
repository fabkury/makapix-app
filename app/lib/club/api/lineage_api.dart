import '../models/lineage.dart';
import '../models/page.dart';
import '../models/post.dart';
import 'club_api_client.dart';

/// Public remix lineage, read side (artwork-provenance PLAN §5.5). All three
/// endpoints are login-gated (L8); the Remix badge/counts on `Post` are the
/// public half.
class LineageApi {
  final ClubApiClient client;
  LineageApi(this.client);

  /// Ordered Parent slots of a post — up to 8, declaration order (base first),
  /// including anonymous `unavailable` and `deleted` placeholder slots.
  Future<List<LineageParentSlot>> parents(int postId) => client.guard(() async {
        final resp = await client.dio.get('/post/$postId/parents');
        final items = ((resp.data as Map?)?['items'] as List?) ?? const [];
        return items
            .map((e) => LineageParentSlot.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  /// Viewer-visible Remixes of a post, newest first. Invisible children are
  /// filtered out server-side (no placeholders).
  Future<Page<Post>> children(int postId, {String? cursor, int limit = 30}) =>
      client.guard(() async {
        final resp = await client.dio.get('/post/$postId/children',
            queryParameters: {'cursor': ?cursor, 'limit': limit});
        return Page<Post>.fromJson((resp.data as Map).cast<String, dynamic>(), Post.fromJson);
      });

  /// Aggregate "Remixes of my works", newest first; each item names which of
  /// the caller's works it remixes.
  Future<Page<RemixReceivedItem>> myRemixes({String? cursor, int limit = 30}) =>
      client.guard(() async {
        final resp = await client.dio
            .get('/me/remixes', queryParameters: {'cursor': ?cursor, 'limit': limit});
        return Page<RemixReceivedItem>.fromJson(
            (resp.data as Map).cast<String, dynamic>(), RemixReceivedItem.fromJson);
      });
}
