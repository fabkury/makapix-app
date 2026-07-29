import 'dart:typed_data';

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

  /// Artwork blobs can be MBs; the default 30 s I/O timeouts are sized for JSON.
  static const Duration _blobTimeout = Duration(minutes: 5);

  // ---- File downloads (`/d/{sqid}*`, same router as the .mkpx download) ----

  /// The stored native-format file, byte-exact.
  Future<Uint8List> downloadNative(String sqid) =>
      _downloadBytes('/d/${Uri.encodeComponent(sqid)}');

  /// The server-generated nearest-neighbor upscaled WebP (404 until generated).
  Future<Uint8List> downloadUpscaled(String sqid) =>
      _downloadBytes('/d/${Uri.encodeComponent(sqid)}/upscaled');

  /// A pre-generated alternative-format variant (one of `post.files`).
  Future<Uint8List> downloadFormat(String sqid, String format) =>
      _downloadBytes('/d/${Uri.encodeComponent(sqid)}.${Uri.encodeComponent(format)}');

  Future<Uint8List> _downloadBytes(String path) => client.guard(() async {
        final resp = await client.dio.get<List<int>>(path,
            options: Options(responseType: ResponseType.bytes, receiveTimeout: _blobTimeout));
        return Uint8List.fromList(resp.data ?? const []);
      });

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

  /// Owner metadata edit (`PATCH /post/{id}`). [hashtags] is the artist-controlled
  /// list only — the server normalizes it and re-merges mod-owned tags (D10).
  /// Returns the updated post.
  Future<Post> update(int postId,
          {required String title,
          required String description,
          required List<String> hashtags}) =>
      client.guard(() async {
        final resp = await client.dio.patch('/post/$postId', data: {
          'title': title,
          'description': description,
          'hashtags': hashtags,
        });
        return Post.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// Owner visibility toggle (`POST`/`DELETE /post/{id}/hide`).
  Future<void> setHidden(int postId, bool hidden) => client.guard(() => hidden
      ? client.dio.post('/post/$postId/hide')
      : client.dio.delete('/post/$postId/hide'));

  /// Owner soft delete (`DELETE /post/{id}`) — the server keeps a 7-day grace
  /// window before permanent removal (same semantics as the bulk PMD delete).
  Future<void> deletePost(int postId) =>
      client.guard(() => client.dio.delete('/post/$postId'));

  Future<ReactionTotals> reactions(int postId) => client.guard(() async {
        final resp = await client.dio.get('/post/$postId/reactions');
        return ReactionTotals.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  Future<void> addReaction(int postId, String emoji) => client
      .guard(() => client.dio.put('/post/$postId/reactions/${Uri.encodeComponent(emoji)}'));

  Future<void> removeReaction(int postId, String emoji) => client
      .guard(() => client.dio.delete('/post/$postId/reactions/${Uri.encodeComponent(emoji)}'));

  /// Authenticated reactors for a post (newest first, server-capped at 200, no pagination).
  /// Shape is `{items: [...], total}` — not the cursor-paged `Page<T>` envelope.
  Future<List<ReactionUser>> reactionUsers(int postId) => client.guard(() async {
        final resp = await client.dio.get('/post/$postId/reaction-users');
        final items = ((resp.data as Map)['items'] as List?) ?? const [];
        return items
            .map((e) => ReactionUser.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

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
