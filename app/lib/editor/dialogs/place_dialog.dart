// The "Place" step of the import flow (ADR 0019, 2026-09-01): before the engine imports, the user
// drags the scaled import around the canvas — over the start frame's current artwork — and the
// chosen top-left offset (canvas pixels) is what the import commits with. A pre-import page, never
// an editor Draft: no engine draft state, undo and the Journal chapter cut are unchanged.
//
// Since ADR 0030 (2026-09-09) the import may land anywhere in the document's storage area: the
// part outside the canvas is parked in the off-canvas gutter (the Move tool / Overscan view reach
// it) instead of being dropped, and only the part beyond the storage boundary is lost. The page
// shows the dimmed gutter around the canvas — with whatever is already parked there — and fits the
// view to the canvas as before; the gutter overflows the edges and is reached by panning or zooming
// out (the zoom floor is storage-fit).
//
// Gestures mirror the crop editor: one finger drags the import (from anywhere on the view, snapped
// to whole canvas pixels); two fingers / trackpad pan and pinch the view; wheel zooms about the
// cursor; right- or middle-drag pans; double-tap toggles fit <-> 4x; the status row's zoom buttons
// step 1.5x; the app bar resets the view and re-centers the import. X/Y chips type the offset; arrows nudge one canvas pixel.
//
// The status block under the view keeps one height in every state (the panel's height feeds the
// preview's fit scale; a line that appears mid-drag would move the image under the finger): the
// off-canvas and memory notes each own a fixed slot that only changes color and text.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'crop_dialog.dart'
    show CropView, NudgeArrows, ViewZoomControls, fitNoUpscale, kImportModeNative, nudgeKeyHandler, viewGestureHint;
import 'raster_preview.dart';

/// The on-canvas size (canvas pixels) an import will have, mirroring the engine's placement math
/// in `frame_to_storage`: an explicit crop region is placed 1:1 and downscaled (integer
/// cross-multiply) only when larger than the canvas — and not even then under the Native mode
/// code (ADR 0034: the region keeps its size); Stretch fills the canvas; Fit scales by the
/// binding axis (the engine's f32 `round`, mirrored in double — the result feeds the preview only,
/// the engine computes its own size at import time); Native (1:1, ADR 0030) is the source's own size.
({int w, int h}) importPlacedSize({
  required int srcW,
  required int srcH,
  required int canvasW,
  required int canvasH,
  required int mode,
  Rect? crop,
}) {
  if (crop != null) {
    final (rw, rh) = (math.max(1, crop.width.round()), math.max(1, crop.height.round()));
    if (mode == kImportModeNative) return (w: rw, h: rh);
    final (w, h) = fitNoUpscale(rw, rh, canvasW, canvasH);
    return (w: w, h: h);
  }
  switch (mode) {
    case 1: // Stretch
      return (w: canvasW, h: canvasH);
    case 0: // Fit
      final scale = math.min(canvasW / srcW, canvasH / srcH);
      return (w: (srcW * scale).round(), h: (srcH * scale).round());
    case kImportModeNative: // 1:1
      return (w: srcW, h: srcH);
    default: // anchored Crop: a canvas-sized window
      return (w: canvasW, h: canvasH);
  }
}

/// Whether the Place step has anything to place: the result is not exactly the canvas — it
/// leaves canvas uncovered, or (1:1, ADR 0030) overhangs it. Stretch and an exact-size result skip it.
bool placementApplies(({int w, int h}) placed, int canvasW, int canvasH) => placed.w != canvasW || placed.h != canvasH;

/// Upper-bound bytes an import adds to the document: every kept pixel of every source frame at
/// 4 bytes. An upper bound because layer tiles are allocated lazily — fully transparent 32×32
/// tiles of the placed image cost nothing — and because the engine dedups identical tiles.
int importBytesEstimate({required int frames, required Rect kept}) =>
    math.max(0, frames) * kept.width.round() * kept.height.round() * 4;

