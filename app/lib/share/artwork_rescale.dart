import 'dart:typed_data';

import 'package:makapix_club/engine_ffi.dart';

/// Nearest-neighbor rescale of an encoded artwork file (PNG/GIF/WebP/BMP,
/// static or animated) to exactly [width]×[height], re-encoded as [format]
/// (`'png'` · `'webp'` · `'gif'`). Frames and their durations survive; the
/// heavy work runs on an isolate (`Engine.encodeRasterInBackground`).
///
/// Returns null when the engine binary is unavailable or the bytes don't
/// decode. Lives in `lib/share` (not `lib/club`) so Club unit tests keep
/// running without the engine binary — Dart fetches, Rust computes.
Future<Uint8List?> rescaleArtworkBytes(Uint8List bytes,
    {required int width, required int height, required String format}) async {
  try {
    final out = await Engine.encodeRasterInBackground(bytes,
        width: width, height: height, format: format);
    return out.isEmpty ? null : out;
  } catch (_) {
    return null; // engine missing or undecodable input
  }
}
