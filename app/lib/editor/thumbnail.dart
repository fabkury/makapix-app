import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:makapix_club/engine_ffi.dart' show premultiplyRgbaInPlace;

// A cached frame thumbnail tagged with the frame content hash it was generated from.
class ThumbCache {
  final int hash;
  final ui.Image img;
  ThumbCache(this.hash, this.img);
}

/// Decode engine-emitted straight-alpha RGBA bytes into a [ui.Image]. The raw decode expects
/// premultiplied pixels, so the bytes are premultiplied IN PLACE first — pass a buffer you own.
/// One helper for the film roll, the layer strip, the gallery, and the Frames page.
Future<ui.Image> decodeRgbaImage(Uint8List bytes, int w, int h) {
  final c = Completer<ui.Image>();
  premultiplyRgbaInPlace(bytes);
  ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// The thumbnail size for a `w`×`h` artwork: the longer side is [maxSide], the other follows the
/// aspect (never below 1). The film roll uses 64; the Frames page's larger tiles use 96.
(int, int) thumbSizeFor(int w, int h, {int maxSide = 64}) {
  if (w <= 0 || h <= 0) return (maxSide, maxSide);
  if (w >= h) {
    final t = (maxSide * h / w).round().clamp(1, maxSide).toInt();
    return (maxSide, t);
  }
  final t = (maxSide * w / h).round().clamp(1, maxSide).toInt();
  return (t, maxSide);
}
