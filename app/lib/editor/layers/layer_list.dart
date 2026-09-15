// The stack list (ADR 0033): a lazily built list of LayerRowTiles, top of the stack first,
// and every gesture on it — the Frames grid's rules over rows.
//
// Touch: tap toggles (instantly — no onDoubleTap; a second tap on the same row inside the
// double-tap window is Make active); a slide that starts mostly SIDEWAYS is a SWEEP that paints
// the first row's new state onto every row the finger crosses (the span between the last and
// current row) with edge auto-scroll, while a slide that starts up/down scrolls as usual — the
// horizontal-drag recognizer competes with the list's vertical one in the arena; long-press and
// a right-click open the row menu. From the moment a second finger lands until every finger
// lifts, no row gesture counts: a sweep already begun is cancelled (the page restores the
// selection), so a pinch or a two-finger scroll never selects.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../frames/frame_selection.dart';
import 'layer_model.dart';
import 'layer_row.dart';

const double _kEdgeBand = 48;
const double _kEdgeStep = 12;
const Duration _kEdgeTick = Duration(milliseconds: 16);
const double _kRowGap = 4;
const double _kPadV = 8;
const double _kPadH = 8;

class LayerList extends StatefulWidget {
  const LayerList({
    super.key,
    required this.rows,
    required this.selection,
    required this.activeIndex,
    required this.rowHeight,
    required this.thumbAspect,
    required this.scale,
    required this.controller,
    required this.thumbFor,
    required this.requestThumb,
    required this.onTap,
    required this.onSweepStart,
    required this.onSweepAdd,
    required this.onSweepCancel,
    required this.onActivate,
    required this.onRowMenu,
  });

  /// Engine order (bottom first); the list shows the last row on top.
  final List<LayerRow> rows;
  final FrameSelection selection;

  /// Engine index of the active layer.
  final int activeIndex;
  final double rowHeight;
  final double thumbAspect;
  final double scale;
  final ScrollController controller;

  final ui.Image? Function(int id) thumbFor;
  final void Function(int id, int index) requestThumb;

  /// A plain tap: toggle, or a Shift-range when [range] is true.
  final void Function(int id, {required bool range}) onTap;
  final void Function(int id) onSweepStart;
  final void Function(Iterable<int> ids) onSweepAdd;
  final VoidCallback onSweepCancel;

  /// Double-tap: make the layer at engine [index] active.
  final void Function(int index) onActivate;
  final void Function(int index) onRowMenu;

  @override
  State<LayerList> createState() => LayerListState();
}

class LayerListState extends State<LayerList> {
  final GlobalKey _viewportKey = GlobalKey();
  double _viewportHeight = 0;

  int? _lastTapIndex;
  DateTime? _lastTapAt;

  bool _sweeping = false;
  int _sweepLast = -1; // display position
  Offset? _sweepGlobal;
  Timer? _edgeTimer;

  final Set<int> _touch = {};
  bool _multiTouch = false;

  double get _extent => widget.rowHeight + _kRowGap;
  int get _n => widget.rows.length;

  /// Display position (0 = top) ↔ engine index.
  int _engineOf(int pos) => _n - 1 - pos;
  int _posOf(int engineIndex) => _n - 1 - engineIndex;

  @override
  void dispose() {
    _edgeTimer?.cancel();
    super.dispose();
  }

  /// The inclusive engine-index range currently on screen, or `(0, -1)`.
  (int, int) visibleRange() {
    if (!widget.controller.hasClients || _n == 0) return (0, -1);
    final top = widget.controller.offset;
    final firstPos = ((top - _kPadV) / _extent).floor().clamp(0, _n - 1);
    final lastPos = ((top + _viewportHeight - _kPadV) / _extent).ceil().clamp(0, _n - 1);
    return (_engineOf(lastPos), _engineOf(firstPos));
  }

  /// Scroll just enough that the row of engine [index] is fully visible.
  void revealIndex(int index) {
    if (!widget.controller.hasClients || index < 0 || index >= _n) return;
    final pos = _posOf(index);
    final rTop = _kPadV + pos * _extent;
    final rBottom = rTop + widget.rowHeight;
    final top = widget.controller.offset;
    final bottom = top + _viewportHeight;
    double? target;
    if (rTop < top) target = rTop - _kPadV;
    if (rBottom > bottom) target = rBottom - _viewportHeight + _kPadV;
    if (target == null) return;
    final max = widget.controller.position.maxScrollExtent;
    widget.controller.jumpTo(target.clamp(0.0, math.max(0.0, max)));
  }

