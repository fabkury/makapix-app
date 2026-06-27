part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// The canvas rendering widget, multi-touch draw/pan/zoom gestures, and the
// gesture-safe tooltip help band.
extension _EditorCanvas on _EditorPageState {

  // Non-interactive help band at the very bottom. It moves the tool buttons up and out of
  // Android's bottom swipe-to-switch-app gesture zone, and teaches the current tool.
  Widget _buildTooltipBand(BuildContext context) {
    // Reserve the system gesture inset (min 16) as empty space below the text so the
    // Android swipe-up-to-switch-app gesture isn't blocked by tool buttons.
    final inset = MediaQuery.of(context).viewPadding.bottom;
    final gesturePad = inset < 16 ? 16.0 : inset;
    final tip = toolTips[_tool] ?? '';
    final icon = tools.firstWhere((t) => t.dsl == _tool, orElse: () => tools.first).icon;
    // FIXED height = exactly two text lines + top padding + the reserved gesture pad, so the
    // band never changes height (no reflow of the rest of the screen).
    const lineH = 13.75; // 11px * 1.25
    final bandHeight = 6 + lineH * 2 + 6 + gesturePad;
    return Container(
      width: double.infinity,
      height: bandHeight,
      color: const Color(0xFF0E1012),
      padding: EdgeInsets.fromLTRB(12, 6, 12, gesturePad),
      alignment: Alignment.topLeft,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: const Color(0xFF6DAA2C)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            tip,
            style: const TextStyle(fontSize: 11, color: Colors.white60, height: 1.25),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(builder: (context, c) {
      final box = Size(c.maxWidth, c.maxHeight);
      final (vScale, vOff) = _view(box);
      return Container(
        color: const Color(0xFF222428),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            _touchPos[e.pointer] = e.localPosition;
            if (_touchPos.length >= 2) {
              // a second finger → pan/zoom; abort any single-finger draw in progress
              if (!_pinching) {
                if (_drawPointer != null) {
                  _cancelDraw();
                  _drawPointer = null;
                }
                _startPinch();
              }
            } else {
              // first finger → draw (unless this tool doesn't draw on the canvas)
              if (!_isTransformTool) {
                _drawPointer = e.pointer;
                _beginDraw(e.localPosition, box);
              }
            }
          },
          onPointerMove: (e) {
            if (!_touchPos.containsKey(e.pointer)) return;
            _touchPos[e.pointer] = e.localPosition;
            if (_pinching) {
              _updatePinch(box);
              return;
            }
            if (e.pointer == _drawPointer) _continueDraw(e.localPosition, box);
          },
          onPointerUp: (e) => _endTouch(e.pointer, cancel: false),
          onPointerCancel: (e) => _endTouch(e.pointer, cancel: true),
          child: Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: CanvasPainter(_image, vScale, vOff), size: Size.infinite),
            CustomPaint(painter: OutlinePainter(_outlineEdges, vScale, vOff, _antCtrl), size: Size.infinite),
            if (_isCursorTool)
              // marching ants around the EXACT pixels the actuate button would draw (the airbrush
              // shows its spray disc, an approximation, due to its randomized dabs)
              CustomPaint(
                painter: OutlinePainter(
                  _footprintEdges(_cursorX, _cursorY, airbrush: _tool == 'Airbrush'),
                  vScale,
                  vOff,
                  _antCtrl,
                ),
                size: Size.infinite,
              ),
          ]),
        ),
      );
    });
  }

  // A finger left the canvas (lifted or cancelled). End the pinch or the draw as appropriate; once
  // pinching, drawing stays suspended until every finger has lifted.
  void _endTouch(int pointer, {required bool cancel}) {
    _touchPos.remove(pointer);
    if (_pinching) {
      if (_touchPos.length < 2) _pinching = false; // back to ≤1 finger: stop pinching, don't draw
      return;
    }
    if (pointer == _drawPointer) {
      if (cancel) {
        _cancelDraw();
      } else {
        _endDraw();
      }
      _drawPointer = null;
    }
  }

  // ---- single-pointer draw helpers (driven by the multi-touch state machine above) ----

  void _beginDraw(Offset pos, Size box) {
    if (_isCursorTool) {
      _lastTouch = pos;
      _accX = 0;
      _accY = 0;
      return; // off-finger: drag moves the reticle, acting is via buttons
    }
    final p = _toCanvas(pos, box);
    if (_tool == 'Eraser') {
      _eraserX = p.dx.toInt();
      _eraserY = p.dy.toInt();
    }
    _send('PointerDown(${p.dx.toInt()},${p.dy.toInt()})');
    _redraw();
  }

  void _continueDraw(Offset pos, Size box) {
    if (_isCursorTool) {
      final last = _lastTouch ?? pos;
      final (scale, _) = _view(box);
      _accX += (pos.dx - last.dx) / scale;
      _accY += (pos.dy - last.dy) / scale;
      _lastTouch = pos;
      final mx = _accX.truncate();
      final my = _accY.truncate();
      if (mx != 0 || my != 0) {
        _accX -= mx;
        _accY -= my;
        _moveCursor(mx, my);
        _redraw();
      }
      return;
    }
    final p = _toCanvas(pos, box);
    if (_tool == 'Eraser') {
      _eraserX = p.dx.toInt();
      _eraserY = p.dy.toInt();
    }
    _send('PointerMove(${p.dx.toInt()},${p.dy.toInt()})');
    _redraw();
  }

  void _endDraw() {
    if (_isCursorTool) {
      _lastTouch = null;
      if (_penDown) _refreshState();
      return;
    }
    if (_eraserX != null) {
      _eraserX = null;
      _eraserY = null;
    }
    _send('PointerUp()');
    _refreshState();
    _redraw();
    setState(() {});
  }

  // Abort an in-progress draw, discarding its marks without an undo step (used when a second finger
  // interrupts a nascent stroke to begin pan/zoom).
  void _cancelDraw() {
    if (_isCursorTool) {
      _lastTouch = null;
      if (_penDown) _send('CancelStroke()'); // abort a precision pen line in progress
    } else {
      _eraserX = null;
      _eraserY = null;
      _send('CancelStroke()');
    }
    _refreshState();
    _redraw();
    setState(() {});
  }

  (int, int) _thumbSize() {
    final w = engine.width, h = engine.height;
    const maxSide = 64;
    if (w >= h) {
      final t = (maxSide * h / w).round().clamp(1, maxSide).toInt();
      return (maxSide, t);
    }
    final t = (maxSide * w / h).round().clamp(1, maxSide).toInt();
    return (t, maxSide);
  }

}