/// Whether an import of [estimate] bytes on top of [budgetedBytes] would cross the engine's hard
/// memory budget (and so be refused wholesale). Never with an unknown (zero) budget.
bool importMayExceedBudget({required int estimate, required int budgetedBytes, required int hardBudget}) =>
    hardBudget > 0 && budgetedBytes + estimate > hardBudget;

/// Pure placement state: a `w`x`h` image on a `canvasW`x`canvasH` canvas with its top-left at
/// (`x`, `y`), both in canvas pixels, inside a storage area that extends `gutterW`/`gutterH` px
/// beyond each canvas edge (ADR 0030; 0 = no gutter). Starts centered exactly as the engine
/// centers (truncating integer division) and moves freely: what hangs off the canvas but stays
/// within storage is *parked* at import; what lies beyond storage is dropped.
class PlaceGeometry {
  PlaceGeometry({
    required this.canvasW,
    required this.canvasH,
    required this.w,
    required this.h,
    this.gutterW = 0,
    this.gutterH = 0,
  }) {
    center();
  }
  final int canvasW, canvasH, w, h, gutterW, gutterH;
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
  Rect get storageRect => Rect.fromLTWH(
      -gutterW.toDouble(), -gutterH.toDouble(), (canvasW + 2 * gutterW).toDouble(), (canvasH + 2 * gutterH).toDouble());

  static Rect _clip(Rect a, Rect b) {
    final r = a.intersect(b);
    return (r.width <= 0 || r.height <= 0) ? Rect.zero : r;
  }

  /// The part of the image that lands on the canvas (empty when none does).
  Rect get visibleRect => _clip(placedRect, canvasRect);

  /// The part of the image that lands anywhere — on the canvas or parked in the gutter.
  Rect get keptRect => _clip(placedRect, storageRect);

  bool get fullyInside => visibleRect == placedRect;
  bool get fullyOutside => visibleRect == Rect.zero;

  /// Every pixel lands somewhere (nothing beyond the storage boundary).
  bool get fullyKept => keptRect == placedRect;

  /// Nothing lands anywhere: the import lies entirely beyond storage — it cannot be committed.
  bool get nothingKept => keptRect == Rect.zero;

  static int _area(Rect r) => r.width.round() * r.height.round();

  /// Pixels that will be parked off-canvas (kept, but not on the canvas).
  int get parkedPixels => _area(keptRect) - _area(visibleRect);

  /// Pixels beyond the storage boundary, dropped at import.
  int get droppedPixels => _area(placedRect) - _area(keptRect);
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
    this.gutterW = 0,
    this.gutterH = 0,
    this.backdrop,
    this.memBudgetedBytes = 0,
    this.memHardBudget = 0,
  });

  /// The shared decoded-frames preview (the flow owns and disposes it).
  final RasterPreview preview;

  /// The source region being imported (source pixels): the crop rect, or the whole source.
  final Rect srcRect;
  final int canvasW, canvasH;

  /// The off-canvas gutter beyond each canvas edge (ADR 0030): storage = canvas + 2 × gutter.
  final int gutterW, gutterH;

  /// The import's on-canvas size ([importPlacedSize]).
  final int placedW, placedH;

  /// The frame the import starts at (0-based; shown 1-based) — whose composite is [backdrop].
  final int startFrame;

  /// The start frame composited over the whole storage area (canvas + gutter, undimmed), so it
  /// is drawn over `PlaceGeometry.storageRect` — with no gutter that is the canvas itself.
  final ui.Image? backdrop;

  /// The document's current engine-budgeted bytes and the hard budget, for the memory note
  /// (0 = unknown: the note shows the estimate alone and never warns).
  final int memBudgetedBytes, memHardBudget;

  @override
  State<PlacePage> createState() => _PlacePageState();
}

class _PlacePageState extends State<PlacePage> with SingleTickerProviderStateMixin {
  static const double _kWheelZoomStep = 1.2, _kWheelNotchDelta = 60.0;

