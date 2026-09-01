import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
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

/// Pure view transform for the crop editor (2026-09-01): the source is drawn at
/// `fitScale × zoom` screen px per source px, centered in the viewport, then shifted by [pan].
/// `zoom` runs from 1 (fit to screen — never below: there is nothing to see out there) up to
/// [maxZoom], the zoom that puts [maxPxPerSource] screen px on one source pixel (the editor
/// canvas's own ceiling). Pan is clamped so at least [keep] px of the image stay inside the
/// viewport on each axis, and is pinned to zero at fit. Unit-tested; the page only feeds it
/// gestures and reads [scale] / [origin].
class CropView {
  CropView({required this.srcW, required this.srcH, this.margin = 16});
  final int srcW, srcH;
  final double margin;
  static const double maxPxPerSource = 32;
  static const double keep = 48;

  Size view = Size.zero;
  double zoom = 1;
  Offset pan = Offset.zero;

  double get fitScale {
    final aw = math.max(1.0, view.width - margin * 2);
    final ah = math.max(1.0, view.height - margin * 2);
    return math.min(aw / srcW, ah / srcH);
  }

  double get scale => fitScale * zoom;
  double get maxZoom => math.max(1.0, maxPxPerSource / fitScale);
  bool get isFit => zoom <= 1.0001;

  /// The image's top-left on screen at the current zoom and pan.
  Offset get origin => _centeredOrigin + pan;
  Offset get _centeredOrigin => Offset((view.width - srcW * scale) / 2, (view.height - srcH * scale) / 2);

  /// Adopt the viewport size (re-clamping the pan; a rotation must not strand the image).
  void setView(Size s) {
    if (s == view) return;
    view = s;
    _clampPan();
  }

  /// Zoom to [newZoom] (clamped) keeping the source point under screen point [p] fixed.
  void zoomAt(Offset p, double newZoom) {
    final oldScale = scale;
    final oldOrigin = origin;
    zoom = newZoom.clamp(1.0, maxZoom);
    final k = scale / oldScale;
    final desiredOrigin = p - (p - oldOrigin) * k;
    pan = desiredOrigin - _centeredOrigin;
    _clampPan();
  }

  void panBy(Offset d) {
    pan += d;
    _clampPan();
  }

  void fit() {
    zoom = 1;
    pan = Offset.zero;
  }

  /// Double-tap: back to fit when zoomed, else 4× fit about the tapped point.
  void toggleDoubleTap(Offset p) {
    if (isFit) {
      zoomAt(p, 4);
    } else {
      fit();
    }
  }

  /// Screen → source pixel (rounded), for corner drags.
  int srcX(double localX) => ((localX - origin.dx) / scale).round();
  int srcY(double localY) => ((localY - origin.dy) / scale).round();

  void _clampPan() {
    if (isFit) {
      pan = Offset.zero;
      return;
    }
    final base = _centeredOrigin;
    double axis(double p, double b, double disp, double extent) {
      // origin allowed in [keep − disp, extent − keep]; too small a viewport stays centered
      final lo = keep - disp - b, hi = extent - keep - b;
      return lo > hi ? 0 : p.clamp(lo, hi);
    }
    pan = Offset(axis(pan.dx, base.dx, srcW * scale, view.width), axis(pan.dy, base.dy, srcH * scale, view.height));
  }
}

/// How a raster to import relates to the canvas (2026-09-01): the Fit / Stretch / Crop chooser
/// only earns its place for a source larger than the canvas in at least one dimension. A source
/// no larger than the canvas is placed 1:1 centered unless the user asks to scale it up; one the
/// exact canvas size has a single outcome and no scaling UI at all.
enum ImportSizeClass { exact, small, large }

ImportSizeClass importSizeClass(int srcW, int srcH, int canvasW, int canvasH) {
  if (srcW == canvasW && srcH == canvasH) return ImportSizeClass.exact;
  if (srcW <= canvasW && srcH <= canvasH) return ImportSizeClass.small;
  return ImportSizeClass.large;
}

/// Engine arguments for a source no larger than the canvas: [scaleUp] → Fit (mode 0, the
/// aspect-kept upscale to fill the canvas); otherwise the whole source as an explicit crop
/// region, which the engine places 1:1 centered (never upscaled) — the documented crop path
/// rather than the anchor-centered Crop mode, so the placement is the one the crop editor uses.
({int mode, Rect? crop}) smallSourceImportArgs({required bool scaleUp, required int srcW, required int srcH}) =>
    scaleUp ? (mode: 0, crop: null) : (mode: 2, crop: Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()));

