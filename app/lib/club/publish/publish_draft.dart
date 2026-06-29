import 'dart:typed_data';

import '../edit/club_edit_request.dart';

/// The exported artwork handed from the editor to the publish flow. Keeps
/// `lib/club` free of any engine dependency — it receives bytes + dimensions,
/// never the engine handle.
class PublishDraft {
  final Uint8List bytes;
  final String format; // "webp" (lossless; recommended) | "png" | "gif"
  final String filename;
  final int width;
  final int height;
  final int frameCount;

  /// Set when the document was opened from a Club artwork (enables Replace +
  /// remix metadata pre-fill). Null for a brand-new drawing.
  final ClubEditSource? source;

  const PublishDraft({
    required this.bytes,
    required this.format,
    required this.filename,
    required this.width,
    required this.height,
    required this.frameCount,
    this.source,
  });

  bool get isAnimated => frameCount > 1;
  int get byteLength => bytes.length;
}
