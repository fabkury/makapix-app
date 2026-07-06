import '../models/blocked_user.dart';
import '../models/page.dart';
import '../models/report.dart';
import 'club_api_client.dart';

/// User-facing UGC-safety endpoints — content reporting + user blocking
/// (contract ugc-safety v1). Deliberately distinct from the moderator-role
/// [ModerationApi]: these are actions any user (and, for reporting, any
/// logged-out visitor) can take.
///
/// Reporting works signed-out with no extra plumbing — the shared client
/// attaches the bearer only when a session exists.
class SafetyApi {
  final ClubApiClient client;
  SafetyApi(this.client);

  /// `POST /report` — file a report (auth optional). Returns the created
  /// [Report] (201). Errors surface as [ClubError]; branch on `code`:
  /// `not_found` (404), `validation_error` (422), `rate_limited` (429).
  /// [notes] is trimmed-or-null by the caller; a null omits the key entirely.
  Future<Report> report(ReportTarget t, {required String reasonCode, String? notes}) =>
      client.guard(() async {
        final resp = await client.dio.post('/report', data: {
          'target_type': t.type,
          'target_id': t.id,
          'reason_code': reasonCode,
          'notes': ?notes,
        });
        return Report.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// `POST /user/u/{sqid}/block` — block a user (204, idempotent). Errors:
  /// `bad_request` (400 self-block), `not_found` (404),
  /// `block_cap_reached` (409), `unauthorized` (401).
  Future<void> block(String sqid) => client.guard(() async {
        await client.dio.post('/user/u/${Uri.encodeComponent(sqid)}/block');
      });

  /// `DELETE /user/u/{sqid}/block` — unblock (204, idempotent).
  Future<void> unblock(String sqid) => client.guard(() async {
        await client.dio.delete('/user/u/${Uri.encodeComponent(sqid)}/block');
      });

  /// `GET /me/blocks` — the caller's blocked users (cursor-paginated).
  Future<Page<BlockedUser>> blocks({String? cursor}) => client.guard(() async {
        final resp = await client.dio.get('/me/blocks', queryParameters: {'cursor': ?cursor});
        return Page<BlockedUser>.fromJson(
            (resp.data as Map).cast<String, dynamic>(), BlockedUser.fromJson);
      });
}
