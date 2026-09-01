// The decoded-frames preview shared by the import flow's Crop and Place pages (2026-09-01): one
// decode of the source raster (with the crop page's soft caps), frame durations, and a tiny
// playback clock. The import flow creates it, hands the same instance to both pages, and
// disposes it once when the flow ends — so a many-frame GIF is decoded once, not per page.
//
// The preview is spatial and cosmetic: a truncated preview never affects the actual import (the
// engine decodes the full animation independently on its own isolate).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

class RasterPreview extends ChangeNotifier {
  RasterPreview(this.bytes, {required this.srcW, required this.srcH});

  final Uint8List bytes;
  final int srcW, srcH;

  // Soft caps: a big source can allocate ~1 GB+ of GPU textures across 1,024 frames, which OOMs
  // phones. The crop rect / placement are spatial, so truncating the PREVIEW loses nothing.
  static const int kMaxFrames = 120;
  static const int kMaxPixels = 64 * 1000 * 1000;

  final List<ui.Image> frames = [];
  final List<Duration> durations = [];
  bool truncated = false;
  bool loadError = false;
  bool _loading = false;
  bool _disposed = false;

  bool get loaded => frames.isNotEmpty;
  bool get animated => frames.length > 1;

  /// Decode once; further calls are no-ops. Notifies on completion (or error).
  Future<void> load() async {
    if (_loading || loaded || loadError) return;
    _loading = true;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final count = codec.frameCount;
      final fs = <ui.Image>[];
      final ds = <Duration>[];
      var pixels = 0;
      var trunc = false;
      for (var i = 0; i < count; i++) {
        final fi = await codec.getNextFrame();
        fs.add(fi.image);
        ds.add(fi.duration.inMicroseconds <= 0 ? const Duration(milliseconds: 100) : fi.duration);
        pixels += srcW * srcH;
        if (fs.length >= kMaxFrames || pixels >= kMaxPixels) {
          trunc = i + 1 < count;
          break;
        }
      }
      if (_disposed) {
        for (final f in fs) {
          f.dispose();
        }
        return;
      }
      frames.addAll(fs);
      durations.addAll(ds);
      truncated = trunc;
    } catch (_) {
      if (!_disposed) loadError = true;
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Advance a playback clock: given the accumulated time since the current frame started and the
  /// current index, return the new (index, leftover) pair. Pure; the pages own their tickers.
  (int, Duration) advance(int current, Duration acc) {
    if (frames.length < 2) return (current, Duration.zero);
    var cur = current;
    var guard = 0;
    while (acc >= durations[cur] && guard++ < frames.length) {
      acc -= durations[cur];
      cur = (cur + 1) % frames.length;
    }
    return (cur, acc);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final f in frames) {
      f.dispose();
    }
    frames.clear();
    super.dispose();
  }
}
