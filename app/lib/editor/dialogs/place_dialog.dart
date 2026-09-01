// The "Place" step of the import flow (ADR 0019, 2026-09-01): before the engine imports, the user
// drags the scaled import around the canvas — over the start frame's current artwork — and the
// chosen top-left offset (canvas pixels) is what the import commits with. A pre-import page, never
// an editor Draft: no engine draft state, undo and the Journal chapter cut are unchanged.
//
// Gestures mirror the crop editor: one finger drags the import (from anywhere on the view, snapped
// to whole canvas pixels); two fingers / trackpad pan and pinch the view; wheel zooms about the
// cursor; right- or middle-drag pans; double-tap toggles fit <-> 4x; the app bar resets the view
// and re-centers the import. X/Y chips type the offset; arrows nudge one canvas pixel.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'crop_dialog.dart' show CropView, fitNoUpscale;
import 'raster_preview.dart';

/// The on-canvas size (canvas pixels) an import will have, mirroring the engine's placement math
/// in `frame_to_buffer`: an explicit crop region is placed 1:1 and downscaled (integer
/// cross-multiply) only when larger than the canvas; Stretch fills the canvas; Fit scales by the
/// binding axis (the engine's f32 `round`, mirrored in double — the result feeds the preview only,
/// the engine computes its own size at import time).
({int w, int h}) importPlacedSize({
  required int srcW,
  required int srcH,
  required int canvasW,
  required int canvasH,
  required int mode,
  Rect? crop,
}) {
  if (crop != null) {
    final (w, h) = fitNoUpscale(math.max(1, crop.width.round()), math.max(1, crop.height.round()), canvasW, canvasH);
    return (w: w, h: h);
  }
  switch (mode) {
    case 1: // Stretch
      return (w: canvasW, h: canvasH);
    case 0: // Fit
      final scale = math.min(canvasW / srcW, canvasH / srcH);
      return (w: (srcW * scale).round(), h: (srcH * scale).round());
    default: // anchored Crop: a canvas-sized window
      return (w: canvasW, h: canvasH);
  }
}

/// Whether the Place step has anything to place: the result leaves canvas uncovered in some
/// dimension. Stretch and an exact-size result skip it.
bool placementApplies(({int w, int h}) placed, int canvasW, int canvasH) => placed.w < canvasW || placed.h < canvasH;

/// Pure placement state: a `w`x`h` image on a `canvasW`x`canvasH` canvas with its top-left at
/// (`x`, `y`), both in canvas pixels. Starts centered exactly as the engine centers (truncating
/// integer division), moves freely (off-canvas allowed — the outside is dropped at import).
class PlaceGeometry {
  PlaceGeometry({required this.canvasW, required this.canvasH, required this.w, required this.h}) {
    center();
  }
  final int canvasW, canvasH, w, h;
  int x = 0, y = 0;

  void center() {
    x = (canvasW - w) ~/ 2;
    y = (canvasH - h) ~/ 2;
  }

  void nudge(int dx, int dy) {
    x += dx;
    y += dy;
  }

  Rect get placedRect => Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
  Rect get canvasRect => Rect.fromLTWH(0, 0, canvasW.toDouble(), canvasH.toDouble());

  /// The part of the image that lands on the canvas (empty when none does).
  Rect get visibleRect {
    final r = placedRect.intersect(canvasRect);
    return (r.width <= 0 || r.height <= 0) ? Rect.zero : r;
  }

  bool get fullyInside => visibleRect == placedRect;
  bool get fullyOutside => visibleRect == Rect.zero;
}

class PlacePage extends StatefulWidget {
  const PlacePage({
    super.key,
    required this.preview,
    required this.srcRect,
    required this.canvasW,
    required this.canvasH,
    required this.placedW,
    required this.placedH,
    required this.startFrame,
    this.backdrop,
  });

  /// The shared decoded-frames preview (the flow owns and disposes it).
  final RasterPreview preview;

  /// The source region being imported (source pixels): the crop rect, or the whole source.
  final Rect srcRect;
  final int canvasW, canvasH;

  /// The import's on-canvas size ([importPlacedSize]).
  final int placedW, placedH;

  /// The frame the import starts at (0-based; shown 1-based) — whose composite is [backdrop].
  final int startFrame;
  final ui.Image? backdrop;

  @override
  State<PlacePage> createState() => _PlacePageState();
}

class _PlacePageState extends State<PlacePage> with SingleTickerProviderStateMixin {
  static const double _kWheelZoomStep = 1.2, _kWheelNotchDelta = 60.0;

