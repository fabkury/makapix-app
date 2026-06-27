import 'package:dio/dio.dart';

import '../models/club_error.dart';
import '../models/license_option.dart';
import '../models/post.dart';
import 'club_api_client.dart';

/// Artwork publishing (`POST /post/upload`) + the license catalog.
class UploadApi {
  final ClubApiClient client;
  UploadApi(this.client);

  Future<List<LicenseOption>> licenses() async {
    try {
      final resp = await client.dio.get('/license');
      final items = (resp.data as Map?)?['items'] as List? ?? const [];
      return items
          .map((e) => LicenseOption.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  /// Multipart upload. On 413 → `file_too_large`, 409 → `artwork_duplicate`,
  /// 429 → `rate_limited` (all via [ClubError]).
  Future<Post> uploadArtwork({
    required List<int> bytes,
    required String filename,
    required String title,
    String description = '',
    String hashtags = '',
    bool hiddenByUser = false,
    int? licenseId,
  }) async {
    try {
      final form = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: filename),
        'title': title,
        'description': description,
        'hashtags': hashtags,
        'hidden_by_user': hiddenByUser.toString(),
        'license_id': ?licenseId?.toString(),
      });
      final resp = await client.dio.post('/post/upload', data: form);
      final data = (resp.data as Map).cast<String, dynamic>();
      // Tolerate either a bare Post or { post: {...} }.
      final postJson = (data['post'] as Map?)?.cast<String, dynamic>() ?? data;
      return Post.fromJson(postJson);
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }
}
