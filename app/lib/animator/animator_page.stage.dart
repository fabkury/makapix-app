part of 'animator_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _AnimatorPageState — the editor part files' rationale: extensions on a State
// subclass trip a false positive calling the @protected setState.)

// The Stage — the primary editing surface (design 03 §1: "the stage is the editor"). A raw
// Listener with the strict select-then-act grammar (docs/animator/06-gesture-safety.md
// §4.3): a TAP selects (on pointer-up, via engine hit-test); a one-finger drag starting
// ANYWHERE acts on the current selection — Move mode drags position, Rotate mode orbits the
// pivot with 15° stops — auto-keyed via the BeginGesture/SetAtPlayhead/EndGesture bracket;
// the pivot reticle keeps its own grab; TWO fingers always pan/zoom the view. Scale is
// deliberately not a gesture (it lives in the Transform sheet).
extension _AnimatorStage on _AnimatorPageState {
  Widget _buildStageArea() {
    return LayoutBuilder(builder: (context, constraints) {
      final box = constraints.biggest;
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
                            dragging: _dragKind == 1 || _dragKind == 3,
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
        chromeIconToggle(
          const [Icons.open_with, Icons.rotate_left],
          const ['Move — a drag anywhere moves the actor', 'Rotate — a drag orbits the pivot'],
          _stageMode.index,
          (i) => setState(() => _stageMode = _StageMode.values[i]),
        ),
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
      // Second finger: cancel a nascent drag; a pinch is ALWAYS the view (no actor pinch).
      _cancelStageDrag();
      _pinching = true;
      _startViewPinch();
      return;
    }
    if (_playing) _pause(); // touching the stage pauses playback
    final c = _toCanvas(e.localPosition, box);
    final sel = _state.selected;
    final (s, off) = _view(box);

    // Pivot grab keeps its start-point-specific handle: within 28 SCREEN px of the reticle.
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

    // Strict select-then-act: no hit-test, no selection change on the way down — a drag
    // acts on the CURRENT selection from anywhere; taps (re)select on pointer-up.
    _dragPointer = e.pointer;
    _dragStartCanvas = c;
    if (sel == null) {
      _dragKind = 0;
      return;
    }
    if (_stageMode == _StageMode.rotate) {
      _dragKind = 3;
      _rotStartMdeg = sel.pose.rotMdeg;
      _rotAccum = 0;
      final pivotScreen = off + _pivotCanvas(sel) * s;
      _rotPrevBearing = (e.localPosition - pivotScreen).direction;
    } else {
      _dragKind = 1;
      _dragStartX = sel.pose.x;
      _dragStartY = sel.pose.y;
    }
    _beginGesture();
  }

  void _stageMove(PointerMoveEvent e, Size box) {
    _touchPos[e.pointer] = e.localPosition;
    if (_pinching) {
      _updateViewPinch(box);
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
      case 3: // rotate: the finger orbits the pivot (bearing deltas, multi-turn safe)
        final a = sel!;
        final (s, off) = _view(box);
        final pivotScreen = off + _pivotCanvas(a) * s;
        final v = e.localPosition - pivotScreen;
        if (v.distance < 24) break; // min-radius guard: bearings are noise near the pivot
        final bearing = v.direction;
        var d = bearing - _rotPrevBearing;
        while (d > math.pi) {
          d -= 2 * math.pi;
        }
        while (d < -math.pi) {
          d += 2 * math.pi;
        }
        _rotAccum += d;
        _rotPrevBearing = bearing;
        var rot = _rotStartMdeg + (_rotAccum * 180000 / math.pi).round();
        final snapR = snapRotation(rot);
        rot = snapR.value;
        _hapticOnSnap(snapR.snapped);
        _snapGuides = snapR.snapped
            ? [
                SnapGuide(
                  badge: '${normalizeMdeg(rot) ~/ 1000}°',
                  badgeAnchorCanvas:
                      Offset(a.pose.x.toDouble(), a.pose.y.toDouble()),
                )
              ]
            : const [];
        _send('SetAtPlayhead(${a.id}, rot, $rot)');
        _liveRefresh();
        _hintLive('rot ${normalizeMdeg(rot) ~/ 1000}°');
      default:
        break;
    }
  }

  void _stageUp(PointerEvent e, Size box, {bool cancel = false}) {
    _touchPos.remove(e.pointer);
    if (_pinching) {
      if (_touchPos.length < 2) _pinching = false;
      return;
    }
    if (e.pointer != _dragPointer) return;
    final wasKind = _dragKind;
    final moved =
        (_toCanvas(e.localPosition, box) - _dragStartCanvas).distance >= 0.5;
    _dragPointer = null;
    _dragKind = 0;
    _snapGuides = const [];
    if (!cancel && !moved && wasKind != 2) {
      // A tap: the ONLY stage selection path. Hit-test the down point; a pivot-reticle tap
      // (kind 2) is exempt — grabbing the handle must never deselect.
      final c = _dragStartCanvas;
      final hit = engine.hitTest(_state.playhead, c.dx.floor(), c.dy.floor());
      if (hit != null && hit != _state.selectedActor) {
        _sendSession('SelectActor($hit)');
        _refreshState();
        setState(() {});
      } else if (hit == null && _state.selectedActor != null) {
        _sendSession('SelectNone()');
        _refreshState();
        setState(() {});
      }
    }
    _overlayVN.value++;
    if (wasKind != 0) {
      _endGesture(dropKey: moved);
    } else {
      _hintEnd();
    }
  }

  void _cancelStageDrag() {
    // A second finger always means the view: close any open bracket quietly.
    if (_dragKind != 0 && _gestureOpen) _endGesture(dropKey: false);
    _dragPointer = null;
    _dragKind = 0;
    _snapGuides = const [];
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
