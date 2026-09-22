import '../models/mention_candidate.dart';
import 'club_api_client.dart';

/// Mention autocomplete (`GET /user/mention-candidates`, server message
/// 0004/0002 §4).
///
/// The endpoint applies the same mentionability function as the write path, so
/// anyone it offers survives the write — the composer never has to second-guess
/// a row it was given.
class MentionsApi {
  final ClubApiClient client;
  MentionsApi(this.client);

  /// Candidates for the `@` composer.
  ///
  /// [q] is a prefix on the handle skeleton; empty returns only the contextual
  /// tiers (`owner`, `thread`, `following`, `follower`), which is what the bare
  /// `@` keystroke shows. [postId] is the **integer** post id (not the sqid);
  /// the server ignores it silently when the caller cannot access that post, and
  /// without it the `owner` and `thread` tiers cannot apply — the publish page
  /// has no post yet, so it simply passes null.
  ///
  /// Server limit: 120 requests / 60 s per user, 429 past it. The composer
  /// debounces and cancels in flight, so a fast typist costs about one request
  /// per word.
  Future<List<MentionCandidate>> candidates({
    String q = '',
    int? postId,
    int limit = 8,
  }) =>
      client.guard(() async {
        final resp = await client.dio.get(
          '/user/mention-candidates',
          queryParameters: {
            if (q.isNotEmpty) 'q': q,
            if (postId != null && postId > 0) 'post_id': postId,
            'limit': limit.clamp(1, 20),
          },
        );
        final data = (resp.data as Map?)?.cast<String, dynamic>() ?? const {};
        final items = data['items'];
        if (items is! List) return const <MentionCandidate>[];
        return items
            .whereType<Map>()
            .map((e) => MentionCandidate.fromJson(e.cast<String, dynamic>()))
            .where((c) => c.sqid.isNotEmpty && c.handle.isNotEmpty)
            .toList();
      });
}
