import 'package:dio/dio.dart';

import '../models/comment.dart';
import '../models/page.dart';
import '../models/post.dart';
import '../models/reactions.dart';
import 'club_api_client.dart';

/// Single-post reads + engagement (view, reactions, comments).
class PostApi {
  final ClubApiClient client;
  PostApi(this.client);

  Future<Post> getBySqid(String sqid) => client.guard(() async {
        final resp = await client.dio.get('/p/${Uri.encodeComponent(sqid)}');
        return Post.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// Fire-and-forget view registration (server-throttled to 1/3 s). Never surfaces — so it keeps
  /// its own swallowing catch rather than going through `guard` (which would rethrow).
  Future<void> registerView(int postId, {String? channel, String? channelContext}) async {
    try {
      final body = <String, dynamic>{};
      if (channel != null) body['channel'] = channel;
      if (channelContext != null) body['channel_context'] = channelContext;
      await client.dio.post('/post/$postId/view', data: body.isEmpty ? null : body);
    } on DioException catch (_) {
      // ignore (overlay views, rate limits, network)
    }
  }

  Future<ReactionTotals> reactions(int postId) => client.guard(() async {
        final resp = await client.dio.get('/post/$postId/reactions');
        return ReactionTotals.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  Future<void> addReaction(int postId, String emoji) => client
      .guard(() => client.dio.put('/post/$postId/reactions/${Uri.encodeComponent(emoji)}'));

  Future<void> removeReaction(int postId, String emoji) => client
      .guard(() => client.dio.delete('/post/$postId/reactions/${Uri.encodeComponent(emoji)}'));

  /// Comments as a depth-≤2 tree (fetched flat, assembled client-side).
  Future<List<Comment>> comments(int postId) => client.guard(() async {
        final resp = await client.dio
            .get('/post/$postId/comments', queryParameters: {'view': 'flat', 'limit': 200});
        final page = Page<Comment>.fromJson(
            (resp.data as Map).cast<String, dynamic>(), Comment.fromJson);
        return Comment.assembleTree(page.items);
      });

  Future<void> addComment(int postId, String body, {String? parentId}) => client.guard(() => client
      .dio.post('/post/$postId/comments', data: {'body': body, 'parent_id': ?parentId}));

  Future<void> editComment(String commentId, String body) => client.guard(
      () => client.dio.patch('/post/comments/${Uri.encodeComponent(commentId)}', data: {'body': body}));

  Future<void> deleteComment(String commentId) =>
      client.guard(() => client.dio.delete('/post/comments/${Uri.encodeComponent(commentId)}'));

  Future<void> likeComment(String commentId) =>
      client.guard(() => client.dio.put('/post/comments/${Uri.encodeComponent(commentId)}/like'));

  Future<void> unlikeComment(String commentId) =>
      client.guard(() => client.dio.delete('/post/comments/${Uri.encodeComponent(commentId)}/like'));
}
