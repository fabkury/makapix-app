// The contact sheet (ADR 0031): a lazily built grid of FrameTiles and every gesture on it.
//
// Touch: tap toggles (instantly — no onDoubleTap, which would delay every tap ~300 ms; a
// second tap on the same tile inside the double-tap window is the Go-to); a slide that starts
// mostly SIDEWAYS is a SWEEP that paints the first tile's new state onto every tile the finger
// crosses (row-major span between the last and current tile, so a fast diagonal skips
// nothing) with edge auto-scroll, while a slide that starts up/down scrolls as usual — the
// horizontal-drag recognizer simply competes with the grid's vertical one in the arena;
// long-press and a right-click open the tile menu. Mouse: a drag that starts on empty grid
// space is a rubber-band; two touch pointers pinch the column count — and from the moment a
// second finger lands until every finger lifts, no tile gesture counts: a sweep already
// begun is cancelled (the page restores the selection), and the fingers' taps and holds are
// ignored, so a pinch never selects. The scroll view keeps the app's own overscroll behavior
// (no ScrollConfiguration override).

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'frame_grid_geometry.dart';
import 'frame_model.dart';
import 'frame_selection.dart';
import 'frame_tile.dart';

const double _kEdgeBand = 48;
const double _kEdgeStep = 12;
const Duration _kEdgeTick = Duration(milliseconds: 16);

class FrameGrid extends StatefulWidget {
  const FrameGrid({
    super.key,
    required this.frames,
    required this.selection,
    required this.activeIndex,
    required this.columns,
    required this.thumbAspect,
    required this.scale,
    required this.controller,
    required this.thumbFor,
    required this.requestThumb,
    required this.onTap,
    required this.onSweepStart,
    required this.onSweepAdd,
    required this.onSweepCancel,
    required this.onGoTo,
    required this.onTileMenu,
    required this.onBand,
    required this.onColumnsChanged,
  });

  final List<FrameInfo> frames;
  final FrameSelection selection;
  final int activeIndex;
  final int columns;
  final double thumbAspect;
  final double scale;
  final ScrollController controller;

  final ui.Image? Function(int id) thumbFor;
  final void Function(int id, int index) requestThumb;

  /// A plain tap: toggle, or a Shift-range when [range] is true.
  final void Function(int id, {required bool range}) onTap;

  /// A sweep begins on [id]: the page flips it and remembers the new state to paint.
  final void Function(int id) onSweepStart;

  /// Tiles the sweep crossed since the last sample; the page paints the remembered state.
  final void Function(Iterable<int> ids) onSweepAdd;

  /// A second finger landed mid-sweep: the page puts the selection back as it was before.
  final VoidCallback onSweepCancel;
  final void Function(int index) onGoTo;
  final void Function(int index) onTileMenu;

  /// A rubber-band update: the tiles inside it; [additive] when Primary is held; [done] on release.
  final void Function(Set<int> ids, {required bool additive, required bool done}) onBand;
  final ValueChanged<int> onColumnsChanged;

  @override
  State<FrameGrid> createState() => FrameGridState();
}

class FrameGridState extends State<FrameGrid> {
  final GlobalKey _viewportKey = GlobalKey();
  FrameGridGeometry? _geometry;
  double _viewportHeight = 0;

  // Manual double-tap (the second tap on the same tile inside the window is Go-to).
  int? _lastTapIndex;
  DateTime? _lastTapAt;

  // Sweep.
  bool _sweeping = false;
  int _sweepLast = -1;
  Offset? _sweepGlobal;
  Timer? _edgeTimer;

  // Rubber-band (mouse).
  int? _bandPointer;
  Offset? _bandOrigin; // content coordinates
  Offset? _bandCurrent;

  // Pinch (touch).
  final Map<int, Offset> _touch = {};
  double? _pinchStart;

  /// Two fingers were down at some point in the current touch sequence. Set when the second
  /// lands, cleared only when the NEXT sequence begins (not on the last lift: a tile's onTap
  /// fires after the Listener has already seen that same pointer-up), so the fingers' taps,
  /// holds, and slides are all ignored for the rest of the sequence.
  bool _multiTouch = false;

  @override
  void dispose() {
    _edgeTimer?.cancel();
    super.dispose();
  }

  /// The inclusive index range currently on screen, or `(0, -1)`.
  (int, int) visibleRange() {
    final g = _geometry;
    if (g == null || !widget.controller.hasClients) return (0, -1);
    return g.visibleRange(widget.controller.offset, _viewportHeight, widget.frames.length);
  }