  late final PlaceGeometry _geo;
  late final CropView _view;
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'PlacePage');
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
    _geo = PlaceGeometry(
      canvasW: widget.canvasW,
      canvasH: widget.canvasH,
      w: widget.placedW,
      h: widget.placedH,
      gutterW: widget.gutterW,
      gutterH: widget.gutterH,
    );
    // Fit frames the canvas alone (the pre-gutter look); the gutter is the pannable overscan band.
    _view = CropView(srcW: widget.canvasW, srcH: widget.canvasH, overscanX: widget.gutterW, overscanY: widget.gutterH);
    _ticker = createTicker(_onTick);
    widget.preview.addListener(_onPreview);
    widget.preview.load();
  }

  @override
  void dispose() {
    widget.preview.removeListener(_onPreview);
    _ticker.dispose();
    _focus.dispose();
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

  /// The nudge arrows and the keyboard arrows (shared with the crop editor): one canvas px,
  /// ending any live drag so a held finger does not keep writing the pre-nudge position.
  void _nudge(int dx, int dy) => setState(() {
        _dragging = false;
        _geo.nudge(dx, dy);
      });

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return KeyEventResult.ignored;
    return nudgeKeyHandler(event, _nudge, shift: HardwareKeyboard.instance.isShiftPressed);
  }

  // ---- the fixed-height status block ----

  /// One status slot: a fixed 20 px row with an icon and a single ellipsized line, so the block
  /// never changes height (see the file header).
  static Widget _slot(IconData icon, String text, Color color) => SizedBox(
        height: 20,
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color)),
          ),
        ]),
      );

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0);

  /// Where the pixels go: on the canvas, parked off-canvas, or dropped beyond storage.
  Widget _placementSlot() {
    if (_geo.nothingKept) {
      return _slot(Icons.block, 'Entirely beyond the storage area — nothing would land.', Colors.amber);
    }
    if (!_geo.fullyKept) {
      return _slot(Icons.warning_amber_rounded,
          '${_geo.droppedPixels} px beyond the storage area are dropped; ${_geo.parkedPixels} px are parked off-canvas.', Colors.amber);
    }
    if (_geo.parkedPixels > 0) {
      return _slot(Icons.open_in_full, '${_geo.parkedPixels} px are parked off-canvas (Move tool / Overscan view reach them).',
          Colors.white60);
    }
    return _slot(Icons.check_circle_outline, 'Fits on the canvas.', Colors.white60);
  }

  /// The memory note (user decision 2026-09-09: a warning only — the engine's budget gate stays
  /// the authority and refuses wholesale; this just says so before a long decode).
  Widget _memorySlot() {
    final p = widget.preview;
    final frames = p.sourceFrames;
    if (!p.loaded || frames <= 0) return _slot(Icons.memory, 'Memory: estimating…', Colors.white38);
    final est = importBytesEstimate(frames: frames, kept: _geo.keptRect);
    final over = importMayExceedBudget(estimate: est, budgetedBytes: widget.memBudgetedBytes, hardBudget: widget.memHardBudget);
    final free = math.max(0, widget.memHardBudget - widget.memBudgetedBytes);
    final text = widget.memHardBudget <= 0
        ? 'Adds up to ~${_mb(est)} MB ($frames ${frames == 1 ? 'frame' : 'frames'}).'
        : over
            ? 'Adds up to ~${_mb(est)} MB, over the ${_mb(free)} MB left — the import may be refused.'
            : 'Adds up to ~${_mb(est)} MB of the ${_mb(free)} MB left.';
    return _slot(over ? Icons.warning_amber_rounded : Icons.memory, text, over ? Colors.amber : Colors.white60);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Place'),
          actions: [
            IconButton(
              tooltip: 'Fit to screen',
              icon: const Icon(Icons.fit_screen),
              onPressed: _view.isHome ? null : () => setState(_view.fit),
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
                    // Short (2026-09-15: the long sentence was cut off next to the zoom cluster
                    // on a phone); the tooltip carries the sentence.
                    child: Tooltip(
                      message: 'Preview truncated: the full animation still imports.',
                      child: Text('(preview cut)', style: TextStyle(fontSize: 11, color: Colors.white54)),
                    ),
                  ),
                const Spacer(),
                ViewZoomControls(view: _view, onChanged: () => setState(() {})),
              ]),
              viewGestureHint('moves the import'),
              const SizedBox(height: 4),
              Row(children: [
                ActionChip(label: Text('X ${_geo.x}'), onPressed: () => _editField('X', _geo.x, (v) => _geo.x = v)),
                const SizedBox(width: 6),
                ActionChip(label: Text('Y ${_geo.y}'), onPressed: () => _editField('Y', _geo.y, (v) => _geo.y = v)),
                const Spacer(),
                NudgeArrows(onNudge: _nudge),
              ]),
              const SizedBox(height: 6),
              SizedBox(
                height: 18,
                child: Text(
                  'Import ${_geo.w} × ${_geo.h} px at (${_geo.x}, ${_geo.y}) on the ${widget.canvasW}×${widget.canvasH} canvas. '
                  'Backdrop: frame ${widget.startFrame + 1}.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
              _placementSlot(),
              _memorySlot(),
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
                onPressed: p.loaded && !_geo.nothingKept ? () => Navigator.pop(context, (_geo.x, _geo.y)) : null,
                child: const Text('Import'),
              ),
            ]),
          ),
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

  /// The engine's overscan-view wash (`dim_gutter`: black at alpha 130), so the gutter reads the
  /// same here as in the editor.
  static const Color _gutterWash = Color(0x82000000);

  Rect _toScreen(Rect r) => Rect.fromLTWH(origin.dx + r.left * scale, origin.dy + r.top * scale, r.width * scale, r.height * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = _toScreen(geo.canvasRect);
    final storageRect = _toScreen(geo.storageRect);
    // The storage area: flat dark ground (no checker — transparency is only meaningful on the
    // canvas), the checker under the canvas, then the storage-sized backdrop over both.
    canvas.save();
    canvas.clipRect(storageRect);
    canvas.drawRect(storageRect, Paint()..color = const Color(0xFF2E3034));
    const cell = 8.0;
    final dark = Paint()..color = const Color(0xFF3A3D42);
    final light = Paint()..color = const Color(0xFF50545A);
    canvas.drawRect(canvasRect, dark);
    for (var yy = canvasRect.top; yy < canvasRect.bottom; yy += cell) {
      final row = ((yy - canvasRect.top) / cell).floor();
      for (var xx = canvasRect.left + (row.isOdd ? cell : 0); xx < canvasRect.right; xx += cell * 2) {
        canvas.drawRect(Rect.fromLTWH(xx, yy, cell, cell).intersect(canvasRect), light);
      }
    }
    if (backdrop != null) {
      canvas.drawImageRect(
          backdrop!,
          Rect.fromLTWH(0, 0, backdrop!.width.toDouble(), backdrop!.height.toDouble()),
          storageRect,
          Paint()..filterQuality = FilterQuality.none);
    }
    // Dim the gutter (storage minus canvas) so the canvas stands out, as the editor's overscan view does.
    if (storageRect != canvasRect) {
      final gutter = Path()
        ..addRect(storageRect)
        ..addRect(canvasRect)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(gutter, Paint()..color = _gutterWash);
    }
    canvas.restore();

    // The import, at its placed size; nearest-neighbor keeps pixel art crisp.
    final placed = _toScreen(geo.placedRect);
    canvas.drawImageRect(frame, srcRect, placed, Paint()..filterQuality = FilterQuality.none);
    // Shade the part of the import beyond the storage area (dropped at import). The part over the
    // gutter is kept, so it stays unshaded — the dimmed ground under it already says "off-canvas".
    final kept = geo.keptRect;
    if (kept != geo.placedRect) {
      final shade = Path()..addRect(placed);
      if (kept != Rect.zero) shade.addRect(_toScreen(kept));
      shade.fillType = PathFillType.evenOdd;
      canvas.drawPath(shade, Paint()..color = const Color(0xAA000000));
    }

    // Outlines: storage (faint), canvas (thin, white) and import (amber).
    if (storageRect != canvasRect) {
      canvas.drawRect(
          storageRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white24);
    }
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
