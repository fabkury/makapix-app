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
              if (!_isInertCanvasTool) {
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
            if (_isShapeTool && _hasShapeDraft)
              // draggable endpoint handles for the uncommitted figure
              CustomPaint(
                painter: HandlePainter([_shapeA!, _shapeB!], vScale, vOff),
                size: Size.infinite,
              ),
            if (_isRuler && _hasRuler)
              // measurement line + endpoint coords + length (never drawn to the canvas)
              CustomPaint(
                painter: RulerPainter(_rulerA!, _rulerB!, vScale, vOff),
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
    if (_isRuler) {
      _beginRuler(pos, box);
      return;
    }
    if (_isShapeTool) {
      _beginShape(pos, box);
      return;
    }
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
    if (_isRuler) {
      _continueRuler(pos, box);
      return;
    }
    if (_isShapeTool) {
      _continueShape(pos, box);
      return;
    }
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
    if (_isRuler) {
      _rulerDrag = 0;
      setState(() {});
      return;
    }
    if (_isShapeTool) {
      _endShape();
      return;
    }
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
    if (_isRuler) {
      _rulerDrag = 0; // a second finger interrupted; keep the measurement as-is
      setState(() {});
      return;
    }
    if (_isShapeTool) {
      // A second finger interrupted a figure gesture (→ pan/zoom). Keep any established draft; but
      // if this was a brand-new degenerate figure (a single point, e.g. a pinch starting on empty
      // canvas), drop it so it leaves no stray dot behind.
      if (_shapeDrag == 3 && _hasShapeDraft && _shapeA == _shapeB) {
        _send('ShapeCancel()');
        _shapeA = null;
        _shapeB = null;
      }
      _shapeDrag = 0;
      _newShapeStart = null;
      _redraw();
      setState(() {});
      return;
    }
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

  // ---- figure draft gestures (Line/Rect/Ellipse: drag → adjust handles → commit) ----

  // Begin a figure gesture: grab the nearest endpoint handle if the press lands near one
  // (generous screen-space tolerance — "near, not necessarily on"). With a draft already pending,
  // a press OFF the handles does nothing (it never resets the draft); a fresh figure only starts
  // when there is no draft yet.
  void _beginShape(Offset pos, Size box) {
    final p = _toCanvas(pos, box);
    _newShapeStart = null;
    if (_hasShapeDraft) {
      final (s, off) = _view(box);
      Offset screenOf(Offset c) => Offset(off.dx + (c.dx + 0.5) * s, off.dy + (c.dy + 0.5) * s);
      final tol = (s * 0.9).clamp(22.0, 44.0);
      final dA = (pos - screenOf(_shapeA!)).distance;
      final dB = (pos - screenOf(_shapeB!)).distance;
      if (dA <= tol && dA <= dB) {
        _shapeDrag = 1;
        _shapeA = p;
        _pushShape();
      } else if (dB <= tol) {
        _shapeDrag = 2;
        _shapeB = p;
        _pushShape();
      } else {
        _shapeDrag = 0; // off the handles → do nothing, keep the pending draft as-is
      }
    } else {
      // No draft yet: materialize a degenerate figure so a tap drops a starting handle.
      _shapeDrag = 3;
      _newShapeStart = p;
      _shapeA = p;
      _shapeB = p;
      _pushShape();
    }
    _redraw();
    setState(() {});
  }

  void _continueShape(Offset pos, Size box) {
    if (_shapeDrag == 0) return;
    final p = _toCanvas(pos, box);
    if (_shapeDrag == 1) {
      _shapeA = _ratioed(_shapeB!, p); // dragging A: anchor is B
    } else if (_shapeDrag == 2) {
      _shapeB = _ratioed(_shapeA!, p); // dragging B: anchor is A
    } else {
      // New figure: A fixed at the press point, B follows (ratio-locked to A if enabled).
      final a = _newShapeStart ?? p;
      _shapeA = a;
      _shapeB = _ratioed(a, p);
    }
    _pushShape();
    _redraw();
    setState(() {});
  }

  // Constrain `moving` so that |moving - anchor| keeps the locked width:height ratio (Rect/Ellipse
  // only). The box is sized to reach the finger in whichever axis is more extended. Clamped to the
  // canvas so the handles match the engine-clamped preview.
  Offset _ratioed(Offset anchor, Offset moving) {
    if (!_lockRatio || (_tool != 'Rectangle' && _tool != 'Ellipse')) return moving;
    final r = _ratio <= 0 ? 1.0 : _ratio;
    final dw = moving.dx - anchor.dx;
    final dh = moving.dy - anchor.dy;
    final h = (dh.abs() > dw.abs() / r) ? dh.abs() : dw.abs() / r;
    final w = h * r;
    final bx = (anchor.dx + (dw < 0 ? -w : w)).roundToDouble().clamp(0, engine.width - 1).toDouble();
    final by = (anchor.dy + (dh < 0 ? -h : h)).roundToDouble().clamp(0, engine.height - 1).toDouble();
    return Offset(bx, by);
  }

  // Re-snap the pending draft to the current ratio (called when Lock Ratio or the ratio changes).
  void _reapplyRatio() {
    if (!_hasShapeDraft) return;
    _shapeB = _ratioed(_shapeA!, _shapeB!);
    _pushShape();
    _redraw();
    setState(() {});
  }

  // ---- ruler gestures (measure only — never draws to the canvas) ----

  Offset _clampToCanvas(Offset p) =>
      Offset(p.dx.clamp(0, engine.width - 1).toDouble(), p.dy.clamp(0, engine.height - 1).toDouble());

  void _beginRuler(Offset pos, Size box) {
    final p = _clampToCanvas(_toCanvas(pos, box));
    if (_hasRuler) {
      final (s, off) = _view(box);
      Offset screenOf(Offset c) => Offset(off.dx + (c.dx + 0.5) * s, off.dy + (c.dy + 0.5) * s);
      final tol = (s * 0.9).clamp(22.0, 44.0);
      final dA = (pos - screenOf(_rulerA!)).distance;
      final dB = (pos - screenOf(_rulerB!)).distance;
      if (dA <= tol && dA <= dB) {
        _rulerDrag = 1;
        _rulerA = p;
      } else if (dB <= tol) {
        _rulerDrag = 2;
        _rulerB = p;
      } else {
        // Off the handles → start a fresh measurement (the ruler draws nothing, so replacing is free).
        _rulerDrag = 3;
        _rulerA = p;
        _rulerB = p;
      }
    } else {
      _rulerDrag = 3;
      _rulerA = p;
      _rulerB = p;
    }
    setState(() {});
  }

  void _continueRuler(Offset pos, Size box) {
    if (_rulerDrag == 0) return;
    final p = _clampToCanvas(_toCanvas(pos, box));
    if (_rulerDrag == 1) {
      _rulerA = p;
    } else {
      _rulerB = p; // dragging B, or growing a new measurement (A stays put)
    }
    setState(() {});
  }

  // Releasing leaves the draft in place (preview + handles persist); commit is an explicit button.
  void _endShape() {
    _shapeDrag = 0;
    _newShapeStart = null;
    setState(() {});
  }

  // Mirror the local draft endpoints into the engine so the preview re-renders.
  void _pushShape() {
    if (!_hasShapeDraft) return;
    final a = _shapeA!, b = _shapeB!;
    _send('ShapeSet(${a.dx.toInt()},${a.dy.toInt()},${b.dx.toInt()},${b.dy.toInt()})');
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
