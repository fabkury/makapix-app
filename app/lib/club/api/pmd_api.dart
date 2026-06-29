import 'package:dio/dio.dart';

import '../models/page.dart';
import '../models/pmd.dart';
import 'club_api_client.dart';

/// Post Management Dashboard (`SPEC-CLUB.md` §20). These endpoints live at the
/// **unversioned** `/api/pmd/*` root, so they go through [ClubApiClient.dioRoot]
/// rather than the `/api/v1` [ClubApiClient.dio]. Self-only (no `target_sqid`
/// moderator mode).
///
/// Bulk endpoints accept at most 128 ids per request; callers chunk above that.
class PmdApi {
  final ClubApiClient client;
  PmdApi(this.client);

  Dio get _dio => client.dioRoot;

  /// `GET /pmd/posts` — cursor-paged list of the user's own posts (excludes playlists).
  Future<Page<PmdPostItem>> listPosts({int limit = 200, String? cursor}) =>
      client.guard(() async {
        final resp = await _dio.get('/pmd/posts', queryParameters: {
          'limit': limit,
          'cursor': ?cursor,
        });
        return Page<PmdPostItem>.fromJson(
            (resp.data as Map).cast<String, dynamic>(), PmdPostItem.fromJson);
      });

  /// `POST /pmd/action` — hide / unhide / delete (`post_ids` ≤ 128).
  Future<BatchActionResult> batchAction(String action, List<int> postIds) =>
      client.guard(() async {
        final resp = await _dio.post('/pmd/action', data: {'action': action, 'post_ids': postIds});
        return BatchActionResult.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// `POST /pmd/license` — set the license on `post_ids` (≤ 128). `licenseId == null`
  /// removes the license (all rights reserved).
  Future<BatchActionResult> batchLicense(List<int> postIds, int? licenseId) =>
      client.guard(() async {
        final resp =
            await _dio.post('/pmd/license', data: {'post_ids': postIds, 'license_id': licenseId});
        return BatchActionResult.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// `POST /pmd/bdr` — queue a ZIP export job (≤ 128 posts; 8/day → 429).
  Future<CreateBdrResult> createBdr(
    List<int> postIds, {
    bool includeComments = false,
    bool includeReactions = false,
    bool sendEmail = false,
  }) =>
      client.guard(() async {
        final resp = await _dio.post('/pmd/bdr', data: {
          'post_ids': postIds,
          'include_comments': includeComments,
          'include_reactions': includeReactions,
          'send_email': sendEmail,
        });
        return CreateBdrResult.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// `GET /pmd/bdr` — the user's recent export jobs (≤ 20).
  Future<List<Bdr>> listBdr() => client.guard(() async {
        final resp = await _dio.get('/pmd/bdr');
        final items = (resp.data as Map?)?['items'] as List? ?? const [];
        return items.map((e) => Bdr.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  /// `GET /pmd/bdr/{id}/download` — the ZIP bytes (404 missing, 410 expired, 400 not ready).
  Future<List<int>> downloadBdr(String id) => client.guard(() async {
        final resp = await _dio.get<List<int>>(
          '/pmd/bdr/${Uri.encodeComponent(id)}/download',
          options: Options(responseType: ResponseType.bytes),
        );
        return resp.data ?? const [];
      });
}
