import '../models/page.dart';
import '../models/post.dart';
import 'club_api_client.dart';

/// Moderator-role endpoints (`roles` ∋ moderator|owner — site roles, not post
/// authorship). UI gating: everything here requires `isModeratorProvider`;
/// [setModHashtags] additionally needs the `max_mod_hashtags_per_post` config
/// key (`ClubServerConfig.modHashtagsEnabled`) — against a server without that
/// feature the endpoint 404s indistinguishably from "post not found".
class ModerationApi {
  final ClubApiClient client;
  ModerationApi(this.client);

  /// `PUT /post/{id}/mod-hashtags` — **full replace** of the post's moderator
  /// hashtag set (contract v1). The server normalizes (trim, strip one `#`,
  /// lowercase, dedupe) and returns the full updated Post — the source of
  /// truth for both `hashtags` and `mod_hashtags`; never render what was sent.
  /// Errors surface as [ClubError]; branch on `code`:
  /// `forbidden` (not a moderator), `not_found` (missing / playlist /
  /// soft-deleted post), `validation_error` (>cap after normalization or a
  /// tag >64 chars).
  Future<Post> setModHashtags(int postId, List<String> hashtags, {String? note}) =>
      client.guard(() async {
        final resp = await client.dio.put('/post/$postId/mod-hashtags', data: {
          'hashtags': hashtags,
          'note': ?note,
        });
        return Post.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  // ---- Post actions (the website's `p/{sqid}` moderator block) ----

  /// `POST`/`DELETE /post/{id}/hide` with `{by: "mod"}` — sets/clears
  /// `hidden_by_mod` (the take-down the owner cannot self-clear). The DELETE
  /// carries no body; the server clears both hide flags for moderators.
  Future<void> setModHidden(int postId, bool hidden) => client.guard(() => hidden
      ? client.dio.post('/post/$postId/hide', data: {'by': 'mod'})
      : client.dio.delete('/post/$postId/hide'));

  /// `POST /post/{id}/promote` — feature the post in [category]
  /// (`frontpage` | `editor-pick` | `weekly-pack` | `daily's-best`).
  /// The server notifies the artist.
  Future<void> promotePost(int postId, {String category = 'frontpage'}) =>
      client.guard(() => client.dio.post('/post/$postId/promote', data: {'category': category}));

  /// `DELETE /post/{id}/promote` — remove the post from its promoted category.
  Future<void> demotePost(int postId) =>
      client.guard(() => client.dio.delete('/post/$postId/promote'));

  /// `POST`/`DELETE /post/{id}/approve-public` — grant/revoke visibility in
  /// Recent Artworks and search (the pending-approval gate).
  Future<void> setPublicVisibility(int postId, bool approved) => client.guard(() => approved
      ? client.dio.post('/post/$postId/approve-public')
      : client.dio.delete('/post/$postId/approve-public'));

  /// `DELETE /post/{id}/permanent` — irreversibly delete the post AND its
  /// vault artwork. Callers must put a two-step confirmation in front.
  Future<void> deletePostPermanently(int postId) =>
      client.guard(() => client.dio.delete('/post/$postId/permanent'));

  /// `GET /admin/pending-approval` — posts awaiting public-visibility approval
  /// (newest first, cursor-paged).
  Future<Page<Post>> pendingApproval({int limit = 50, String? cursor}) =>
      client.guard(() async {
        final resp = await client.dio.get('/admin/pending-approval', queryParameters: {
          'limit': limit,
          'cursor': ?cursor,
        });
        return Page<Post>.fromJson((resp.data as Map).cast<String, dynamic>(), Post.fromJson);
      });
}