  /// Scroll just enough that tile [index] is fully visible (no-op when it already is).
  void revealIndex(int index) {
    final g = _geometry;
    if (g == null || !widget.controller.hasClients || index < 0 || index >= widget.frames.length) return;
    final r = g.rectOf(index);
    final top = widget.controller.offset;
    final bottom = top + _viewportHeight;
    double? target;
    if (r.top < top) target = r.top - g.padding.top;
    if (r.bottom > bottom) target = r.bottom - _viewportHeight + g.padding.bottom;
    if (target == null) return;
    final max = widget.controller.position.maxScrollExtent;
    widget.controller.jumpTo(target.clamp(0.0, math.max(0.0, max)));
  }

  Offset? _toLocal(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  int? _indexAtGlobal(Offset global) {
    final g = _geometry;
    final local = _toLocal(global);
    if (g == null || local == null || !widget.controller.hasClients) return null;
    return g.indexAt(local, widget.controller.offset, widget.frames.length);
  }

  // ---- taps ----

  void _tapTile(int index) {
    if (_multiTouch) return;
    final now = DateTime.now();
    if (_lastTapIndex == index && _lastTapAt != null && now.difference(_lastTapAt!) < kDoubleTapTimeout) {
      _lastTapIndex = null;
      _lastTapAt = null;
      widget.onGoTo(index);
      return;
    }
    _lastTapIndex = index;
    _lastTapAt = now;
    widget.onTap(widget.frames[index].id, range: HardwareKeyboard.instance.isShiftPressed);
  }

  // ---- sweep ----

  void _sweepStart(int index, Offset global) {
    if (_multiTouch) return;
    _sweeping = true;
    _sweepLast = index;
    _sweepGlobal = global;
    HapticFeedback.selectionClick();
    widget.onSweepStart(widget.frames[index].id);
    _edgeTimer?.cancel();
    _edgeTimer = Timer.periodic(_kEdgeTick, (_) => _edgeScroll());
    _sweepSample(); // the drag start already sits past the touch slop, maybe on a neighbor
  }

  void _sweepMove(Offset global) {
    if (!_sweeping) return;
    _sweepGlobal = global;
    _sweepSample();
  }

  void _sweepSample() {
    final global = _sweepGlobal;
    if (global == null) return;
    final i = _indexAtGlobal(global);
    if (i == null || i == _sweepLast) return;
    final lo = math.min(i, _sweepLast);
    final hi = math.max(i, _sweepLast);
    _sweepLast = i;
    widget.onSweepAdd([for (var k = lo; k <= hi; k++) widget.frames[k].id]);
  }

  void _sweepEnd() {
    _sweeping = false;
    _sweepGlobal = null;
    _edgeTimer?.cancel();
    _edgeTimer = null;
  }

  void _edgeScroll() {
    final global = _sweepGlobal ?? (_bandPointer != null ? _bandGlobal : null);
    final local = global == null ? null : _toLocal(global);
    if (local == null || !widget.controller.hasClients) return;
    final pos = widget.controller.position;
    double delta = 0;
    if (local.dy < _kEdgeBand) delta = -_kEdgeStep;
    if (local.dy > _viewportHeight - _kEdgeBand) delta = _kEdgeStep;
    if (delta == 0) return;
    final next = (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (next == pos.pixels) return;
    widget.controller.jumpTo(next);
    if (_sweeping) _sweepSample();
    if (_bandPointer != null) _bandUpdate();
  }

  // ---- rubber-band ----

  Offset? _bandGlobal;

  void _pointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      if (_touch.isEmpty) _multiTouch = false; // a fresh sequence
      _touch[e.pointer] = e.position;
      if (_touch.length == 2) {
        _multiTouch = true;
        if (_sweeping) {
          _sweepEnd();
          widget.onSweepCancel(); // the first finger's drift was the pinch's opening, not a sweep
        }
        _pinchStart = _touchDistance();
        setState(() {}); // switch physics off while pinching
      }
      return;
    }
    if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryButton) return;
    if (_indexAtGlobal(e.position) != null) return; // a tile: the tile's own gestures own it
    final g = _geometry;
    final local = _toLocal(e.position);
    if (g == null || local == null || !widget.controller.hasClients) return;
    _bandPointer = e.pointer;
    _bandGlobal = e.position;
    _bandOrigin = local + Offset(0, widget.controller.offset);
    _bandCurrent = _bandOrigin;
    _edgeTimer?.cancel();
    _edgeTimer = Timer.periodic(_kEdgeTick, (_) => _edgeScroll());
    setState(() {});
  }

  void _pointerMove(PointerMoveEvent e) {
    if (_touch.containsKey(e.pointer)) {
      _touch[e.pointer] = e.position;
      _pinchSample();
      return;
    }
    if (e.pointer != _bandPointer) return;
    _bandGlobal = e.position;
    _bandUpdate();
  }

  void _bandUpdate() {
    final g = _geometry;
    final global = _bandGlobal;
    final local = global == null ? null : _toLocal(global);
    if (g == null || local == null || _bandOrigin == null || !widget.controller.hasClients) return;
    _bandCurrent = local + Offset(0, widget.controller.offset);
    final rect = Rect.fromPoints(_bandOrigin!, _bandCurrent!);
    final hits = g.indicesInRect(rect, widget.frames.length).map((i) => widget.frames[i].id).toSet();
    final hk = HardwareKeyboard.instance;
    widget.onBand(hits, additive: hk.isControlPressed || hk.isMetaPressed, done: false);
    setState(() {});
  }

  void _pointerUp(PointerEvent e) {
    if (_touch.remove(e.pointer) != null) {
      if (_touch.length < 2) {
        _pinchStart = null;
        setState(() {});
      }
      return;
    }
    if (e.pointer != _bandPointer) return;
    final g = _geometry;
    if (g != null && _bandOrigin != null && _bandCurrent != null) {
      final rect = Rect.fromPoints(_bandOrigin!, _bandCurrent!);
      final hits = g.indicesInRect(rect, widget.frames.length).map((i) => widget.frames[i].id).toSet();
      final hk = HardwareKeyboard.instance;
      widget.onBand(hits, additive: hk.isControlPressed || hk.isMetaPressed, done: true);
    }
    _bandPointer = null;
    _bandOrigin = null;
    _bandCurrent = null;
    _bandGlobal = null;
    _edgeTimer?.cancel();
    _edgeTimer = null;
    setState(() {});
  }

  // ---- pinch ----

  double _touchDistance() {
    final pts = _touch.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  void _pinchSample() {
    final start = _pinchStart;
    if (_touch.length != 2 || start == null || start <= 0) return;
    final d = _touchDistance();
    final next = FrameGridGeometry.columnsForPinch(widget.columns, d / start);
    if (next != widget.columns) {
      _pinchStart = d; // re-anchor for the next step
      HapticFeedback.selectionClick();
      widget.onColumnsChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final width = constraints.maxWidth;
      _viewportHeight = constraints.maxHeight;
      final g = FrameGridGeometry(
        gridWidth: width,
        columns: widget.columns,
        thumbAspect: widget.thumbAspect,
        labelBand: kFrameTileLabelBand * widget.scale + 6, // + the tile's border and padding
      );
      _geometry = g;
      final pinching = _touch.length >= 2;
      final grid = GridView.builder(
        key: _viewportKey,
        controller: widget.controller,
        padding: g.padding,
        physics: pinching ? const NeverScrollableScrollPhysics() : null,
        addAutomaticKeepAlives: false,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: g.columns,
          mainAxisExtent: g.cellHeight,
          crossAxisSpacing: g.spacing,
          mainAxisSpacing: g.spacing,
        ),
        itemCount: widget.frames.length,
        itemBuilder: (_, i) {
          final f = widget.frames[i];
          final img = widget.thumbFor(f.id);
          if (img == null) widget.requestThumb(f.id, i);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tapTile(i),
            onSecondaryTapUp: (_) => widget.onTileMenu(i),
            onLongPress: () {
              if (!_multiTouch) widget.onTileMenu(i);
            },
            onHorizontalDragStart: (d) => _sweepStart(i, d.globalPosition),
            onHorizontalDragUpdate: (d) => _sweepMove(d.globalPosition),
            onHorizontalDragEnd: (_) => _sweepEnd(),
            onHorizontalDragCancel: _sweepEnd,
            child: FrameTile(
              image: img,
              aspect: widget.thumbAspect,
              number: i + 1,
              durationMs: f.durationMs,
              active: i == widget.activeIndex,
              selected: widget.selection.contains(f.id),
              scale: widget.scale,
            ),
          );
        },
      );
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        child: Stack(fit: StackFit.expand, children: [
          grid,
          if (_bandOrigin != null && _bandCurrent != null && widget.controller.hasClients)
            IgnorePointer(
              child: CustomPaint(
                painter: _BandPainter(
                  Rect.fromPoints(_bandOrigin!, _bandCurrent!).shift(Offset(0, -widget.controller.offset)),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

class _BandPainter extends CustomPainter {
  const _BandPainter(this.rect);
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = const Color(0x33FFC107));
    canvas.drawRect(
      rect,
      Paint()
        ..color = kFramesSelect
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.rect != rect;
}
