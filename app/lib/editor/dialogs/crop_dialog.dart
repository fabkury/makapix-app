import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Which corner reticle is being dragged.
enum CropCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Pure, Flutter-free crop-rectangle geometry — all values are **integer source pixels**, so the
/// rect never accumulates fractional drift that `importImage`'s `.toInt()` would silently truncate.
/// The engine places this region 1:1 centered on the canvas (downscaled to fit only when larger),
/// so the math here mirrors `fit_no_upscale` in `crates/engine/src/import.rs`.
class CropGeometry {
  final int srcW, srcH, canvasW, canvasH;
  int x = 0, y = 0, w = 1, h = 1;
  bool aspectLocked = false;

  CropGeometry({required this.srcW, required this.srcH, required this.canvasW, required this.canvasH}) {
    // Default: canvas-size rect centered on the source, clamped to the source bounds (so a source
    // smaller than the canvas defaults to the whole source; the engine then centers it 1:1).
    w = canvasW.clamp(1, srcW);
    h = canvasH.clamp(1, srcH);
    x = ((srcW - w) / 2).round();
    y = ((srcH - h) / 2).round();
    _clamp();
  }

  double get _aspect => canvasW / canvasH; // canvas W:H

  void _clamp() {
    w = w.clamp(1, srcW);
    h = h.clamp(1, srcH);
    x = x.clamp(0, srcW - w);
    y = y.clamp(0, srcH - h);
  }

  Rect toRect() => Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());

  /// Move the whole rectangle to a new origin (clamped so it stays fully within the source).
  void setOrigin(int nx, int ny) {
    x = nx;
    y = ny;
    x = x.clamp(0, srcW - w);
    y = y.clamp(0, srcH - h);
  }

  /// Drag one corner to source-pixel `(sx, sy)`, keeping the opposite corner fixed.
  void dragCorner(CropCorner c, int sx, int sy) {
    sx = sx.clamp(0, srcW);
    sy = sy.clamp(0, srcH);
    final l = x, t = y, r = x + w, b = y + h;
    final fixedRight = c == CropCorner.topLeft || c == CropCorner.bottomLeft; // the LEFT edge is moving
    final fixedBottom = c == CropCorner.topLeft || c == CropCorner.topRight; // the TOP edge is moving
    var nw = fixedRight ? r - sx : sx - l;
    var nh = fixedBottom ? b - sy : sy - t;
    // Space available from the fixed corner toward the moving corner.
    final maxW = fixedRight ? r : srcW - l;
    final maxH = fixedBottom ? b : srcH - t;
    nw = nw.clamp(1, maxW);
    nh = nh.clamp(1, maxH);
    if (aspectLocked) {
      nh = (nw / _aspect).round().clamp(1, maxH);
      if ((nh / maxH) >= 1 || nh < (nw / _aspect).round()) {
        nw = (nh * _aspect).round().clamp(1, maxW);
      }
    }
    // Re-anchor the fixed corner.
    x = fixedRight ? r - nw : l;
    y = fixedBottom ? b - nh : t;
    w = nw;
    h = nh;
    _clamp();
  }

  /// Set one of the four fields from direct numeric entry (anchored at the top-left for W/H).
  void setField(String field, int value) {
    switch (field) {
      case 'x':
        x = value.clamp(0, srcW - w);
      case 'y':
        y = value.clamp(0, srcH - h);
      case 'w':
        w = value.clamp(1, srcW - x);
        if (aspectLocked) h = (w / _aspect).round().clamp(1, srcH - y);
      case 'h':
        h = value.clamp(1, srcH - y);
        if (aspectLocked) w = (h * _aspect).round().clamp(1, srcW - x);
    }
    _clamp();
  }

  void toggleAspectLock() {
    aspectLocked = !aspectLocked;
    if (aspectLocked) {
      final nh = (w / _aspect).round();
      h = nh.clamp(1, srcH - y);
      if (h != nh) w = (h * _aspect).round().clamp(1, srcW - x);
      _clamp();
    }
  }

  /// The on-canvas size this crop will produce — mirrors `fit_no_upscale` (integer cross-multiply).
  (int, int) resultDims() {
    if (w <= canvasW && h <= canvasH) return (w, h);
    if (w * canvasH >= h * canvasW) {
      return (canvasW, (h * canvasW ~/ w).clamp(1, canvasH));
    }
    return ((w * canvasH ~/ h).clamp(1, canvasW), canvasH);
  }
}

