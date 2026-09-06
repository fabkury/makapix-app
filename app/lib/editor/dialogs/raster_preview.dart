// The decoded-frames preview shared by the import flow's Crop and Place pages (2026-09-01) and,
// since the Crop canvas page (ADR 0027, 2026-09-06), by the document itself: one decode of the
// frames (with the crop page's soft caps), frame durations, and a tiny playback clock. The owner
// creates it, hands the same instance to every page that draws it, and disposes it once when the
// flow ends — so a many-frame GIF is decoded once, not per page.
//
// The preview is spatial and cosmetic: a truncated preview never affects the actual import or
// crop (the engine works on the full document / animation independently).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Frames + durations + playback clock; subclasses say where the frames come from.
abstract class FramePreview extends ChangeNotifier {
  FramePreview({required this.srcW, required this.srcH});

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

  /// How many frames the source has (may open a codec).
  @protected
  Future<int> frameCount();

  /// The next frame in order, with its duration (0 = use the default).
  @protected
  Future<(ui.Image, Duration)> nextFrame(int index);

  /// Decode once; further calls are no-ops. Notifies on completion (or error).
  Future<void> load() async {
    if (_loading || loaded || loadError) return;
    _loading = true;
    try {
      final count = await frameCount();
      final fs = <ui.Image>[];
      final ds = <Duration>[];
      var pixels = 0;
      var trunc = false;
      for (var i = 0; i < count; i++) {
        final (image, duration) = await nextFrame(i);
        fs.add(image);
        ds.add(duration.inMicroseconds <= 0 ? const Duration(milliseconds: 100) : duration);
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

/// A raster file's frames (the import flow).
class RasterPreview extends FramePreview {
  RasterPreview(this.bytes, {required super.srcW, required super.srcH});

  final Uint8List bytes;
  ui.Codec? _codec;

  @override
  Future<int> frameCount() async {
    _codec = await ui.instantiateImageCodec(bytes);
    return _codec!.frameCount;
  }

  @override
  Future<(ui.Image, Duration)> nextFrame(int index) async {
    final fi = await _codec!.getNextFrame();
    return (fi.image, fi.duration);
  }
}

/// The open document's composited frames (the Crop canvas page): the owner supplies the frame
/// count, each frame's duration, and a compositor that yields frame `i` as a [ui.Image].
class CanvasPreview extends FramePreview {
  CanvasPreview({
    required super.srcW,
    required super.srcH,
    required this.totalFrames,
    required List<int> durationsUs,
    required this.composite,
  }) : _durations = [for (final us in durationsUs) Duration(microseconds: us)];

  final int totalFrames;
  final List<Duration> _durations;
  final Future<ui.Image> Function(int frame) composite;

  @override
  Future<int> frameCount() async => totalFrames;

  @override
  Future<(ui.Image, Duration)> nextFrame(int index) async =>
      (await composite(index), index < _durations.length ? _durations[index] : Duration.zero);
}
