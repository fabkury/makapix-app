import '../models/artist_stats.dart';
import 'club_api_client.dart';

/// Analytics (`SPEC-CLUB.md` §19). Currently: the artist dashboard aggregate.
/// (Per-post `GET /post/{id}/stats` drill-in is deferred.)
class StatsApi {
  final ClubApiClient client;
  StatsApi(this.client);

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