/// A large, dedicated crop editor for imported rasters (static or animated). Returns the chosen crop
/// rectangle in **source pixels** (or null on cancel). The engine (`mkpx_import`) places that region
/// 1:1 centered on the canvas, downscaling only when it is larger than the canvas.
///
/// View gestures (user decisions 2026-09-01): one finger always edits the crop (a corner reticle
/// or the rect body); two fingers pan and pinch-zoom about the pinch point; a trackpad pan/pinch
/// does the same; the mouse wheel zooms about the cursor (the editor canvas's step); a right- or
/// middle-button drag pans; double-tap toggles fit ↔ 4× at the tapped point; the app bar's
/// "Fit view" resets. Zoom runs from fit to 32 screen px per source px.
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
  // One wheel notch zooms by this factor (the editor canvas's constants: 60 logical px per notch).
  static const double _kWheelZoomStep = 1.2, _kWheelNotchDelta = 60.0;

  late final CropGeometry _geo;
  late final CropView _view;
  late final Ticker _ticker;
  final List<ui.Image> _frames = [];
  final List<Duration> _durations = [];
  bool _truncated = false;
  bool _loadError = false;
  int _current = 0;
  bool _playing = false;
  Duration _last = Duration.zero;
  Duration _acc = Duration.zero;

  // Crop-drag state (snapshot on start to avoid fractional drift).
  CropCorner? _dragCorner;
  bool _dragMove = false;
  Offset _startLocal = Offset.zero;
  int _startX = 0, _startY = 0;
  // View-gesture state: a scale gesture is a view gesture from its start (two fingers / trackpad)
  // or becomes one the moment a second finger lands — and stays one until it ends, so lifting
  // back to one finger never resumes a crop edit mid-air.
  bool _viewGesture = false;
  // ScaleUpdateDetails.scale is cumulative only until the finger count changes (the recognizer
  // re-references and reports 1 again), so zoom is applied as the ratio between consecutive
  // updates, with the reference re-seeded on every pointer-count change.
  double _lastGestureScale = 1;
  int _lastPointerCount = 0;
  // Mouse: a right/middle-button drag pans; tracked from the raw Listener so the primary-button
  // scale recognizer never sees it as a crop edit.
  bool _mousePan = false;
  Offset _mouseLast = Offset.zero;

  @override
  void initState() {
    super.initState();
    _geo = CropGeometry(srcW: widget.srcW, srcH: widget.srcH, canvasW: widget.canvasW, canvasH: widget.canvasH);
    _view = CropView(srcW: widget.srcW, srcH: widget.srcH);
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

  // ---- gestures ----

  void _endCropDrag() {
    _dragCorner = null;
    _dragMove = false;
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (_mousePan) return;
    _viewGesture = d.pointerCount >= 2 || d.kind == PointerDeviceKind.trackpad;
    if (_viewGesture) {
      _endCropDrag();
      _lastGestureScale = 1;
      _lastPointerCount = d.pointerCount;
      return;
    }
    // One finger: corner reticles first (generous radius), then inside-rect move.
    final p = d.localFocalPoint;
    for (final c in CropCorner.values) {
      if ((p - _cornerScreen(c)).distance <= _reticleHit) {
        _dragCorner = c;
        _dragMove = false;
        return;
      }
    }
    final rectScreen = Rect.fromLTWH(
      _view.origin.dx + _geo.x * _view.scale,
      _view.origin.dy + _geo.y * _view.scale,
      _geo.w * _view.scale,
      _geo.h * _view.scale,
    );
    if (rectScreen.contains(p)) {
      _dragMove = true;
      _dragCorner = null;
      _startLocal = p;
      _startX = _geo.x;
      _startY = _geo.y;
    } else {
      _endCropDrag();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_mousePan) return;
    if (!_viewGesture && d.pointerCount >= 2) {
      // A second finger joined a crop edit: it is a view gesture from here on.
      _viewGesture = true;
      _endCropDrag();
      _lastGestureScale = d.scale;
      _lastPointerCount = d.pointerCount;
    }
    if (_viewGesture) {
      if (d.pointerCount != _lastPointerCount) {
        _lastPointerCount = d.pointerCount;
        _lastGestureScale = d.scale; // re-referenced: no zoom step on this update
      }
      final ratio = _lastGestureScale > 0 ? d.scale / _lastGestureScale : 1.0;
      _lastGestureScale = d.scale;
      setState(() {
        // Pinch about the (moving) focal point: zoom keeps the source under the focal point
        // fixed, then the focal drift pans.
        if (ratio != 1) _view.zoomAt(d.localFocalPoint, _view.zoom * ratio);
        _view.panBy(d.focalPointDelta);
      });
      return;
    }
    if (_dragCorner != null) {
      setState(() =>
          _geo.dragCorner(_dragCorner!, _view.srcX(d.localFocalPoint.dx), _view.srcY(d.localFocalPoint.dy)));
    } else if (_dragMove) {
      final dx = ((d.localFocalPoint.dx - _startLocal.dx) / _view.scale).round();
      final dy = ((d.localFocalPoint.dy - _startLocal.dy) / _view.scale).round();
      setState(() => _geo.setOrigin(_startX + dx, _startY + dy));
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _viewGesture = false;
    _endCropDrag();
  }

  void _onDoubleTapDown(TapDownDetails d) => setState(() => _view.toggleDoubleTap(d.localPosition));

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse && (e.buttons & (kSecondaryButton | kMiddleMouseButton)) != 0) {
      _mousePan = true;
      _mouseLast = e.localPosition;
      _endCropDrag();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_mousePan) return;
    final delta = e.localPosition - _mouseLast;
    _mouseLast = e.localPosition;
    if (delta != Offset.zero) setState(() => _view.panBy(delta));
  }

  void _onPointerUp(PointerEvent e) => _mousePan = false;

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final factor = math.pow(_kWheelZoomStep, -e.scrollDelta.dy / _kWheelNotchDelta).toDouble();
    setState(() => _view.zoomAt(e.localPosition, _view.zoom * factor));
  }

  Offset _cornerScreen(CropCorner c) {
    final l = _view.origin.dx + _geo.x * _view.scale;
    final t = _view.origin.dy + _geo.y * _view.scale;
    final r = l + _geo.w * _view.scale;
    final b = t + _geo.h * _view.scale;
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
            tooltip: 'Fit view',
            icon: const Icon(Icons.fit_screen),
            onPressed: _view.isFit ? null : () => setState(_view.fit),
          ),
          IconButton(
            tooltip: _geo.aspectLocked ? 'Aspect locked to canvas' : 'Lock to canvas aspect',
            icon: Icon(_geo.aspectLocked ? Icons.lock : Icons.lock_open),
            // [G-45] Kill any live drag first: an in-flight corner/move drag would otherwise
            // keep writing geometry derived from before the toggle.
            onPressed: () => setState(() {
              _endCropDrag();
              _geo.toggleAspectLock();
            }),
          ),
          IconButton(
            tooltip: 'Reset crop',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(() {
              // [G-45] Same here: without this the still-held drag resurrects the pre-reset rect.
              _endCropDrag();
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
                      _view.setView(Size(cons.maxWidth, cons.maxHeight));
                      // Raw pointer layer (wheel zoom, right/middle-drag pan) around the gesture
                      // layer (primary-button scale = crop edit or two-finger view; double-tap).
                      // The scale recognizer is restricted to the primary button so a mouse pan
                      // never doubles as a crop edit.
                      return Listener(
                        onPointerDown: _onPointerDown,
                        onPointerMove: _onPointerMove,
                        onPointerUp: _onPointerUp,
                        onPointerCancel: _onPointerUp,
                        onPointerSignal: _onPointerSignal,
                        child: RawGestureDetector(
                          behavior: HitTestBehavior.opaque,
                          gestures: <Type, GestureRecognizerFactory>{
                            ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                              () => ScaleGestureRecognizer(
                                  debugOwner: this, allowedButtonsFilter: (b) => b == kPrimaryButton),
                              (r) => r
                                ..onStart = _onScaleStart
                                ..onUpdate = _onScaleUpdate
                                ..onEnd = _onScaleEnd,
                            ),
                            DoubleTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
                              () => DoubleTapGestureRecognizer(debugOwner: this),
                              (r) => r..onDoubleTapDown = _onDoubleTapDown,
                            ),
                          },
                          child: ClipRect(
                            child: CustomPaint(
                              size: Size(cons.maxWidth, cons.maxHeight),
                              painter: _CropPreviewPainter(
                                image: _frames[_current],
                                geo: _geo,
                                scale: _view.scale,
                                origin: _view.origin,
                                reticleRadius: _reticleRadius,
                              ),
                            ),
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
              const Spacer(),
              Text(
                _view.isFit ? 'Zoom: fit' : 'Zoom ${(_view.zoom * 100).round()}%',
                style: const TextStyle(fontSize: 12, color: Colors.white60),
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
