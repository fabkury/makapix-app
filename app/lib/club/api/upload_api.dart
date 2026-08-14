import 'package:dio/dio.dart';

import '../models/license_option.dart';
import '../models/post.dart';
import 'club_api_client.dart';

/// Artwork publishing (`POST /post/upload`) + the license catalog.
class UploadApi {
  final ClubApiClient client;
  UploadApi(this.client);

  Future<List<LicenseOption>> licenses() => client.guard(() async {
        final resp = await client.dio.get('/license');
        final items = (resp.data as Map?)?['items'] as List? ?? const [];
        return items
            .map((e) => LicenseOption.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  /// Multipart upload. On 413 → `file_too_large`, 409 → `artwork_duplicate`,
  /// 429 → `rate_limited` (all via [ClubError]).
  ///
  /// [mkpxBytes] optionally attaches the layers (.mkpx) file in the same call
  /// (contract §6): atomic — if it fails validation (`mkpx_invalid`,
  /// `mkpx_too_large`) or quota, no post is created.
  ///
  /// [provenanceFields] are the optional provenance/lineage declarations
  /// (`client`, `creation_method`, `source_details`, `remixed_from`,
  /// `remixable` — see `publish/provenance_fields.dart`). Lineage failures:
  /// 422 `parent_not_found` / `remix_not_allowed` / `too_many_parents`.
  Future<Post> uploadArtwork({
    required List<int> bytes,
    required String filename,
    required String title,
    String description = '',
    String hashtags = '',
    bool hiddenByUser = false,
    int? licenseId,
    List<int>? mkpxBytes,
    Map<String, String> provenanceFields = const {},
  }) =>
      client.guard(() async {
        final form = FormData.fromMap({
          'image': MultipartFile.fromBytes(bytes, filename: filename),
          'title': title,
          'description': description,
          'hashtags': hashtags,
          'hidden_by_user': hiddenByUser.toString(),
          'license_id': ?licenseId?.toString(),
          ...provenanceFields,
          if (mkpxBytes != null)
            'mkpx': MultipartFile.fromBytes(mkpxBytes, filename: 'layers.mkpx'),
        });
        final resp = await client.dio.post('/post/upload',
            data: form,
            // A layers file can reach tens of MB; the default 30 s send
            // timeout is sized for the ≤5 MB artwork alone.
            options: mkpxBytes == null
                ? null
                : Options(sendTimeout: const Duration(minutes: 5)));
        final data = (resp.data as Map).cast<String, dynamic>();
        // Tolerate either a bare Post or { post: {...} }.
        final postJson = (data['post'] as Map?)?.cast<String, dynamic>() ?? data;
        return Post.fromJson(postJson);
      });

  /// Replace an existing post's artwork in place (owner / allow-edit; the server
  /// enforces permission). Keeps the post's reactions/comments/stats.
  ///
  /// [provenanceFields] as on [uploadArtwork]; here `remixed_from` APPENDS
  /// lineage links (existing ones are never removed) and `remixable` is ignored
  /// (that toggle belongs to PATCH /post/{id}).
  Future<Post> replaceArtwork(int postId, List<int> bytes, String filename,
          {Map<String, String> provenanceFields = const {}}) =>
      client.guard(() async {
        final form = FormData.fromMap({
          'image': MultipartFile.fromBytes(bytes, filename: filename),
          ...provenanceFields,
        });
        final resp = await client.dio.post('/post/$postId/replace-artwork', data: form);
        final data = (resp.data as Map?)?.cast<String, dynamic>() ?? const {};
        final postJson = (data['post'] as Map?)?.cast<String, dynamic>() ?? data;
        return Post.fromJson(postJson);
      });
}