  Offset? _toLocal(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  // ---- taps ----

  void _tapRow(int pos) {
    if (_multiTouch) return;
    final now = DateTime.now();
    if (_lastTapIndex == pos && _lastTapAt != null && now.difference(_lastTapAt!) < kDoubleTapTimeout) {
      _lastTapIndex = null;
      _lastTapAt = null;
      widget.onActivate(_engineOf(pos));
      return;
    }
    _lastTapIndex = pos;
    _lastTapAt = now;
    widget.onTap(widget.rows[_engineOf(pos)].id, range: HardwareKeyboard.instance.isShiftPressed);
  }

  // ---- sweep ----

  void _sweepStart(int pos, Offset global) {
    if (_multiTouch) return;
    _sweeping = true;
    _sweepLast = pos;
    _sweepGlobal = global;
    HapticFeedback.selectionClick();
    widget.onSweepStart(widget.rows[_engineOf(pos)].id);
    _edgeTimer?.cancel();
    _edgeTimer = Timer.periodic(_kEdgeTick, (_) => _edgeScroll());
    _sweepSample();
  }

  void _sweepMove(Offset global) {
    if (!_sweeping) return;
    _sweepGlobal = global;
    _sweepSample();
  }

  void _sweepSample() {
    final global = _sweepGlobal;
    if (global == null) return;
    final local = _toLocal(global);
    if (local == null || !widget.controller.hasClients) return;
    // Past the ends of the list the finger still means "up to the edge".
    final y = local.dy + widget.controller.offset - _kPadV;
    final pos = (y / _extent).floor().clamp(0, _n - 1);
    if (pos == _sweepLast) return;
    final lo = math.min(pos, _sweepLast);
    final hi = math.max(pos, _sweepLast);
    _sweepLast = pos;
    widget.onSweepAdd([for (var k = lo; k <= hi; k++) widget.rows[_engineOf(k)].id]);
  }

  void _sweepEnd() {
    _sweeping = false;
    _sweepGlobal = null;
    _edgeTimer?.cancel();
    _edgeTimer = null;
  }

  void _edgeScroll() {
    final global = _sweepGlobal;
    final local = global == null ? null : _toLocal(global);
    if (local == null || !widget.controller.hasClients) return;
    final p = widget.controller.position;
    double delta = 0;
    if (local.dy < _kEdgeBand) delta = -_kEdgeStep;
    if (local.dy > _viewportHeight - _kEdgeBand) delta = _kEdgeStep;
    if (delta == 0) return;
    final next = (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (next == p.pixels) return;
    widget.controller.jumpTo(next);
    if (_sweeping) _sweepSample();
  }

  // ---- multi-touch ----

  void _pointerDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    if (_touch.isEmpty) _multiTouch = false;
    _touch.add(e.pointer);
    if (_touch.length == 2) {
      _multiTouch = true;
      if (_sweeping) {
        _sweepEnd();
        widget.onSweepCancel();
      }
    }
  }

  void _pointerUp(PointerEvent e) => _touch.remove(e.pointer);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      _viewportHeight = constraints.maxHeight;
      final list = ListView.builder(
        key: _viewportKey,
        controller: widget.controller,
        padding: const EdgeInsets.symmetric(vertical: _kPadV, horizontal: _kPadH),
        itemExtent: _extent,
        addAutomaticKeepAlives: false,
        itemCount: _n,
        itemBuilder: (_, pos) {
          final i = _engineOf(pos);
          final l = widget.rows[i];
          final img = widget.thumbFor(l.id);
          if (img == null) widget.requestThumb(l.id, i);
          return Padding(
            padding: const EdgeInsets.only(bottom: _kRowGap),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _tapRow(pos),
              onSecondaryTapUp: (_) => widget.onRowMenu(i),
              onLongPress: () {
                if (!_multiTouch) widget.onRowMenu(i);
              },
              onHorizontalDragStart: (d) => _sweepStart(pos, d.globalPosition),
              onHorizontalDragUpdate: (d) => _sweepMove(d.globalPosition),
              onHorizontalDragEnd: (_) => _sweepEnd(),
              onHorizontalDragCancel: _sweepEnd,
              child: LayerRowTile(
                layer: l,
                image: img,
                aspect: widget.thumbAspect,
                number: i + 1,
                active: i == widget.activeIndex,
                selected: widget.selection.contains(l.id),
                height: widget.rowHeight,
                scale: widget.scale,
              ),
            ),
          );
        },
      );
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _pointerDown,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        child: list,
      );
    });
  }
}