  late final PlaceGeometry _geo;
  late final CropView _view;
  late final Ticker _ticker;
  int _current = 0;
  bool _playing = false;
  Duration _last = Duration.zero;
  Duration _acc = Duration.zero;

  // One-finger import drag (snapshot at start; deltas are rounded to whole canvas pixels).
  bool _dragging = false;
  Offset _startLocal = Offset.zero;
  int _startX = 0, _startY = 0;
  // View gesture (two fingers / trackpad), incremental pinch — see the crop editor for why.
  bool _viewGesture = false;
  double _lastGestureScale = 1;
  int _lastPointerCount = 0;
  bool _mousePan = false;
  Offset _mouseLast = Offset.zero;

  @override
  void initState() {
    super.initState();
    _geo = PlaceGeometry(canvasW: widget.canvasW, canvasH: widget.canvasH, w: widget.placedW, h: widget.placedH);
    _view = CropView(srcW: widget.canvasW, srcH: widget.canvasH);
    _ticker = createTicker(_onTick);
    widget.preview.addListener(_onPreview);
    widget.preview.load();
  }

  @override
  void dispose() {
    widget.preview.removeListener(_onPreview);
    _ticker.dispose();
    super.dispose();
  }

  void _onPreview() {
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    _acc += dt;
    final (cur, left) = widget.preview.advance(_current, _acc);
    _acc = left;
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

  // ---- gestures (the crop editor's layer, with a one-finger import drag) ----

  void _onScaleStart(ScaleStartDetails d) {
    if (_mousePan) return;
    _viewGesture = d.pointerCount >= 2 || d.kind == PointerDeviceKind.trackpad;
    if (_viewGesture) {
      _dragging = false;
      _lastGestureScale = 1;
      _lastPointerCount = d.pointerCount;
      return;
    }
    _dragging = true;
    _startLocal = d.localFocalPoint;
    _startX = _geo.x;
    _startY = _geo.y;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_mousePan) return;
    if (!_viewGesture && d.pointerCount >= 2) {
      _viewGesture = true;
      _dragging = false;
      _lastGestureScale = d.scale;
      _lastPointerCount = d.pointerCount;
    }
    if (_viewGesture) {
      if (d.pointerCount != _lastPointerCount) {
        _lastPointerCount = d.pointerCount;
        _lastGestureScale = d.scale;
      }
      final ratio = _lastGestureScale > 0 ? d.scale / _lastGestureScale : 1.0;
      _lastGestureScale = d.scale;
      setState(() {
        if (ratio != 1) _view.zoomAt(d.localFocalPoint, _view.zoom * ratio);
        _view.panBy(d.focalPointDelta);
      });
      return;
    }
    if (_dragging) {
      final dx = ((d.localFocalPoint.dx - _startLocal.dx) / _view.scale).round();
      final dy = ((d.localFocalPoint.dy - _startLocal.dy) / _view.scale).round();
      setState(() {
        _geo.x = _startX + dx;
        _geo.y = _startY + dy;
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _viewGesture = false;
    _dragging = false;
  }

  void _onDoubleTapDown(TapDownDetails d) => setState(() => _view.toggleDoubleTap(d.localPosition));

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse && (e.buttons & (kSecondaryButton | kMiddleMouseButton)) != 0) {
      _mousePan = true;
      _mouseLast = e.localPosition;
      _dragging = false;
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

  // ---- numeric entry ----

  Future<void> _editField(String label, int current, ValueChanged<int> set) async {
    final ctrl = TextEditingController(text: '$current');
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label (canvas px)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (t) => Navigator.pop(ctx, int.tryParse(t.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())), child: const Text('Set')),
        ],
      ),
    );
    if (v != null && mounted) setState(() => set(v));
  }

  Widget _nudge(IconData icon, int dx, int dy, String tip) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 20),
        onPressed: () => setState(() => _geo.nudge(dx, dy)),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final clipped = !_geo.fullyInside;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Place'),
        actions: [
          IconButton(
            tooltip: 'Fit view',
            icon: const Icon(Icons.fit_screen),
            onPressed: _view.isFit ? null : () => setState(_view.fit),
          ),
          IconButton(
            tooltip: 'Center the import',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () => setState(() {
              _dragging = false;
              _geo.center();
            }),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: p.loadError
              ? const Center(child: Text('Could not decode this image.'))
              : !p.loaded
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(builder: (ctx, cons) {
                      _view.setView(Size(cons.maxWidth, cons.maxHeight));
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
                              painter: _PlacePainter(
                                frame: p.frames[_current],
                                srcRect: widget.srcRect,
                                backdrop: widget.backdrop,
                                geo: _geo,
                                scale: _view.scale,
                                origin: _view.origin,
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
                onPressed: p.animated ? _togglePlay : null,
              ),
              Text(p.animated ? 'Frame ${_current + 1} / ${p.frames.length}' : 'Static',
                  style: const TextStyle(fontSize: 13)),
              if (p.truncated)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('(preview truncated — full animation still imports)',
                      style: TextStyle(fontSize: 11, color: Colors.white54)),
                ),
              const Spacer(),
              Text(_view.isFit ? 'Zoom: fit' : 'Zoom ${(_view.zoom * 100).round()}%',
                  style: const TextStyle(fontSize: 12, color: Colors.white60)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              ActionChip(label: Text('X ${_geo.x}'), onPressed: () => _editField('X', _geo.x, (v) => _geo.x = v)),
              const SizedBox(width: 6),
              ActionChip(label: Text('Y ${_geo.y}'), onPressed: () => _editField('Y', _geo.y, (v) => _geo.y = v)),
              const Spacer(),
              _nudge(Icons.keyboard_arrow_left, -1, 0, 'Left 1 px'),
              _nudge(Icons.keyboard_arrow_up, 0, -1, 'Up 1 px'),
              _nudge(Icons.keyboard_arrow_down, 0, 1, 'Down 1 px'),
              _nudge(Icons.keyboard_arrow_right, 1, 0, 'Right 1 px'),
            ]),
            const SizedBox(height: 6),
            Text(
              'Import ${_geo.w} × ${_geo.h} px at (${_geo.x}, ${_geo.y}) on the ${widget.canvasW}×${widget.canvasH} canvas. '
              'Backdrop: frame ${widget.startFrame + 1}.'
              '${clipped ? _geo.fullyOutside ? ' The import is entirely off the canvas — nothing would land.' : ' The part outside the canvas is dropped.' : ''}',
              style: TextStyle(fontSize: 12, color: clipped ? Colors.amber : Colors.white60),
            ),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: p.loaded && !_geo.fullyOutside ? () => Navigator.pop(context, (_geo.x, _geo.y)) : null,
              child: const Text('Import'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PlacePainter extends CustomPainter {
  final ui.Image frame;
  final Rect srcRect;
  final ui.Image? backdrop;
  final PlaceGeometry geo;
  final double scale;
  final Offset origin;
  _PlacePainter({
    required this.frame,
    required this.srcRect,
    required this.backdrop,
    required this.geo,
    required this.scale,
    required this.origin,
  });

  Rect _toScreen(Rect r) => Rect.fromLTWH(origin.dx + r.left * scale, origin.dy + r.top * scale, r.width * scale, r.height * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = _toScreen(geo.canvasRect);
    // Checker under the canvas (screen-space cells, clipped to the canvas).
    canvas.save();
    canvas.clipRect(canvasRect);
    const cell = 8.0;
    final dark = Paint()..color = const Color(0xFF3A3D42);
    final light = Paint()..color = const Color(0xFF50545A);
    canvas.drawRect(canvasRect, dark);
    for (var yy = canvasRect.top; yy < canvasRect.bottom; yy += cell) {
      final row = ((yy - canvasRect.top) / cell).floor();
      for (var xx = canvasRect.left + (row.isOdd ? cell : 0); xx < canvasRect.right; xx += cell * 2) {
        canvas.drawRect(Rect.fromLTWH(xx, yy, cell, cell), light);
      }
    }
    if (backdrop != null) {
      canvas.drawImageRect(
          backdrop!,
          Rect.fromLTWH(0, 0, backdrop!.width.toDouble(), backdrop!.height.toDouble()),
          canvasRect,
          Paint()..filterQuality = FilterQuality.none);
    }
    canvas.restore();

    // The import, at its placed size; nearest-neighbor keeps pixel art crisp.
    final placed = _toScreen(geo.placedRect);
    canvas.drawImageRect(frame, srcRect, placed, Paint()..filterQuality = FilterQuality.none);
    // Shade the part of the import that hangs off the canvas (it is dropped at import).
    final visible = geo.visibleRect;
    final shade = Path()..addRect(placed);
    if (visible != Rect.zero) shade.addRect(_toScreen(visible));
    shade.fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = const Color(0xAA000000));

    // Outlines: canvas (thin, white) and import (amber).
    canvas.drawRect(
        canvasRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white54);
    canvas.drawRect(
        placed,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.amber);
  }

  @override
  bool shouldRepaint(_PlacePainter old) =>
      old.frame != frame ||
      old.backdrop != backdrop ||
      old.scale != scale ||
      old.origin != origin ||
      old.geo.x != geo.x ||
      old.geo.y != geo.y ||
      old.srcRect != srcRect;
}
