import '../models/post.dart';
import 'club_api_client.dart';

/// Moderator-role endpoints (`roles` ∋ moderator|owner — site roles, not post
/// authorship). First occupant of this file; future moderator actions
/// (hide/promote) belong here too. All UI reaching these must be gated on the
/// `max_mod_hashtags_per_post` config key (`ClubServerConfig.modHashtagsEnabled`)
/// — against a server without the feature the endpoint 404s indistinguishably
/// from "post not found".
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
}
