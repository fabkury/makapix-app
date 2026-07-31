part of 'animator_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _AnimatorPageState — the editor part files' rationale: extensions on a State
// subclass trip a false positive calling the @protected setState.)

// The Stage — the primary editing surface (design 03 §1: "the stage is the editor"). A raw
// Listener with the editor's finger-count state machine: one finger = select / drag the
// Actor (auto-keyed via the GestureBegin/SetAtPlayhead/EndGesture bracket) or drag the pivot;
// two fingers = pinch — on the selected Actor's body it scales+rotates the ACTOR (15° stops,
// 1.0 scale detent, haptic ticks), elsewhere it pans/zooms the view.
extension _AnimatorStage on _AnimatorPageState {
  Widget _buildStageArea() {
    return LayoutBuilder(builder: (context, constraints) {
      final box = constraints.biggest;
      _lastStageBox = box;
      return Container(
        color: const Color(0xFF222428),
        child: ClipRect(
          child: Stack(fit: StackFit.expand, children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _stageDown(e, box),
              onPointerMove: (e) => _stageMove(e, box),
              onPointerUp: (e) => _stageUp(e, box),
              onPointerCancel: (e) => _stageUp(e, box, cancel: true),
              child: Stack(fit: StackFit.expand, children: [
                ValueListenableBuilder<ui.Image?>(
                  valueListenable: _frameVN,
                  builder: (_, img, _) {
                    if (img == null) return const SizedBox.shrink();
                    final (s, off) = _view(box);
                    return RepaintBoundary(
                      child: CustomPaint(painter: CanvasPainter(img, s, off)),
                    );
                  },
                ),
                ValueListenableBuilder<int>(
                  valueListenable: _overlayVN,
                  builder: (_, _, _) {
                    final sel = _state.selected;
                    final (s, off) = _view(box);
                    return Stack(fit: StackFit.expand, children: [
                      if (sel != null)
                        CustomPaint(
                          painter: ActorBoxPainter(
                            Rect.fromLTWH(
                              sel.bounds[0].toDouble(),
                              sel.bounds[1].toDouble(),
                              sel.bounds[2].toDouble(),
                              sel.bounds[3].toDouble(),
                            ),
                            s,
                            off,
                            dragging: _dragKind == 1,
                          ),
                        ),
                      if (sel != null)
                        CustomPaint(
                          painter: PivotHandlePainter(
                            _pivotCanvas(sel),
                            s,
                            off,
                            grabbed: _dragKind == 2,
                          ),
                        ),
                      if (_snapGuides.isNotEmpty)
                        CustomPaint(painter: SnapGuidePainter(_snapGuides, s, off)),
                    ]);
                  },
                ),
              ]),
            ),
            if (_state.selected != null)
              Positioned(left: 10, bottom: 10, child: _actorPill(_state.selected!)),
          ]),
        ),
      );
    });
  }

  /// The selected Actor's pivot in scene coords: its position IS the pivot's location.
  Offset _pivotCanvas(ActorState sel) =>
      Offset(sel.pose.x.toDouble(), sel.pose.y.toDouble());

  // ---- the compact selected-Actor pill (the editor's floating-menu idiom) ------------------

  Widget _actorPill(ActorState sel) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xE0141618),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(sel.name,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
            overflow: TextOverflow.ellipsis),
        const SizedBox(width: 6),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          tooltip: 'Flip horizontally (keys at the playhead)',
          icon: const Icon(Icons.flip),
          onPressed: () => _act(
              'SetAtPlayhead(${sel.id}, fliph, ${sel.pose.flipH ? 0 : 1})'),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          tooltip: 'Duplicate actor',
          icon: const Icon(Icons.copy),
          onPressed: () => _act('DuplicateActor(${sel.id})'),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          tooltip: 'Actor options',
          icon: const Icon(Icons.more_horiz),
          onPressed: () => _actorSheet(sel.id),
        ),
      ]),
    );
  }

  // ---- pointer state machine ---------------------------------------------------------------

  void _stageDown(PointerDownEvent e, Size box) {
    _touchPos[e.pointer] = e.localPosition;
    if (_touchPos.length >= 2) {
      // Second finger: cancel a nascent drag, start a pinch.
      _cancelStageDrag();
      _pinching = true;
      _startPinchAny(box);
      return;
    }
    if (_playing) _pause(); // v0.1: touching the stage pauses playback
    final c = _toCanvas(e.localPosition, box);
    final sel = _state.selected;
    final (s, _) = _view(box);

    // Pivot grab: within 28 SCREEN px of the selected Actor's pivot reticle.
    if (sel != null) {
      final pv = _pivotCanvas(sel);
      if ((c - pv).distance * s <= 28) {
        _dragPointer = e.pointer;
        _dragKind = 2;
        _dragStartCanvas = c;
        _beginGesture();
        return;
      }
    }

    // Actor hit: topmost opaque pixel via the engine; select + begin move drag.
    final hit = engine.hitTest(_state.playhead, c.dx.floor(), c.dy.floor());
    if (hit != null) {
      if (hit != _state.selectedActor) {
        _sendSession('SelectActor($hit)');
        _refreshState();
        _overlayVN.value++;
        setState(() {});
      }
      final a = _state.actor(hit)!;
      _dragPointer = e.pointer;
      _dragKind = 1;
      _dragStartX = a.pose.x;
      _dragStartY = a.pose.y;
      _dragStartCanvas = c;
      _beginGesture();
      return;
    }
    // Empty stage: a tap (no drag) clears the selection on pointer-up.
    _dragPointer = e.pointer;
    _dragKind = 0;
    _dragStartCanvas = c;
  }

  void _stageMove(PointerMoveEvent e, Size box) {
    _touchPos[e.pointer] = e.localPosition;
    if (_pinching) {
      if (_pinchMode == 1) {
        _updateActorPinch(box);
      } else {
        _updateViewPinch(box);
      }
      return;
    }
    if (e.pointer != _dragPointer) return;
    final c = _toCanvas(e.localPosition, box);
    final sel = _state.selected;
    if (sel == null && _dragKind != 0) return;
    switch (_dragKind) {
      case 1: // move the Actor: position keys at the playhead
        final dx = (c.dx - _dragStartCanvas.dx).round();
        final dy = (c.dy - _dragStartCanvas.dy).round();
        var nx = _dragStartX + dx;
        var ny = _dragStartY + dy;
        final sx = snapPosition(nx, _state.w);
        final sy = snapPosition(ny, _state.h);
        nx = sx.value;
        ny = sy.value;
        _hapticOnSnap(sx.snapped || sy.snapped);
        _snapGuides = [
          if (sx.snapped) SnapGuide(x: nx.toDouble()),
          if (sy.snapped) SnapGuide(y: ny.toDouble()),
        ];
        _send('SetAtPlayhead(${sel!.id}, x, $nx); SetAtPlayhead(${sel.id}, y, $ny)');
        _liveRefresh();
        _hintLive('x $nx · y $ny');
      case 2: // move the pivot (prop-local milli-px follow the world-space drag)
        final a = sel!;
        final dxMilli = ((c.dx - _dragStartCanvas.dx) * 1000).round();
        final dyMilli = ((c.dy - _dragStartCanvas.dy) * 1000).round();
        // Moving the pivot alone would jump the art (position pins the pivot point), so
        // compensate position to keep the art still: pivot and position move together.
        final px = a.pose.pivotXMilli + dxMilli;
        final py = a.pose.pivotYMilli + dyMilli;
        final nx = a.pose.x + ((c.dx - _dragStartCanvas.dx)).round();
        final ny = a.pose.y + ((c.dy - _dragStartCanvas.dy)).round();
        _send('SetAtPlayhead(${a.id}, pivotx, $px); SetAtPlayhead(${a.id}, pivoty, $py);'
            'SetAtPlayhead(${a.id}, x, $nx); SetAtPlayhead(${a.id}, y, $ny)');
        _dragStartCanvas = c;
        _liveRefresh();
      default:
        break;
    }
  }

  void _stageUp(PointerEvent e, Size box, {bool cancel = false}) {
    _touchPos.remove(e.pointer);
    if (_pinching) {
      if (_touchPos.length < 2) {
        _pinching = false;
        if (_pinchMode == 1) _endGesture();
        _pinchMode = 0;
      }
      return;
    }
    if (e.pointer != _dragPointer) return;
    final wasDrag = _dragKind != 0;
    final moved = wasDrag &&
        (_toCanvas(e.localPosition, box) - _dragStartCanvas).distance >= 0.5;
    _dragPointer = null;
    if (_dragKind == 0 && !cancel) {
      // Tap on empty stage → clear selection.
      if (_state.selectedActor != null) {
        _sendSession('SelectNone()');
        _refreshState();
        setState(() {});
      }
    }
    _dragKind = 0;
    _snapGuides = const [];
    _overlayVN.value++;
    if (wasDrag) {
      _endGesture(dropKey: moved || true);
    }
  }

  void _cancelStageDrag() {
    if (_dragKind != 0 && _gestureOpen) {
      // The pinch takes over: keep the bracket open — the actor pinch shares it.
      _pinchMode = _state.selected != null ? _pinchModeForMid() : 0;
      if (_pinchMode == 0) _endGesture();
    } else {
      _pinchMode = _state.selected != null ? _pinchModeForMid() : 0;
      if (_pinchMode == 1) _beginGesture();
    }
    _dragPointer = null;
    _dragKind = 0;
    _snapGuides = const [];
  }

  /// Actor pinch iff the midpoint lands inside the selected Actor's bounds inflated by 24
  /// screen px; else view pinch.
  int _pinchModeForMid() {
    final sel = _state.selected;
    if (sel == null || _touchPos.length < 2) return 0;
    final ps = _touchPos.values.toList();
    final mid = (ps[0] + ps[1]) / 2;
    final c = _toCanvas(mid, _lastStageBox);
    final (s, _) = _view(_lastStageBox);
    final inflate = 24 / s;
    final r = Rect.fromLTWH(
      sel.bounds[0] - inflate,
      sel.bounds[1] - inflate,
      sel.bounds[2] + 2 * inflate,
      sel.bounds[3] + 2 * inflate,
    );
    return r.contains(c) ? 1 : 0;
  }

  void _startPinchAny(Size box) {
    final ps = _touchPos.values.toList();
    _startViewPinch();
    if (_pinchMode == 1) {
      final sel = _state.selected!;
      _pinchStartAngle = (ps[1] - ps[0]).direction;
      _pinchStartScaleMilli = sel.pose.scaleMilli;
      _pinchStartRotMdeg = sel.pose.rotMdeg;
      if (!_gestureOpen) _beginGesture();
    }
  }

  void _updateActorPinch(Size box) {
    final sel = _state.selected;
    if (sel == null || _touchPos.length < 2) return;
    final ps = _touchPos.values.toList();
    final dist = (ps[0] - ps[1]).distance.clamp(1.0, double.infinity);
    final angle = (ps[1] - ps[0]).direction;

    var scaleMilli = (_pinchStartScaleMilli * dist / _pinchStartDist).round();
    final snapS = snapScale(scaleMilli);
    scaleMilli = snapS.value.clamp(100, 8000);

    final dMdeg = ((angle - _pinchStartAngle) * 180000 / math.pi).round();
    var rot = _pinchStartRotMdeg + dMdeg;
    final snapR = snapRotation(rot);
    rot = snapR.value;
    _hapticOnSnap(snapS.snapped || snapR.snapped);
    _snapGuides = snapR.snapped
        ? [
            SnapGuide(
              badge: '${normalizeMdeg(rot) ~/ 1000}°',
              badgeAnchorCanvas: Offset(sel.pose.x.toDouble(), sel.pose.y.toDouble()),
            )
          ]
        : const [];

    _send('SetAtPlayhead(${sel.id}, scale, $scaleMilli); SetAtPlayhead(${sel.id}, rot, $rot)');
    _liveRefresh();
  }

  // ---- the auto-key gesture bracket --------------------------------------------------------

  void _beginGesture() {
    if (_gestureOpen) return;
    _gestureOpen = true;
    _send('BeginGesture()');
  }

  void _endGesture({bool dropKey = true}) {
    if (!_gestureOpen) return;
    _gestureOpen = false;
    _send('EndGesture()');
    if (dropKey) HapticFeedback.lightImpact(); // the key-drop pulse
    _refreshState();
    _redrawCurrent();
    if (dropKey && _state.autoKey) {
      _hintFlash('Key · frame ${_state.playhead + 1}');
    } else {
      _hintEnd();
    }
    if (mounted) setState(() {});
  }

  /// Per-move refresh: composite the current frame + repaint overlays WITHOUT a full-tree
  /// setState (the editor's per-pointer-event discipline).
  void _liveRefresh() {
    _state = SceneState.parse(engine.stateJson());
    _showFrame(_state.playhead);
    _overlayVN.value++;
  }

  void _hapticOnSnap(bool engaged) {
    if (engaged && !_lastSnapEngaged) HapticFeedback.selectionClick();
    _lastSnapEngaged = engaged;
    if (!engaged) _snapGuides = const [];
  }
}
