import '../models/club_user.dart';
import 'club_api_client.dart';

/// User settings (`SPEC-CLUB.md` §21): the monitored-hashtag content filter
/// (`approved_hashtags`), who may mention you (`mention_policy`), and whether you appear in
/// Displayed on lists (`show_in_impression_lists`).
class SettingsApi {
  final ClubApiClient client;
  SettingsApi(this.client);

  /// `PATCH /user/{userKey}` — set the approved (opted-in) monitored hashtags.
  /// The path resolves by `user_key` (UUID) only. The server returns 400 if any
  /// tag is outside the monitored set. Returns the server's resulting list.
  Future<List<String>> setApprovedHashtags(String userKey, List<String> tags) =>
      client.guard(() async {
        final resp = await client.dio.patch(
          '/user/${Uri.encodeComponent(userKey)}',
          data: {'approved_hashtags': tags},
        );
        final data = (resp.data as Map?)?.cast<String, dynamic>() ?? const {};
        return (data['approved_hashtags'] as List?)?.map((e) => e.toString()).toList() ?? tags;
      });

  /// `PATCH /user/{userKey}` — set who may mention this user. The server 422s
  /// on any value outside the three. Returns the server's resulting policy.
  Future<MentionPolicy> setMentionPolicy(String userKey, MentionPolicy policy) =>
      client.guard(() async {
        final resp = await client.dio.patch(
          '/user/${Uri.encodeComponent(userKey)}',
          data: {'mention_policy': policy.wire},
        );
        final data = (resp.data as Map?)?.cast<String, dynamic>() ?? const {};
        return data.containsKey('mention_policy')
            ? MentionPolicy.fromWire(data['mention_policy'])
            : policy;
      });

  /// `PATCH /user/{userKey}` — whether this user appears in artworks' Displayed on lists.
  /// One switch per account; off hides them from every list, for everyone. Returns the
  /// server's resulting value.
  Future<bool> setShowInImpressionLists(String userKey, bool show) => client.guard(() async {
        final resp = await client.dio.patch(
          '/user/${Uri.encodeComponent(userKey)}',
          data: {'show_in_impression_lists': show},
        );
        final data = (resp.data as Map?)?.cast<String, dynamic>() ?? const {};
        final applied = data['show_in_impression_lists'];
        return applied is bool ? applied : show;
      });
}
