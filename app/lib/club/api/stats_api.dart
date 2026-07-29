import '../models/artist_stats.dart';
import '../models/post_stats.dart';
import 'club_api_client.dart';

/// Analytics (`SPEC-CLUB.md` §19): the artist dashboard aggregate and the
/// per-post drill-in.
class StatsApi {
  final ClubApiClient client;
  StatsApi(this.client);

  /// `GET /post/{id}/stats` — post owner or moderator only (403 otherwise).
  /// Both the all-viewers and authenticated-only variants arrive in one
  /// payload; [refresh] forces the server to recompute its cached stats.
  Future<PostStats> postStats(int postId, {bool refresh = false}) => client.guard(() async {
        final resp = await client.dio.get('/post/$postId/stats',
            queryParameters: refresh ? {'refresh': true} : null);
        return PostStats.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// `GET /user/{userKey}/artist-dashboard` — owner/moderator only. `userKey`
  /// accepts the public_sqid or the UUID.
  Future<ArtistDashboard> artistDashboard(String userKey, {int page = 1, int pageSize = 20}) =>
      client.guard(() async {
        final resp = await client.dio.get(
          '/user/${Uri.encodeComponent(userKey)}/artist-dashboard',
          queryParameters: {'page': page, 'page_size': pageSize},
        );
        return ArtistDashboard.fromJson((resp.data as Map).cast<String, dynamic>());
      });
}