/// A large, dedicated crop editor for imported rasters (static or animated). Returns the chosen crop
/// rectangle in **source pixels** (or null on cancel). The engine (`mkpx_import`) places that region
/// 1:1 centered on the canvas, downscaling only when it is larger than the canvas.
class CropPage extends StatefulWidget {
  final Uint8List bytes;
  final int srcW, srcH, canvasW, canvasH;
  const CropPage({
    super.key,
    required this.bytes,
    required this.srcW,
    required this.srcH,
    required this.canvasW,
    required this.canvasH,
  });
  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> with SingleTickerProviderStateMixin {
  // Soft caps for the animated preview: a big source can allocate ~1 GB+ of GPU textures across
  // 1,024 frames, which OOMs phones. The crop rect is spatial, so a truncated PREVIEW never affects
  // the actual import (the engine decodes the full animation independently).
  static const int _kMaxPreviewFrames = 120;
  static const int _kMaxPreviewPixels = 64 * 1000 * 1000;
  static const double _reticleRadius = 11; // drawn radius
  static const double _reticleHit = 28; // touch radius

  late final CropGeometry _geo;
  late final Ticker _ticker;
  final List<ui.Image> _frames = [];
  final List<Duration> _durations = [];
  bool _truncated = false;
  bool _loadError = false;
  int _current = 0;
  bool _playing = false;
  Duration _last = Duration.zero;
  Duration _acc = Duration.zero;

  // Drag state (snapshot on pan-start to avoid fractional drift).
  CropCorner? _dragCorner;
  bool _dragMove = false;
  Offset _startLocal = Offset.zero;
  int _startX = 0, _startY = 0;
  double _scale = 1;
  Offset _imgOrigin = Offset.zero;

  @override
  void initState() {
    super.initState();
    _geo = CropGeometry(srcW: widget.srcW, srcH: widget.srcH, canvasW: widget.canvasW, canvasH: widget.canvasH);
    _ticker = createTicker(_onTick);
    _load();
  }

  Future<void> _load() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final count = codec.frameCount;
      final frames = <ui.Image>[];
      final durations = <Duration>[];
      var pixels = 0;
      var truncated = false;
      for (var i = 0; i < count; i++) {
        final fi = await codec.getNextFrame();
        frames.add(fi.image);
        durations.add(fi.duration.inMicroseconds <= 0 ? const Duration(milliseconds: 100) : fi.duration);
        pixels += widget.srcW * widget.srcH;
        if (frames.length >= _kMaxPreviewFrames || pixels >= _kMaxPreviewPixels) {
          truncated = i + 1 < count;
          break;
        }
      }
      if (!mounted) {
        for (final f in frames) {
          f.dispose();
        }
        return;
      }
      setState(() {
        _frames
          ..clear()
          ..addAll(frames);
        _durations
          ..clear()
          ..addAll(durations);
        _truncated = truncated;
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final f in _frames) {
      f.dispose();
    }
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_frames.length < 2) return;
    final dt = elapsed - _last;
    _last = elapsed;
    _acc += dt;
    var cur = _current;
    var guard = 0;
    while (_acc >= _durations[cur] && guard++ < _frames.length) {
      _acc -= _durations[cur];
      cur = (cur + 1) % _frames.length;
    }
    if (cur != _current && mounted) setState(() => _current = cur);
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        _last = Duration.zero;
        _acc = Duration.zero;
        _ticker.start();
      } else {
        _ticker.stop();
      }
    });
  }

  // ---- gesture / coordinate mapping ----

  int _srcX(double localX) => ((localX - _imgOrigin.dx) / _scale).round();
  int _srcY(double localY) => ((localY - _imgOrigin.dy) / _scale).round();

  void _onPanStart(DragStartDetails d) {
    final p = d.localPosition;
    // Corner reticles first (generous radius), then inside-rect move.
    for (final c in CropCorner.values) {
      if ((p - _cornerScreen(c)).distance <= _reticleHit) {
        _dragCorner = c;
        _dragMove = false;
        return;
      }
    }
    final rectScreen = Rect.fromLTWH(
      _imgOrigin.dx + _geo.x * _scale,
      _imgOrigin.dy + _geo.y * _scale,
      _geo.w * _scale,
      _geo.h * _scale,
    );
    if (rectScreen.contains(p)) {
      _dragMove = true;
      _dragCorner = null;
      _startLocal = p;
      _startX = _geo.x;
      _startY = _geo.y;
    } else {
      _dragMove = false;
      _dragCorner = null;
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragCorner != null) {
      setState(() => _geo.dragCorner(_dragCorner!, _srcX(d.localPosition.dx), _srcY(d.localPosition.dy)));
    } else if (_dragMove) {
      final dx = ((d.localPosition.dx - _startLocal.dx) / _scale).round();
      final dy = ((d.localPosition.dy - _startLocal.dy) / _scale).round();
      setState(() => _geo.setOrigin(_startX + dx, _startY + dy));
    }
  }

  Offset _cornerScreen(CropCorner c) {
    final l = _imgOrigin.dx + _geo.x * _scale;
    final t = _imgOrigin.dy + _geo.y * _scale;
    final r = l + _geo.w * _scale;
    final b = t + _geo.h * _scale;
    switch (c) {
      case CropCorner.topLeft:
        return Offset(l, t);
      case CropCorner.topRight:
        return Offset(r, t);
      case CropCorner.bottomLeft:
        return Offset(l, b);
      case CropCorner.bottomRight:
        return Offset(r, b);
    }
  }

  Future<void> _editField(String field, int current, String label) async {
    final ctrl = TextEditingController(text: '$current');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label (px)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (t) => Navigator.pop(ctx, int.tryParse(t.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())), child: const Text('Set')),
        ],
      ),
    );
    if (v != null) setState(() => _geo.setField(field, v));
  }

  Widget _coordChip(String field, String label, int value) => ActionChip(
        label: Text('$label $value'),
        onPressed: () => _editField(field, value, label),
      );

  @override
  Widget build(BuildContext context) {
    final animated = _frames.length > 1;
    final (rw, rh) = _geo.resultDims();
    final downscaled = rw < _geo.w || rh < _geo.h;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop'),
        actions: [
          IconButton(
            tooltip: _geo.aspectLocked ? 'Aspect locked to canvas' : 'Lock to canvas aspect',
            icon: Icon(_geo.aspectLocked ? Icons.lock : Icons.lock_open),
            onPressed: () => setState(() => _geo.toggleAspectLock()),
          ),
          IconButton(
            tooltip: 'Reset crop',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(() {
              final fresh = CropGeometry(
                  srcW: widget.srcW, srcH: widget.srcH, canvasW: widget.canvasW, canvasH: widget.canvasH);
              _geo
                ..x = fresh.x
                ..y = fresh.y
                ..w = fresh.w
                ..h = fresh.h
                ..aspectLocked = false;
            }),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loadError
              ? const Center(child: Text('Could not decode this image.'))
              : _frames.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(builder: (ctx, cons) {
                      const margin = 16.0;
                      final availW = cons.maxWidth - margin * 2;
                      final availH = cons.maxHeight - margin * 2;
                      _scale = (availW / widget.srcW).clamp(0.0, double.infinity);
                      final sh = availH / widget.srcH;
                      if (sh < _scale) _scale = sh;
                      final dispW = widget.srcW * _scale;
                      final dispH = widget.srcH * _scale;
                      _imgOrigin = Offset(margin + (availW - dispW) / 2, margin + (availH - dispH) / 2);
                      return GestureDetector(
                        onPanStart: _onPanStart,
                        onPanUpdate: _onPanUpdate,
                        child: CustomPaint(
                          size: Size(cons.maxWidth, cons.maxHeight),
                          painter: _CropPreviewPainter(
                            image: _frames[_current],
                            geo: _geo,
                            scale: _scale,
                            origin: _imgOrigin,
                            reticleRadius: _reticleRadius,
                          ),
                        ),
                      );
                    }),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                onPressed: animated ? _togglePlay : null,
              ),
              Text(
                animated ? 'Frame ${_current + 1} / ${_frames.length}' : 'Static',
                style: const TextStyle(fontSize: 13),
              ),
              if (_truncated)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('(preview truncated — full animation still imports)',
                      style: TextStyle(fontSize: 11, color: Colors.white54)),
                ),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _coordChip('x', 'X', _geo.x),
              _coordChip('y', 'Y', _geo.y),
              _coordChip('w', 'W', _geo.w),
              _coordChip('h', 'H', _geo.h),
            ]),
            const SizedBox(height: 6),
            Text(
              downscaled
                  ? 'On canvas: $rw × $rh px (downscaled to fit ${widget.canvasW}×${widget.canvasH}, centered)'
                  : 'On canvas: $rw × $rh px (placed 1:1, centered)',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _frames.isEmpty ? null : () => Navigator.pop(context, _geo.toRect()),
              child: const Text('Use crop'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CropPreviewPainter extends CustomPainter {
  final ui.Image image;
  final CropGeometry geo;
  final double scale;
  final Offset origin;
  final double reticleRadius;
  _CropPreviewPainter({
    required this.image,
    required this.geo,
    required this.scale,
    required this.origin,
    required this.reticleRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imgRect = Rect.fromLTWH(origin.dx, origin.dy, geo.srcW * scale, geo.srcH * scale);
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    // Nearest-neighbor so pixel art stays crisp.
    canvas.drawImageRect(image, src, imgRect, Paint()..filterQuality = FilterQuality.none);

    final crop = Rect.fromLTWH(
      origin.dx + geo.x * scale,
      origin.dy + geo.y * scale,
      geo.w * scale,
      geo.h * scale,
    );
    // Shade the image OUTSIDE the crop rect (even-odd: outer minus inner).
    final shade = Path()
      ..addRect(imgRect)
      ..addRect(crop)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = const Color(0x99000000));

    // Crop outline.
    canvas.drawRect(
      crop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.amber,
    );

    // Large corner reticles.
    final fill = Paint()..color = Colors.white;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black87;
    for (final c in [crop.topLeft, crop.topRight, crop.bottomLeft, crop.bottomRight]) {
      canvas.drawCircle(c, reticleRadius, fill);
      canvas.drawCircle(c, reticleRadius, ring);
    }
  }

  @override
  bool shouldRepaint(_CropPreviewPainter old) =>
      old.image != image ||
      old.scale != scale ||
      old.origin != origin ||
      old.geo.x != geo.x ||
      old.geo.y != geo.y ||
      old.geo.w != geo.w ||
      old.geo.h != geo.h;
}
