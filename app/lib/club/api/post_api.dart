import 'package:dio/dio.dart';

import '../models/club_error.dart';
import '../models/comment.dart';
import '../models/page.dart';
import '../models/post.dart';
import '../models/reactions.dart';
import 'club_api_client.dart';

/// Single-post reads + engagement (view, reactions, comments).
class PostApi {
  final ClubApiClient client;
  PostApi(this.client);

  Future<Post> getBySqid(String sqid) async {
    try {
      final resp = await client.dio.get('/p/${Uri.encodeComponent(sqid)}');
      return Post.fromJson((resp.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  /// Fire-and-forget view registration (server-throttled to 1/3 s). Never surfaces.
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

  Future<ReactionTotals> reactions(int postId) async {
    try {
      final resp = await client.dio.get('/post/$postId/reactions');
      return ReactionTotals.fromJson((resp.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  Future<void> addReaction(int postId, String emoji) =>
      _ed(() => client.dio.put('/post/$postId/reactions/${Uri.encodeComponent(emoji)}'));

  Future<void> removeReaction(int postId, String emoji) =>
      _ed(() => client.dio.delete('/post/$postId/reactions/${Uri.encodeComponent(emoji)}'));

  /// Comments as a depth-≤2 tree (fetched flat, assembled client-side).
  Future<List<Comment>> comments(int postId) async {
    try {
      final resp = await client.dio
          .get('/post/$postId/comments', queryParameters: {'view': 'flat', 'limit': 200});
      final page = Page<Comment>.fromJson(
          (resp.data as Map).cast<String, dynamic>(), Comment.fromJson);
      return Comment.assembleTree(page.items);
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  Future<void> addComment(int postId, String body, {String? parentId}) => _ed(() => client.dio
      .post('/post/$postId/comments', data: {'body': body, 'parent_id': ?parentId}));

  Future<void> editComment(String commentId, String body) =>
      _ed(() => client.dio.patch('/post/comments/${Uri.encodeComponent(commentId)}', data: {'body': body}));

  Future<void> deleteComment(String commentId) =>
      _ed(() => client.dio.delete('/post/comments/${Uri.encodeComponent(commentId)}'));

  Future<void> likeComment(String commentId) =>
      _ed(() => client.dio.put('/post/comments/${Uri.encodeComponent(commentId)}/like'));

  Future<void> unlikeComment(String commentId) =>
      _ed(() => client.dio.delete('/post/comments/${Uri.encodeComponent(commentId)}/like'));

  /// Run a mutating call, mapping dio errors to [ClubError].
  Future<void> _ed(Future<Response> Function() call) async {
    try {
      await call();
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }
}
