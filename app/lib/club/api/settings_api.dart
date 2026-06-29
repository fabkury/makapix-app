import 'club_api_client.dart';

/// User settings (`SPEC-CLUB.md` §21). Currently: the monitored-hashtag content
/// filter (`approved_hashtags`).
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
}
