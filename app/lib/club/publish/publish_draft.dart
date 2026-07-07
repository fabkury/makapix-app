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

  /// The document as a compact-profile .mkpx ("the layers file"), offered as an
  /// optional attachment at publish time. Null when the draft didn't come from
  /// the editor (direct file upload) — the share checkbox is hidden then.
  final Uint8List? mkpxBytes;

  /// Total loop duration for animated drafts, under the same clamp rules feeds
  /// play by (`AnimationTimeline.computeTotalDurationMs`). Shown on the publish
  /// sheet so an artist can verify a connected series shares one loop duration
  /// (equal loops stay frame-locked on feeds). Null when unknown or static.
  final int? totalDurationMs;

  const PublishDraft({
    required this.bytes,
    required this.format,
    required this.filename,
    required this.width,
    required this.height,
    required this.frameCount,
    this.source,
    this.mkpxBytes,
    this.totalDurationMs,
  });

  bool get isAnimated => frameCount > 1;
  int get byteLength => bytes.length;
}
