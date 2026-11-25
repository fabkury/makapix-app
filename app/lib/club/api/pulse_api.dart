import '../models/page.dart';
import '../models/pulse_card.dart';
import 'club_api_client.dart';

/// The Pulse timeline: `GET /pulse` → a cursor-paginated page of activity cards
/// (messages/0008-pulse/0002). Signed-in only; a server that predates it answers 404.
class PulseApi {
  final ClubApiClient client;
  PulseApi(this.client);

  /// [kinds] narrows the timeline; null or empty asks for every kind. Cards this build cannot
  /// show are dropped, so a page may hold fewer than [limit] cards and still have a cursor.
  Future<Page<PulseCard>> cards({String? cursor, int limit = 20, Set<PulseKind>? kinds}) =>
      client.guard(() async {
        final resp = await client.dio.get('/pulse', queryParameters: {
          'cursor': ?cursor,
          'limit': limit,
          if (kinds != null && kinds.isNotEmpty) 'kinds': kinds.map((k) => k.wire).join(','),
        });
        final body = (resp.data as Map).cast<String, dynamic>();
        final raw = (body['items'] as List?) ?? const [];
        return Page<PulseCard>(
          items: [
            for (final e in raw)
              if (e is Map) ?PulseCard.fromJson(e.cast<String, dynamic>()),
          ],
          nextCursor: body['next_cursor'] as String?,
        );
      });
}
