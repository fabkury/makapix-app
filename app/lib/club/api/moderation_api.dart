import '../models/page.dart';
import '../models/post.dart';
import '../models/umd.dart';
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

  // ---- Comment actions ----
  //
  // Mod *deletion* of a comment needs no method here: the regular
  // `DELETE /post/comments/{id}` (PostApi.deleteComment) detects the moderator
  // case server-side and writes the "[deleted by moderator]" tombstone.

  /// `POST /post/comments/{id}/undelete` — restore a deleted comment
  /// (re-instates the preserved original body when it still exists).
  Future<void> undeleteComment(String commentId) => client.guard(() =>
      client.dio.post('/post/comments/${Uri.encodeComponent(commentId)}/undelete'));

  /// `POST`/`DELETE /post/comments/{id}/hide` — hide/unhide without deleting.
  /// Hidden comments stay visible to moderators only.
  Future<void> setCommentHidden(String commentId, bool hidden) => client.guard(() => hidden
      ? client.dio.post('/post/comments/${Uri.encodeComponent(commentId)}/hide')
      : client.dio.delete('/post/comments/${Uri.encodeComponent(commentId)}/hide'));

  /// `POST /post/comments/{id}/purge-original` — permanently discard a deleted
  /// comment's preserved pre-deletion text (for PII etc.). Irreversible; the
  /// server 400s when the comment is not deleted. Callers put a two-step
  /// confirmation in front.
  Future<void> purgeCommentOriginal(String commentId) => client.guard(() =>
      client.dio.post('/post/comments/${Uri.encodeComponent(commentId)}/purge-original'));

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

  // ---- User management (UMD, the website's /u/{sqid}/manage) ----
  //
  // The UMD router is mounted ONLY at the unversioned root (like PMD), so
  // these go through [ClubApiClient.dioRoot]. The server 403s "Cannot manage
  // the site owner" for the owner as target — surface that message as-is.

  String _umd(String sqid) => '/admin/user/${Uri.encodeComponent(sqid)}';

  /// `GET /admin/user/{sqid}/manage` — the aggregate UMD payload.
  Future<UmdUserData> getUserManagement(String sqid) => client.guard(() async {
        final resp = await client.dioRoot.get('${_umd(sqid)}/manage');
        return UmdUserData.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// `POST`/`DELETE /admin/user/{sqid}/trust` — grant/revoke
  /// `auto_public_approval` (trusted users skip the pending-approval queue).
  Future<void> setUserTrusted(String sqid, bool trusted) => client.guard(() => trusted
      ? client.dioRoot.post('${_umd(sqid)}/trust')
      : client.dioRoot.delete('${_umd(sqid)}/trust'));

  /// `POST`/`DELETE /admin/user/{sqid}/hide` — hide/unhide the user profile.
  Future<void> setUserHidden(String sqid, bool hidden) => client.guard(() => hidden
      ? client.dioRoot.post('${_umd(sqid)}/hide')
      : client.dioRoot.delete('${_umd(sqid)}/hide'));

  /// `POST /admin/user/{sqid}/ban?duration_days=N` — block authentication
  /// without deleting any data. Null [durationDays] = permanent (the server
  /// stores the year-9999 sentinel); otherwise 1–365 days.
  Future<void> banUser(String sqid, {int? durationDays}) =>
      client.guard(() => client.dioRoot.post('${_umd(sqid)}/ban', queryParameters: {
            'duration_days': ?durationDays,
          }));

  /// `DELETE /admin/user/{sqid}/ban` — lift the ban immediately.
  Future<void> unbanUser(String sqid) =>
      client.guard(() => client.dioRoot.delete('${_umd(sqid)}/ban'));

  /// `POST /admin/user/{sqid}/reputation` — apply a signed [delta]
  /// (±1000 max) with a required [reason] (≥8 chars). Returns the new total.
  /// The server writes a history row, notifies the user, and audit-logs.
  Future<int> adjustUserReputation(String sqid,
          {required int delta, required String reason}) =>
      client.guard(() async {
        final resp = await client.dioRoot
            .post('${_umd(sqid)}/reputation', data: {'delta': delta, 'reason': reason});
        return ((resp.data as Map?)?['new_total'] as num?)?.toInt() ?? 0;
      });

  /// `GET /admin/user/{sqid}/email` — reveal the user's email. The server
  /// audit-logs the reveal BEFORE returning it; the UI warns first.
  Future<String> revealUserEmail(String sqid) => client.guard(() async {
        final resp = await client.dioRoot.get('${_umd(sqid)}/email');
        return ((resp.data as Map?)?['email'] ?? '').toString();
      });
}
