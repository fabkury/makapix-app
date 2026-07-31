part of 'animator_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _AnimatorPageState — the editor part files' rationale: extensions on a State
// subclass trip a false positive calling the @protected setState.)

// The chrome bands: top band (☰ · title · readout · fit · cast), the transport dock
// (play/zoom/EasingChip/undo/redo — taps only, bottom-most), the hint strip (passive text
// in the safe-area pad), and the one-timeline surface with its three zoom levels — Strip
// (scrub lane + aggregated ticks + loop handles), Tracks (per-Actor lanes, drag-to-retime),
// Focus (one Actor's per-property rows). Geometry via TimelineLayout only; the timeline
// content sits inside adaptive side gutters so no drag has to start in the OS Back-gesture
// zones (docs/animator/06-gesture-safety.md).
extension _AnimatorTimeline on _AnimatorPageState {
  // ---- top band ----------------------------------------------------------------------------

  Widget _buildTopBand() {
    final s = _chromeScale;
    return Container(
      height: 48 * s,
      color: const Color(0xFF15171A),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        _menuButton(),
        const SizedBox(width: 4),
        Expanded(
          child: InkWell(
            onTap: _renameScene,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_sceneTitle,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(
                '${_state.w}×${_state.h} · ${fpsLabel(_state.millifps)} · ${_state.frameCount} frames',
                style: const TextStyle(fontSize: 10, color: Colors.white38),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
        ),
        ValueListenableBuilder<int>(
          valueListenable: _overlayVN,
          builder: (_, _, _) => Text(
              '${(_playing ? _playbackFrame() : _state.playhead) + 1} / ${_state.frameCount}',
              style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ),
        IconButton(
          tooltip: 'Fit view',
          icon: const Icon(Icons.fit_screen, size: 20),
          onPressed: _fitView,
        ),
        IconButton(
          tooltip: 'Cast (props)',
          icon: const Icon(Icons.theater_comedy_outlined, size: 20),
          onPressed: _castSheet,
        ),
      ]),
    );
  }

  Widget _buildSideBand() {
    final s = _chromeScale;
    return Container(
      width: 48 * s,
      color: const Color(0xFF15171A),
      child: Column(children: [
        _menuButton(),
        IconButton(
            tooltip: 'Cast (props)',
            icon: const Icon(Icons.theater_comedy_outlined, size: 20),
            onPressed: _castSheet),
        IconButton(
            tooltip: 'Fit view',
            icon: const Icon(Icons.fit_screen, size: 20),
            onPressed: _fitView),
        const Spacer(),
        IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo, size: 20),
            onPressed: _state.canUndo ? () => _act('Undo()') : null),
        IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo, size: 20),
            onPressed: _state.canRedo ? () => _act('Redo()') : null),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _menuButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu),
      tooltip: 'Menu',
      onSelected: (v) {
        switch (v) {
          case 'club':
            ref.read(openClubProvider.notifier).state++;
          case 'gallery':
            _openSceneGallery();
          case 'new':
            _newSceneFlow();
          case 'openfile':
            _openSceneFileFlow();
          case 'savefile':
            _saveSceneFileFlow();
          case 'import':
            _importPropFlow();
          case 'export':
            _exportFlow();
          case 'share':
            _shareFlow();
          case 'settings':
            _sceneSettingsSheet();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'club', child: ListTile(leading: Icon(Icons.home_outlined), title: Text('Go to Club'), dense: true)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'gallery', child: ListTile(leading: Icon(Icons.movie_filter_outlined), title: Text('My Scenes'), dense: true)),
        const PopupMenuItem(value: 'new', child: ListTile(leading: Icon(Icons.add), title: Text('New scene'), dense: true)),
        const PopupMenuItem(value: 'openfile', child: ListTile(leading: Icon(Icons.folder_open), title: Text('Open scene file…'), dense: true)),
        const PopupMenuItem(value: 'savefile', child: ListTile(leading: Icon(Icons.save_outlined), title: Text('Save scene file…'), dense: true)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.add_photo_alternate_outlined), title: Text('Import prop…'), dense: true)),
        const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.save_alt), title: Text('Export…'), dense: true)),
        const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share_outlined), title: Text('Share…'), dense: true)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.tune), title: Text('Scene settings'), dense: true)),
      ],
    );
  }

  // ---- transport row -----------------------------------------------------------------------

  Widget _buildTransportRow() {
    final landscape = editorUsesLandscape(MediaQuery.sizeOf(context));
    final selTween = _selTweenState();
    return Container(
      height: 48,
      color: const Color(0xFF202327),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play the loop',
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: _togglePlay,
        ),
        chromeIconToggle(
          const [Icons.horizontal_rule, Icons.stacked_line_chart, Icons.zoom_in],
          const ['Strip — scrub the whole scene', 'Tracks — one lane per actor', 'Focus — per-property rows'],
          _timelineZoom.index,
          (i) => _setTimelineZoom(TimelineZoom.values[i]),
        ),
        const SizedBox(width: 4),
        if (selTween != null)
          EasingChip(
            value: chipForToken(selTween),
            onChanged: _applyEasing,
          ),
        if (_selTween?.$2 != null && selTween != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: 'Delete this key',
            icon: const Icon(Icons.key_off_outlined),
            onPressed: () {
              final st = _selTween!;
              _selTween = null;
              _act('RemoveKey(${st.$1}, ${_dslProp(st.$2!)}, ${st.$3})');
            },
          ),
        const Spacer(),
        if (!landscape) ...[
          miniBtn('Undo', _state.canUndo ? () => _act('Undo()') : () {}),
          miniBtn('Redo', _state.canRedo ? () => _act('Redo()') : () {}),
        ],
      ]),
    );
  }

  /// The engine tween token of the selected tween's key, if the selection is still valid.
  String? _selTweenState() {
    final st = _selTween;
    if (st == null) return null;
    final a = _state.actor(st.$1);
    if (a == null) return null;
    if (st.$2 != null) {
      final t = a.tracks[st.$2];
      final k = t?.keys.where((k) => k.frame == st.$3).toList() ?? const [];
      return k.isEmpty ? null : k.first.tween;
    }
    // Tracks-level selection: representative tween = the first keyed track at that frame.
    for (final name in kTrackNames) {
      final t = a.tracks[name]!;
      for (final k in t.keys) {
        if (k.frame == st.$3 && !_holdOnly(name)) return k.tween;
      }
    }
    return null;
  }

  bool _holdOnly(String prop) => prop == 'flip_h' || prop == 'flip_v' || prop == 'pose';

  void _applyEasing(String chip) {
    final st = _selTween;
    if (st == null) return;
    final token = easingToken(chip);
    final a = _state.actor(st.$1);
    if (a == null) return;
    if (st.$2 != null) {
      _act('SetTween(${st.$1}, ${_dslProp(st.$2!)}, ${st.$3}, $token)');
    } else {
      // Tracks level: apply to every non-hold-only track keyed at that frame.
      final parts = <String>[];
      for (final name in kTrackNames) {
        if (_holdOnly(name)) continue;
        if (a.tracks[name]!.hasKeyAt(st.$3)) {
          parts.add('SetTween(${st.$1}, ${_dslProp(name)}, ${st.$3}, $token)');
        }
      }
      if (parts.isNotEmpty) _act(parts.join('; '));
    }
  }

  /// state_json track name → DSL token (underscores drop).
  String _dslProp(String name) => name.replaceAll('_', '');

  void _setTimelineZoom(TimelineZoom z) {
    setState(() => _timelineZoom = z);
    _prefs?.setInt(_kTimelineZoomPref, z.index);
    if (z == TimelineZoom.focus && _focusActor == null) {
      _focusActor = _state.selectedActor ?? (_state.actors.isEmpty ? null : _state.actors.first.id);
    }
  }

  // ---- the timeline band -------------------------------------------------------------------

  /// Adaptive side gutters (R1): the OS-reported Back-gesture insets, floored to a small
  /// cosmetic margin on devices without edge gestures (3-button nav, desktop, iOS sides).
  (double, double) _timelineGutters() {
    final gi = MediaQuery.of(context).systemGestureInsets;
    return (gi.left.clamp(8.0, 48.0), gi.right.clamp(8.0, 48.0));
  }

  Widget _buildTimelineBand({bool landscape = false}) {
    final s = _chromeScale;
    final viewportH = MediaQuery.sizeOf(context).height;
    final laneCap = viewportH * (landscape ? 0.45 : 0.35);
    final (gutterL, gutterR) = _timelineGutters();
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      // Rebuild with the playback/overlay notifier so the cursor moves in real time
      // while playing (the painters' shouldRepaint gates the actual repaint work).
      return ValueListenableBuilder<int>(
        valueListenable: _overlayVN,
        builder: (_, _, _) {
          switch (_timelineZoom) {
            case TimelineZoom.strip:
              return _stripBand(_layoutFor(width, gutterL, gutterR), 56 * s);
            case TimelineZoom.tracks:
              // Tracks/Focus share one geometry over the lane area right of the 72px
              // label column — the ruler gets the same leading inset, so ticks align.
              return _tracksBand(_layoutFor(width - 72 * s, gutterL, gutterR), s, laneCap);
            case TimelineZoom.focus:
              return _focusBand(_layoutFor(width - 72 * s, gutterL, gutterR), s, laneCap);
          }
        },
      );
    });
  }

  TimelineLayout _layoutFor(double width, double gutterL, double gutterR) {
    if (_timelineZoom == TimelineZoom.strip) {
      // The Strip always fits the whole scene: it IS the scrubber.
      return TimelineLayout.fit(
        width: width,
        frameCount: _state.frameCount,
        originX: gutterL,
        rightInset: gutterR,
      );
    }
    // Over-scroll half a lane past both ends so edge keys are draggable mid-screen (R5).
    final over = math.max(1.0, width - gutterL - gutterR) / 2;
    final probe = TimelineLayout(
      width: width,
      frameCount: _state.frameCount,
      pxPerFrame: _pxPerFrame,
      originX: gutterL,
      rightInset: gutterR,
      overscroll: over,
    );
    return TimelineLayout(
      width: width,
      frameCount: _state.frameCount,
      pxPerFrame: _pxPerFrame,
      scroll: probe.clampScroll(_timeScroll),
      originX: gutterL,
      rightInset: gutterR,
      overscroll: over,
    );
  }

  bool get _recordTint {
    final sel = _state.selected;
    return _state.autoKey && sel != null && !sel.hasKeyAt(_state.playhead);
  }

  // ---- Strip -------------------------------------------------------------------------------

  Widget _stripBand(TimelineLayout layout, double height) {
    final ticks = aggregateTicks(_state.allKeyFrames(), layout);
    return SizedBox(
      height: height,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _stripDown(e, layout),
        onPointerMove: (e) => _stripMove(e, layout),
        onPointerUp: (_) => _stripUp(),
        onPointerCancel: (_) => _stripUp(),
        child: CustomPaint(
          size: Size(layout.width, height),
          painter: StripLanePainter(
            layout: layout,
            tickXs: ticks,
            playhead: _playing ? _playbackFrame() : _state.playhead,
            loopA: _state.loopA,
            loopB: _state.loopB,
            recordTint: _recordTint,
          ),
        ),
      ),
    );
  }

  void _stripDown(PointerDownEvent e, TimelineLayout layout) {
    final x = e.localPosition.dx;
    // Loop-edge handles first (fat 22 px zones).
    final ax = layout.leftOfFrame(_state.loopA);
    final bx = layout.leftOfFrame(_state.loopB) + layout.pxPerFrame;
    if ((x - ax).abs() <= kLoopHandleHitPx) {
      _loopDragEdge = 0;
      return;
    }
    if ((x - bx).abs() <= kLoopHandleHitPx) {
      _loopDragEdge = 1;
      return;
    }
    _loopDragEdge = null;
    _scrubTo(layout.frameAtX(x));
  }

  void _stripMove(PointerMoveEvent e, TimelineLayout layout) {
    final f = layout.frameAtX(e.localPosition.dx);
    if (_loopDragEdge != null) {
      final a = _loopDragEdge == 0 ? f : _state.loopA;
      final b = _loopDragEdge == 1 ? f : _state.loopB;
      final lo = math.min(a, b), hi = math.max(a, b);
      _sendSession('SetLoop($lo, $hi)');
      _state = SceneState.parse(engine.stateJson());
      _hintLive('loop ${lo + 1} – ${hi + 1}');
      setState(() {});
      return;
    }
    _scrubTo(f);
  }

  void _stripUp() {
    _loopDragEdge = null;
    _hintEnd();
  }

  void _scrubTo(int frame) {
    if (_playing) _pause();
    if (frame == _state.playhead) return;
    _sendSession('SetPlayhead($frame)');
    _state = SceneState.parse(engine.stateJson());
    _hintLive('frame ${frame + 1} / ${_state.frameCount}');
    _showFrame(frame);
    _overlayVN.value++;
    setState(() {});
  }

  // ---- Tracks ------------------------------------------------------------------------------

  Widget _tracksBand(TimelineLayout layout, double s, double laneCap) {
    final laneH = 28.0 * s;
    final lanesH = math.min(_state.actors.length * laneH, laneCap);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _ruler(layout, labelInset: 72 * _chromeScale),
      SizedBox(
        height: math.max(lanesH, laneH),
        child: _state.actors.isEmpty
            ? const Center(
                child: Text('No actors yet — import a prop',
                    style: TextStyle(fontSize: 12, color: Colors.white38)))
            : ListView.builder(
                itemCount: _state.actors.length,
                itemExtent: laneH,
                itemBuilder: (_, i) {
                  // Topmost actor first (reverse z), matching what the eye sees on the Stage.
                  final a = _state.actors[_state.actors.length - 1 - i];
                  return _trackLane(a, layout, laneH);
                },
              ),
      ),
    ]);
  }

  /// Ruler height — deliberately generous: the header is the timeline's main tap/drag
  /// surface (scrub, scroll, tap-jump, pinch), so it gets a fat finger-friendly band.
  static const double _kRulerH = 40;

  Widget _ruler(TimelineLayout layout, {double labelInset = 0}) {
    final ruler = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _rulerDown(e, layout),
      onPointerMove: (e) => _rulerMove(e, layout),
      onPointerUp: (_) => _rulerUp(layout),
      onPointerCancel: (_) => _rulerUp(layout, cancel: true),
      child: CustomPaint(
        size: Size(layout.width, _kRulerH),
        painter: TimelineRulerPainter(
          layout: layout,
          playhead: _playing ? _playbackFrame() : _state.playhead,
          loopA: _state.loopA,
          loopB: _state.loopB,
          recordTint: _recordTint,
        ),
      ),
    );
    if (labelInset <= 0) return SizedBox(height: _kRulerH, child: ClipRect(child: ruler));
    // Tracks/Focus: lead with the label-column width so ruler x == lane x. ClipRect keeps
    // off-view painting (a scrolled-out playhead goes negative-x) inside the lane box.
    return SizedBox(
      height: _kRulerH,
      child: Row(children: [
        Container(width: labelInset, color: kLaneBg),
        Expanded(child: ClipRect(child: ruler)),
      ]),
    );
  }

  // Two-finger machine, shared by the ruler AND the lanes: zoom from the finger
  // distance, pan from the moving midpoint — the continuous frame captured under the
  // start midpoint stays under the live midpoint (a still-distance drag is a pure pan).
  void _startTimelinePinch(TimelineLayout layout) {
    _timelinePinching = true;
    final ps = _touchPos.values.toList();
    _tlPinchStartDist = (ps[0].dx - ps[1].dx).abs().clamp(1.0, double.infinity);
    _tlPinchStartPpf = _pxPerFrame;
    _tlPinchFocusFrame = layout.continuousFrameAt((ps[0].dx + ps[1].dx) / 2);
  }

  void _timelinePinchMove(TimelineLayout layout) {
    final ps = _touchPos.values.toList();
    if (ps.length < 2) return;
    final dist = (ps[0].dx - ps[1].dx).abs().clamp(1.0, double.infinity);
    final midX = (ps[0].dx + ps[1].dx) / 2;
    final next = layout.panZoomedTo(
        _tlPinchStartPpf * dist / _tlPinchStartDist, _tlPinchFocusFrame, midX);
    if (next.pxPerFrame != _pxPerFrame || next.scroll != _timeScroll) {
      setState(() {
        _pxPerFrame = next.pxPerFrame;
        _timeScroll = next.scroll;
      });
    }
  }

  // Ruler pointers (Tracks/Focus): grabbing the playhead cursor scrubs; one finger
  // anywhere else scrolls (the header has no keys by design — a free drag surface); a
  // tap jumps the playhead on release; two fingers pan/zoom time.
  void _rulerDown(PointerDownEvent e, TimelineLayout layout) {
    _touchPos[e.pointer] = e.localPosition;
    if (_touchPos.length >= 2) {
      _rulerMode = 0;
      _startTimelinePinch(layout);
      return;
    }
    final x = e.localPosition.dx;
    final shown = _playing ? _playbackFrame() : _state.playhead;
    if ((layout.xAtFrame(shown) - x).abs() <= kLoopHandleHitPx) {
      _rulerMode = 1; // the playhead is grabbed: scrub from the start
      _scrubTo(layout.frameAtX(x));
    } else {
      _rulerMode = 2; // pan candidate; a motionless release becomes a tap-jump
      _rulerPanDownX = x;
      _rulerPanScroll0 = _timeScroll;
      _rulerPanMoved = false;
    }
  }

  void _rulerMove(PointerMoveEvent e, TimelineLayout layout) {
    _touchPos[e.pointer] = e.localPosition;
    if (_timelinePinching) {
      _timelinePinchMove(layout);
      return;
    }
    switch (_rulerMode) {
      case 1:
        _scrubTo(layout.frameAtX(e.localPosition.dx));
      case 2:
        final dx = e.localPosition.dx - _rulerPanDownX;
        if (!_rulerPanMoved && dx.abs() > 6) _rulerPanMoved = true;
        if (!_rulerPanMoved) return;
        final ns = layout.clampScroll(_rulerPanScroll0 - dx);
        if (ns != _timeScroll) {
          final shifted = TimelineLayout(
            width: layout.width,
            frameCount: layout.frameCount,
            pxPerFrame: layout.pxPerFrame,
            scroll: ns,
            originX: layout.originX,
            rightInset: layout.rightInset,
            overscroll: layout.overscroll,
          );
          final (first, last) = shifted.visibleRange();
          _hintLive('frames ${first + 1} – ${last + 1}');
          setState(() => _timeScroll = ns);
        }
    }
  }

  void _rulerUp(TimelineLayout layout, {bool cancel = false}) {
    _touchPos.clear();
    _timelinePinching = false;
    if (!cancel && _rulerMode == 2 && !_rulerPanMoved) {
      _scrubTo(layout.frameAtX(_rulerPanDownX)); // the tap-jump, on release
    }
    _rulerMode = 0;
    _hintEnd();
  }

  Widget _trackLane(ActorState a, TimelineLayout layout, double laneH) {
    final selected = a.id == _state.selectedActor;
    return Row(children: [
      InkWell(
        onTap: () {
          // Tap-to-deselect: the selected actor's own label toggles it off.
          final wasSelected = a.id == _state.selectedActor;
          _sendSession(wasSelected ? 'SelectNone()' : 'SelectActor(${a.id})');
          if (wasSelected) _selTween = null;
          _refreshState();
          _overlayVN.value++;
          setState(() {});
        },
        child: Container(
          width: 72 * _chromeScale,
          height: laneH,
          color: const Color(0xFF1A1C1F),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            if (selected)
              Container(width: 3, height: laneH * 0.6, color: const Color(0xFF4080C0)),
            if (selected) const SizedBox(width: 4),
            Expanded(
              child: Text(a.name,
                  style: TextStyle(
                      fontSize: 11, color: selected ? Colors.white : Colors.white60),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            InkWell(
              onTap: () {
                _focusActor = a.id;
                _setTimelineZoom(TimelineZoom.focus);
              },
              child: const Icon(Icons.unfold_more, size: 14, color: Colors.white38),
            ),
          ]),
        ),
      ),
      Expanded(
        child: ClipRect(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _laneDown(e, a, layout),
            onPointerMove: (e) => _laneMove(e, layout),
            onPointerUp: (e) => _laneUp(e),
            onPointerCancel: (e) => _laneUp(e),
            child: CustomPaint(
              size: Size(layout.width, laneH),
              painter: TrackLanePainter(
                layout: layout,
                keyFrames: a.keyFrames(),
                playhead: _playing ? _playbackFrame() : _state.playhead,
                selected: selected,
                selectedFrame: _selTween?.$1 == a.id ? _selTween?.$3 : null,
                draggedFrom: _keyDrag?.$1 == a.id ? _keyDrag?.$3 : null,
                draggedTo: _keyDragTo,
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  void _clearLaneGesture() {
    _keyDrag = null;
    _keyDragTo = null;
    _tlArmedMove = null;
    _tlSelectCandidate = null;
    _tlDragMoved = false;
  }

  void _laneDown(PointerDownEvent e, ActorState a, TimelineLayout layout) {
    _touchPos[e.pointer] = e.localPosition;
    if (_touchPos.length >= 2) {
      // Second finger: the lane joins the pan/zoom machine; drop any nascent gesture.
      _clearLaneGesture();
      _hintEnd();
      _startTimelinePinch(layout);
      return;
    }
    final x = e.localPosition.dx;
    _tlDownX = x;
    _tlDragMoved = false;
    // What a TAP here selects: the key tick under the finger, else nearest at/left.
    int? hitFrame;
    double best = kKeyHitPx + 1;
    for (final f in a.keyFrames()) {
      final d = (layout.xAtFrame(f) - x).abs();
      if (d < best) {
        best = d;
        hitFrame = f;
      }
    }
    if (hitFrame != null) {
      _tlSelectCandidate = (a.id, null, hitFrame);
    } else {
      final f = layout.frameAtX(x);
      final lefts = a.keyFrames().where((k) => k <= f).toList()..sort();
      _tlSelectCandidate = lefts.isEmpty ? null : (a.id, null, lefts.last);
    }
    // A drag moves the SELECTED key, and only in its own actor's lane (strict
    // select-then-drag). Armed here, live on first real movement.
    final st = _selTween;
    _tlArmedMove = (st != null && st.$1 == a.id) ? (st.$1, st.$2, st.$3) : null;
  }

  void _laneMove(PointerMoveEvent e, TimelineLayout layout) {
    _touchPos[e.pointer] = e.localPosition;
    if (_timelinePinching) {
      _timelinePinchMove(layout);
      return;
    }
    final dx = e.localPosition.dx - _tlDownX;
    if (!_tlDragMoved && dx.abs() > 6) {
      _tlDragMoved = true;
      final armed = _tlArmedMove;
      if (armed != null) {
        if (_playing) _pause();
        _keyDrag = armed;
        _keyDragTo = armed.$3;
      }
    }
    final kd = _keyDrag;
    if (kd == null || !_tlDragMoved) return;
    // Relative retime: the key moves by the drag's frame delta (never jumps to the
    // finger — the drag may start anywhere in the lane).
    var f = (kd.$3 + (dx / layout.pxPerFrame).round())
        .clamp(0, _state.frameCount - 1);
    final magnets = <int>{
      ..._state.allKeyFrames().where((k) => k != kd.$3),
      _state.loopA,
      _state.loopB,
    };
    final snapped = snapFrame(f, magnets);
    if (snapped != f) HapticFeedback.selectionClick();
    f = snapped;
    _hintLive('frame ${kd.$3 + 1} → ${f + 1}');
    if (f != _keyDragTo) setState(() => _keyDragTo = f);
  }

  void _laneUp(PointerEvent e) {
    _touchPos.remove(e.pointer);
    if (_timelinePinching) {
      if (_touchPos.length < 2) {
        _timelinePinching = false;
        _touchPos.clear();
        _clearLaneGesture();
      }
      return;
    }
    final kd = _keyDrag;
    final to = _keyDragTo;
    final cand = _tlSelectCandidate;
    final moved = _tlDragMoved;
    _clearLaneGesture();
    _hintEnd();
    if (moved) {
      // A drag either moves the selected key or does nothing at all — it NEVER changes
      // the selection (only a clean tap selects, matching the stage grammar).
      if (kd == null) return;
      if (to == null || to == kd.$3) {
        setState(() {});
        return;
      }
      if (kd.$2 == null) {
        _act('MoveActorKeys(${kd.$1}, ${kd.$3}, $to)');
      } else {
        _act('MoveKey(${kd.$1}, ${_dslProp(kd.$2!)}, ${kd.$3}, $to)');
      }
      _selTween = (kd.$1, kd.$2, to); // the selection follows the moved key
      return;
    }
    // A clean tap: select — or toggle the already-selected key off (freeing the lane
    // from drag-moves-the-selected-key mode); the actor selection stays.
    if (cand != null) {
      final st = _selTween;
      if (st != null && st.$1 == cand.$1 && st.$2 == cand.$2 && st.$3 == cand.$3) {
        setState(() => _selTween = null);
        _hintFlash('Key deselected');
        return;
      }
      if (cand.$1 != _state.selectedActor) {
        _sendSession('SelectActor(${cand.$1})');
        _refreshState();
      }
      setState(() => _selTween = cand);
      _hintFlash('Frame ${cand.$3 + 1} selected · drag this lane to move it');
    }
  }

  // ---- Focus -------------------------------------------------------------------------------

  Widget _focusBand(TimelineLayout layout, double s, double laneCap) {
    final actor = _state.actor(_focusActor) ?? _state.selected;
    if (actor == null) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text('Select an actor to focus its tracks',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
        ),
      );
    }
    final rowH = 26.0 * s;
    // Posing actors get a Pose row (hold keys) under the five standard properties.
    final rows = [...kFocusTracks, if (!actor.playing) 'pose'];
    final rowsH = math.min(rows.length * rowH, laneCap);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 24,
        child: Row(children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: 'Back to Tracks',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _setTimelineZoom(TimelineZoom.tracks),
          ),
          Text(actor.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
        ]),
      ),
      _ruler(layout, labelInset: 72 * _chromeScale),
      SizedBox(
        height: rowsH,
        child: ListView(
          children: [
            for (final prop in rows) _propertyRow(actor, prop, layout, rowH),
          ],
        ),
      ),
    ]);
  }

  Widget _propertyRow(ActorState a, String prop, TimelineLayout layout, double rowH) {
    final t = a.tracks[prop]!;
    final keys = [for (final k in t.keys) FocusKey(k.frame, k.tween)];
    return Row(children: [
      Container(
        width: 72 * _chromeScale,
        height: rowH,
        color: const Color(0xFF1A1C1F),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        child: Text(_propLabel(prop),
            style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ),
      Expanded(
        child: ClipRect(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _rowDown(e, a, prop, layout),
            onPointerMove: (e) => _laneMove(e, layout),
            onPointerUp: (e) => _laneUp(e),
            onPointerCancel: (e) => _laneUp(e),
            child: CustomPaint(
              size: Size(layout.width, rowH),
              painter: PropertyRowPainter(
                layout: layout,
                keys: keys,
                playhead: _playing ? _playbackFrame() : _state.playhead,
                selectedKeyFrame:
                    _selTween?.$1 == a.id && _selTween?.$2 == prop ? _selTween?.$3 : null,
                draggedFrom:
                    _keyDrag?.$1 == a.id && _keyDrag?.$2 == prop ? _keyDrag?.$3 : null,
                draggedTo: _keyDragTo,
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  String _propLabel(String prop) => switch (prop) {
        'x' => 'X',
        'y' => 'Y',
        'rot' => 'Rotation',
        'scale' => 'Scale',
        'opacity' => 'Opacity',
        'pose' => 'Pose',
        _ => prop,
      };

  void _rowDown(PointerDownEvent e, ActorState a, String prop, TimelineLayout layout) {
    _touchPos[e.pointer] = e.localPosition;
    if (_touchPos.length >= 2) {
      _clearLaneGesture();
      _hintEnd();
      _startTimelinePinch(layout);
      return;
    }
    final t = a.tracks[prop]!;
    final x = e.localPosition.dx;
    _tlDownX = x;
    _tlDragMoved = false;
    int? hitFrame;
    double best = kKeyHitPx + 1;
    for (final k in t.keys) {
      final d = (layout.xAtFrame(k.frame) - x).abs();
      if (d < best) {
        best = d;
        hitFrame = k.frame;
      }
    }
    _tlSelectCandidate = hitFrame == null ? null : (a.id, prop, hitFrame);
    // A Focus drag moves the selected key only in ITS OWN property row.
    final st = _selTween;
    _tlArmedMove = (st != null && st.$1 == a.id && st.$2 == prop)
        ? (st.$1, st.$2, st.$3)
        : null;
  }

  // ---- hint strip --------------------------------------------------------------------------

  /// The bottom-most band: passive text over the safe-area pad (the one thing the mandatory
  /// OS gesture zone tolerates — R2). Live values during gestures via [_hintVN]; a context
  /// hint when idle. Mirrors the editor's tooltip band, single line.
  Widget _buildHintStrip({bool compact = false}) {
    final inset = MediaQuery.of(context).viewPadding.bottom;
    final minPad = compact ? 8.0 : 16.0;
    final gesturePad = inset < minPad ? minPad : inset;
    final double stripHeight = 6 + 13.75 + 6 + gesturePad;
    return IgnorePointer(
      child: Container(
        height: stripHeight,
        color: const Color(0xFF0E1012),
        padding: EdgeInsets.fromLTRB(12, 6, 12, gesturePad),
        alignment: Alignment.topLeft,
        child: ValueListenableBuilder<String?>(
          valueListenable: _hintVN,
          builder: (_, live, _) => Text(
            live ?? _idleHint(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ),
      ),
    );
  }

  String _idleHint() {
    if (_state.actors.isEmpty) return 'Import a prop to begin';
    final sel = _state.selected;
    if (sel == null) return 'Tap an actor to select · two fingers pan and zoom';
    return _stageMode == _StageMode.rotate
        ? 'Drag to orbit the pivot · snaps every 15°'
        : 'Drag anywhere to move · the pill switches to Rotate';
  }
}
