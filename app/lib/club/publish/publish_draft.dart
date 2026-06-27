import 'dart:typed_data';

/// The exported artwork handed from the editor to the publish flow. Keeps
/// `lib/club` free of any engine dependency — it receives bytes + dimensions,
/// never the engine handle.
class PublishDraft {
  final Uint8List bytes;
  final String format; // "png" (static) | "gif" (animated)
  final String filename;
  final int width;
  final int height;
  final int frameCount;

  const PublishDraft({
    required this.bytes,
    required this.format,
    required this.filename,
    required this.width,
    required this.height,
    required this.frameCount,
  });

  bool get isAnimated => frameCount > 1;
  int get byteLength => bytes.length;
}
