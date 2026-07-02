import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/post.dart';
import 'club_api_client.dart';

/// Layers-file (.mkpx) attachments (feature "mkpx-upload", server contract in
/// reference/makapix-club/docs/mkpx-upload/API-CONTRACT.md).
///
/// The server validates only the 8-byte signature and the config size cap and
/// stores the file as an opaque blob; deep validation stays in the engine
/// loader. Attach/replace consumes an upload rate-limit token even when
/// rejected, so callers pre-check [looksLikeMkpx] and the config cap first.
class MkpxApi {
  final ClubApiClient client;
  MkpxApi(this.client);

  /// A layers file can legitimately reach tens of MB; the default 30 s I/O
  /// timeouts are sized for JSON, not blobs.
  static const Duration _blobTimeout = Duration(minutes: 5);

  /// Both accepted profile signatures (SPEC.md / mkpx-format v10) differ only
  /// at byte 4: plain `\x89MKPX\r\n\x1a` vs compact `\x89MKPZ\r\n\x1a`.
  static const List<int> _sigPlain = [0x89, 0x4D, 0x4B, 0x50, 0x58, 0x0D, 0x0A, 0x1A];

  /// Client-side mirror of the server's magic-byte check (`mkpx_invalid`).
  static bool looksLikeMkpx(List<int> bytes) {
    if (bytes.length < 8) return false;
    for (var i = 0; i < 8; i++) {
      final ok = i == 4
          ? (bytes[i] == 0x58 /* X */ || bytes[i] == 0x5A /* Z */)
          : bytes[i] == _sigPlain[i];
      if (!ok) return false;
    }
    return true;
  }

  /// `POST /post/{id}/mkpx` — attach, or silently replace an existing layers
  /// file. Author-only (403), artwork posts only (404). Returns the updated post.
  Future<Post> attach(int postId, List<int> bytes) => client.guard(() async {
        final form = FormData.fromMap({
          'mkpx': MultipartFile.fromBytes(bytes, filename: 'layers.mkpx'),
        });
        final resp = await client.dio.post(
          '/post/$postId/mkpx',
          data: form,
          options: Options(sendTimeout: _blobTimeout),
        );
        final data = (resp.data as Map).cast<String, dynamic>();
        final postJson = (data['post'] as Map?)?.cast<String, dynamic>() ?? data;
        return Post.fromJson(postJson);
      });

  /// `DELETE /post/{id}/mkpx` — detach. Author-only; 404 when none attached.
  /// Consumes no rate-limit token. Returns the updated post.
  Future<Post> detach(int postId) => client.guard(() async {
        final resp = await client.dio.delete('/post/$postId/mkpx');
        final data = (resp.data as Map).cast<String, dynamic>();
        final postJson = (data['post'] as Map?)?.cast<String, dynamic>() ?? data;
        return Post.fromJson(postJson);
      });

  /// `GET /d/{public_sqid}.mkpx` — the exact stored bytes. Bearer required
  /// (401 → [ClubError.isAuth]); 404 when no layers file or post not visible.
  /// Whole-file response (no Range), hence the generous timeout.
  Future<Uint8List> download(String sqid) => client.guard(() async {
        final resp = await client.dio.get<List<int>>(
          '/d/${Uri.encodeComponent(sqid)}.mkpx',
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: _blobTimeout,
          ),
        );
        return Uint8List.fromList(resp.data ?? const []);
      });
}
