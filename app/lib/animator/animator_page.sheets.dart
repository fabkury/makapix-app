part of 'animator_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _AnimatorPageState — the editor part files' rationale: extensions on a State
// subclass trip a false positive calling the @protected setState.)

// The bottom sheets — built from the shared chrome (lib/ui/chrome_sheets.dart): the Cast
// sheet (props: place, style, rename, remove), the Actor sheet (visibility, opacity,
// z-order, duplicate, delete), the Transform sheet (scale, rotation, position, pivot,
// flips — the non-gestural transforms, 06-gesture-safety §4.3: scale is deliberately not a
// gesture), and Scene settings (fps, frames, auto-key).
extension _AnimatorSheets on _AnimatorPageState {
  Future<ui.Image?> _thumbFromRgba(Uint8List rgba, int tw, int th) async {
    if (rgba.isEmpty) return null;
    premultiplyRgbaInPlace(rgba);
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, tw, th, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  // ---- Cast sheet --------------------------------------------------------------------------

  Future<void> _castSheet() async {
    if (!_engineReady) return;
    if (_playing) _pause(); // also stops the warm loop competing with the thumb renders below
    // Pre-render prop thumbnails (fresh copies; disposed when the sheet closes).
    final thumbs = <int, ui.Image?>{};
    for (final p in _state.cast) {
      thumbs[p.id] = await _thumbFromRgba(engine.propThumb(p.id, 48, 48), 48, 48);
    }
    if (!mounted) return;
    await showAppSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return sheetScaffold([
          sheetHeader(
            thumb: null,
            title: 'Cast',
            subtitle: '${_state.cast.length} props · ${_state.actors.length} actors on stage',
          ),
          sheetSection('Add'),
          sheetBtnRow([
            sheetBtn(Icons.add_photo_alternate_outlined, 'Import prop…', () {
              Navigator.pop(ctx);
              _importPropFlow();
            }),
          ]),
          if (_state.cast.isNotEmpty) sheetSection('Props'),
          for (final p in _state.cast)
            ListTile(
              dense: true,
              leading: SizedBox(width: 40, height: 40, child: sheetThumb(thumbs[p.id])),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${p.w}×${p.h} · ${p.frames} frame${p.frames == 1 ? '' : 's'}'
                '${p.frames > 1 ? ' · cycle ${p.cycleLen}' : ''} · ${p.style == 'cleanedge' ? 'cleanEdge' : 'nearest'}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'place':
                      Navigator.pop(ctx);
                      _act('PlaceActor(${p.id})');
                    case 'style':
                      _act(
                          'SetPropStyle(${p.id}, ${p.style == 'cleanedge' ? 'nearest' : 'cleanedge'})');
                      setSheet(() {});
                    case 'cycle':
                      await _cycleSpeedDialog(p);
                      setSheet(() {});
                    case 'rename':
                      Navigator.pop(ctx);
                      _renameProp(p);
                    case 'remove':
                      Navigator.pop(ctx);
                      _removePropConfirm(p);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'place', child: Text('Place on stage')),
                  PopupMenuItem(
                      value: 'style',
                      child: Text(p.style == 'cleanedge'
                          ? 'Switch to nearest (chunky)'
                          : 'Switch to cleanEdge (crisp)')),
                  if (p.frames > 1)
                    const PopupMenuItem(value: 'cycle', child: Text('Cycle speed…')),
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(value: 'remove', child: Text('Remove…')),
                ],
              ),
            ),
        ]);
      }),
    );
    for (final img in thumbs.values) {
      img?.dispose();
    }
  }

  Future<void> _renameProp(CastEntryState p) async {
    final ctrl = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename prop'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            onSubmitted: (s) => Navigator.pop(ctx, s.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      _act('RenameProp(${p.id}, $name)');
    }
  }

  /// Drop a motion preset's keys at the playhead (one undo step — the whole batch rides
  /// one gesture bracket) and close the sheet so the result is immediately scrubbed.
  void _applyPreset(BuildContext sheetCtx, int actorId, PresetKind k) {
    final a = _state.actor(actorId);
    if (a == null) return;
    final dsl = buildPreset(
      k,
      actorId: actorId,
      playhead: _state.playhead,
      millifps: _state.millifps,
      frameCount: _state.frameCount,
      pose: a.pose,
      canvasW: _state.w,
      canvasH: _state.h,
    );
    if (dsl == null) {
      _toast('Not enough frames after the playhead — move it earlier.');
      return;
    }
    Navigator.pop(sheetCtx);
    _act(dsl);
    _hintFlash('${presetLabel(k)} · keys from frame ${_state.playhead + 1}');
  }

  // ---- Pin to… -----------------------------------------------------------------------------

  /// Pick a pin target (or unpin). Eligible parents per the engine's one-level rule:
  /// any other actor that is itself unpinned. Returns via pops: target id, -1 = unpin.
  Future<void> _pinPickerFlow(int actorId) async {
    final a0 = _state.actor(actorId);
    if (a0 == null) return;
    final targets =
        _state.actors.where((o) => o.id != actorId && o.pinTo == null).toList();
    final thumbs = <int, ui.Image?>{};
    for (final t in targets) {
      thumbs[t.id] = await _thumbFromRgba(engine.actorThumb(t.id, 40, 40), 40, 40);
    }
    if (!mounted) {
      for (final img in thumbs.values) {
        img?.dispose();
      }
      return;
    }
    final choice = await showAppSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('Pin "${a0.name}" to',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          if (a0.pinTo != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.link_off, size: 20),
              title: const Text('None — unpin'),
              onTap: () => Navigator.pop(ctx, -1),
            ),
          for (final t in targets)
            ListTile(
              dense: true,
              leading: SizedBox(width: 40, height: 40, child: sheetThumb(thumbs[t.id])),
              title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: t.id == a0.pinTo
                  ? Icon(Icons.check, size: 18, color: Theme.of(ctx).colorScheme.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, t.id),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    for (final img in thumbs.values) {
      img?.dispose();
    }
    if (choice == null || !mounted) return;
    if (choice == -1) {
      _unpinActor(actorId);
    } else if (choice != a0.pinTo) {
      _pinActor(actorId, choice);
    }
  }

  /// Pin with keep-position compensation: compute the child's world pose (unwrapping an
  /// existing pin first), pin, then rewrite its transform tracks so nothing moves on
  /// screen. Two undo steps by construction — the pin meta record cannot join the
  /// gesture-bracketed track rewrite.
  void _pinActor(int childId, int parentId) {
    final c = _state.actor(childId);
    final np = _state.actor(parentId);
    if (c == null || np == null) return;
    var world = PinXf(
      x: c.pose.x,
      y: c.pose.y,
      rotMdeg: c.pose.rotMdeg,
      scaleMilli: c.pose.scaleMilli,
      flipH: c.pose.flipH,
      flipV: c.pose.flipV,
    );
    if (c.pinTo != null) {
      final op = _state.actor(c.pinTo);
      if (op != null) world = worldForLocal(parent: op.pose, local: c.pose);
    }
    _act('SetPinTo($childId, $parentId)');
    if (_state.actor(childId)?.pinTo != parentId) {
      _toast("Couldn't pin — pins are one level only.");
      return;
    }
    final local = localForWorld(parent: np.pose, world: _asPose(world));
    _applyPoseRewrite(childId, c, local);
    _hintFlash('Pinned to ${np.name}');
  }

  /// Unpin with keep-position compensation (world pose from the current parent, then
  /// the tracks rewritten in scene space).
  void _unpinActor(int childId) {
    final c = _state.actor(childId);
    if (c == null || c.pinTo == null) return;
    final p = _state.actor(c.pinTo);
    final world = p == null ? null : worldForLocal(parent: p.pose, local: c.pose);
    _act('ClearPin($childId)');
    if (world != null) _applyPoseRewrite(childId, c, world);
    _hintFlash('Unpinned');
  }

  PoseState _asPose(PinXf x) => PoseState(
      x: x.x,
      y: x.y,
      rotMdeg: x.rotMdeg,
      scaleMilli: x.scaleMilli,
      flipH: x.flipH,
      flipV: x.flipV);

  /// Rewrite the transform tracks so the value AT THE PLAYHEAD becomes [target], in one
  /// gesture-bracketed batch (one undo record): keyless tracks get a new base; keyed
  /// x/y/rot shift base + every key by the additive delta (tweens preserved); keyed
  /// scale/flips are left untouched (rare — world appearance may change there).
  void _applyPoseRewrite(int id, ActorState before, PinXf target) {
    final parts = <String>['BeginGesture()'];
    void additive(String prop, int oldVal, int newVal) {
      final t = before.tracks[prop]!;
      final token = _dslProp(prop);
      if (!t.hasKeys) {
        if (newVal != oldVal) parts.add('SetBase($id, $token, $newVal)');
      } else {
        final d = newVal - oldVal;
        if (d == 0) return;
        parts.add('SetBase($id, $token, ${t.base + d})');
        for (final k in t.keys) {
          parts.add('SetKeyTween($id, $token, ${k.frame}, ${k.v + d}, ${k.tween})');
        }
      }
    }

    additive('x', before.pose.x, target.x);
    additive('y', before.pose.y, target.y);
    additive('rot', before.pose.rotMdeg, target.rotMdeg);
    if (!before.tracks['scale']!.hasKeys && target.scaleMilli != before.pose.scaleMilli) {
      parts.add('SetBase($id, scale, ${target.scaleMilli})');
    }
    if (!before.tracks['flip_h']!.hasKeys && target.flipH != before.pose.flipH) {
      parts.add('SetBase($id, fliph, ${target.flipH ? 1 : 0})');
    }
    if (!before.tracks['flip_v']!.hasKeys && target.flipV != before.pose.flipV) {
      parts.add('SetBase($id, flipv, ${target.flipV ? 1 : 0})');
    }
    parts.add('EndGesture()');
    if (parts.length > 2) _act(parts.join('; '));
  }

  /// Uniform Cycle speed for a multi-frame Prop: scene frames each prop frame holds for
  /// (SetCycleAll). Sent only on a real change — a no-op still invalidates the engine's
  /// transform cache for the prop.
  Future<void> _cycleSpeedDialog(CastEntryState p) async {
    var step = (p.uniformStep ?? 1).clamp(1, 8);
    final applied = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Cycle speed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.uniformStep == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                      'This prop has mixed per-frame steps — applying sets one uniform speed.',
                      style: TextStyle(fontSize: 12, color: Colors.white54)),
                ),
              Row(children: [
                miniBtn('−', () => setD(() => step = (step - 1).clamp(1, 8))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                      '$step scene frame${step == 1 ? '' : 's'} per prop frame',
                      style: const TextStyle(fontSize: 13)),
                ),
                miniBtn('+', () => setD(() => step = (step + 1).clamp(1, 8))),
              ]),
              const SizedBox(height: 6),
              Text('${p.frames} × $step = ${p.frames * step} scene frames per loop',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, step), child: const Text('Apply')),
          ],
        );
      }),
    );
    if (applied != null && applied != p.uniformStep) {
      _act('SetCycleAll(${p.id}, $applied)');
    }
  }

  Future<void> _removePropConfirm(CastEntryState p) async {
    final users = _state.actors.where((a) => a.prop == p.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove prop?'),
        content: Text(users == 0
            ? '"${p.name}" will be removed from the cast.'
            : '"${p.name}" and its $users actor${users == 1 ? '' : 's'} will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) _act('RemoveProp(${p.id})');
  }

  // ---- Actor sheet -------------------------------------------------------------------------

  Future<void> _actorSheet(int actorId) async {
    final a0 = _state.actor(actorId);
    if (a0 == null) return;
    if (_playing) _pause();
    final thumb = await _thumbFromRgba(engine.actorThumb(actorId, 48, 48), 48, 48);
    if (!mounted) return;
    await showAppSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final a = _state.actor(actorId);
        if (a == null) return const SizedBox.shrink();
        final prop = _state.prop(a.prop);
        return sheetScaffold([
          sheetHeader(
            thumb: thumb,
            title: a.name,
            subtitle:
                '${prop?.name ?? '?'} · z ${a.z + 1}/${_state.actors.length}',
            onRename: () {
              Navigator.pop(ctx);
              _renameActor(a);
            },
          ),
          sheetSection('State'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            stateChip(
              icon: Icons.visibility_outlined,
              label: 'Visible',
              value: a.visible,
              onChanged: (v) {
                _act('SetActorVisible(${a.id}, $v)');
                setSheet(() {});
              },
            ),
            if ((prop?.frames ?? 1) > 1)
              stateChip(
                icon: Icons.filter_frames,
                label: 'Posing',
                value: !a.playing,
                tooltip: 'Playing loops the prop\'s own Cycle. Posing holds one '
                    'chosen frame — step poses from the pill; pose keys are hold keys.',
                onChanged: (v) {
                  _act('SetActorMode(${a.id}, ${v ? 'posing' : 'playing'})');
                  setSheet(() {});
                },
              ),
          ]),
          const SizedBox(height: 6),
          Builder(builder: (_) {
            final children = <Widget>[];
            labeledSlider(ctx, children, 'Opacity', a.pose.opacity.toDouble(), 0, 255, (v) {
              _act('SetAtPlayhead(${a.id}, opacity, ${v.round()})');
              setSheet(() {});
            });
            return Row(children: children);
          }),
          sheetSection('Transform'),
          sheetBtnRow([
            sheetBtn(Icons.open_with, 'Transform…', () {
              Navigator.pop(ctx);
              _transformSheet(a.id);
            }),
          ]),
          sheetSection('Pin'),
          Builder(builder: (_) {
            final parent = a.pinTo == null ? null : _state.actor(a.pinTo);
            final hasChildren = _state.actors.any((o) => o.pinTo == a.id);
            final targets = _state.actors
                .where((o) => o.id != a.id && o.pinTo == null)
                .isNotEmpty;
            final blocked = a.pinTo == null && (hasChildren || !targets);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              sheetBtnRow([
                sheetBtn(
                  Icons.push_pin_outlined,
                  parent == null ? 'Pin to…' : 'Pinned to ${parent.name}',
                  blocked
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _pinPickerFlow(a.id);
                        },
                ),
              ]),
              if (hasChildren && a.pinTo == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Other actors are pinned to this one (one level only).',
                      style: TextStyle(fontSize: 11, color: Colors.white38)),
                ),
            ]);
          }),
          sheetSection('Presets'),
          sheetBtnRow([
            sheetBtn(Icons.sports_basketball_outlined, 'Bounce',
                () => _applyPreset(ctx, a.id, PresetKind.bounce)),
            sheetBtn(Icons.login, 'Slide in',
                () => _applyPreset(ctx, a.id, PresetKind.slideIn)),
            sheetBtn(Icons.rotate_right, 'Spin',
                () => _applyPreset(ctx, a.id, PresetKind.spin)),
          ]),
          sheetBtnRow([
            sheetBtn(Icons.vibration, 'Shake',
                () => _applyPreset(ctx, a.id, PresetKind.shake)),
            sheetBtn(Icons.bubble_chart_outlined, 'Pop',
                () => _applyPreset(ctx, a.id, PresetKind.pop)),
          ]),
          sheetSection('Arrange'),
          sheetBtnRow([
            sheetBtn(Icons.keyboard_double_arrow_up, 'Raise',
                a.z < _state.actors.length - 1 ? () {
                  _act('ReorderActor(${a.z}, ${a.z + 1})');
                  setSheet(() {});
                } : null),
            sheetBtn(Icons.keyboard_double_arrow_down, 'Lower',
                a.z > 0 ? () {
                  _act('ReorderActor(${a.z}, ${a.z - 1})');
                  setSheet(() {});
                } : null),
            sheetBtn(Icons.copy, 'Duplicate', () {
              Navigator.pop(ctx);
              _act('DuplicateActor(${a.id})');
            }),
          ]),
          sheetSection('Keys'),
          sheetBtnRow([
            sheetBtn(Icons.layers_clear_outlined, 'Clear all keys', () {
              Navigator.pop(ctx);
              _clearActorKeysConfirm(a);
            }),
          ]),
          const SizedBox(height: 4),
          sheetDelete('Delete actor', () {
            Navigator.pop(ctx);
            _act('RemoveActor(${a.id})');
          }),
        ]);
      }),
    );
    thumb?.dispose();
  }

  Future<void> _renameActor(ActorState a) async {
    final ctrl = TextEditingController(text: a.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename actor'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            onSubmitted: (s) => Navigator.pop(ctx, s.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      _act('RenameActor(${a.id}, $name)');
    }
  }

  Future<void> _clearActorKeysConfirm(ActorState a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all keys?'),
        content: Text(
            '"${a.name}" keeps its current pose; every key on every track is removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final parts = <String>['BeginGesture()'];
    for (final name in kTrackNames) {
      parts.add('ClearTrack(${a.id}, ${_dslProp(name)})');
    }
    parts.add('EndGesture()');
    _act(parts.join('; '));
  }

  // ---- Transform sheet ---------------------------------------------------------------------

  /// The non-gestural transforms' one home (06-gesture-safety §4.3): scale (deliberately not
  /// a gesture — pixel art overwhelmingly wants 1:1), precise rotation/position, pivot
  /// numerics, and flips. Everything routes through SetAtPlayhead, so auto-key records these
  /// edits exactly like stage gestures.
  Future<void> _transformSheet(int actorId) async {
    if (_state.actor(actorId) == null) return;
    await showAppSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final a = _state.actor(actorId);
        if (a == null) return const SizedBox.shrink();
        void send(String dsl) {
          _act(dsl);
          setSheet(() {});
        }

        return sheetScaffold([
          sheetHeader(thumb: null, title: 'Transform', subtitle: a.name),
          sheetSection('Scale'),
          Builder(builder: (_) {
            final children = <Widget>[];
            labeledPowSlider(ctx, children, '×', a.pose.scaleMilli / 1000.0, 0.1, 8.0,
                (v) {
              final snapped = snapScale((v * 1000).round()); // the 1.0 detent
              send('SetAtPlayhead(${a.id}, scale, ${snapped.value.clamp(100, 8000)})');
            }, integer: false);
            return Row(children: children);
          }),
          sheetSection('Rotation'),
          Builder(builder: (_) {
            final children = <Widget>[];
            labeledSlider(ctx, children, 'Degrees',
                normalizeMdeg(a.pose.rotMdeg) / 1000.0, -180, 180, (v) {
              send('SetAtPlayhead(${a.id}, rot, ${(v * 1000).round()})');
            });
            return Row(children: children);
          }),
          sheetSection('Position'),
          _numRow(ctx, 'X', a.pose.x.toDouble(),
              (v) => send('SetAtPlayhead(${a.id}, x, ${v.round()})')),
          _numRow(ctx, 'Y', a.pose.y.toDouble(),
              (v) => send('SetAtPlayhead(${a.id}, y, ${v.round()})')),
          sheetSection('Pivot'),
          _numRow(ctx, 'Pivot X', a.pose.pivotXMilli / 1000.0,
              (v) => send('SetAtPlayhead(${a.id}, pivotx, ${(v * 1000).round()})'),
              integer: false),
          _numRow(ctx, 'Pivot Y', a.pose.pivotYMilli / 1000.0,
              (v) => send('SetAtPlayhead(${a.id}, pivoty, ${(v * 1000).round()})'),
              integer: false),
          sheetSection('Flip'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            stateChip(
              icon: Icons.flip,
              label: 'Flip H',
              value: a.pose.flipH,
              onChanged: (v) => send('SetAtPlayhead(${a.id}, fliph, ${v ? 1 : 0})'),
            ),
            stateChip(
              icon: Icons.flip_camera_android,
              label: 'Flip V',
              value: a.pose.flipV,
              onChanged: (v) => send('SetAtPlayhead(${a.id}, flipv, ${v ? 1 : 0})'),
            ),
          ]),
          const SizedBox(height: 10),
        ]);
      }),
    );
  }

  /// A compact numeric stepper row: −/+ nudge by [step], the underlined value taps to type
  /// (the chrome sliders' exact-entry dialog). Position edits may exceed the canvas — the
  /// generous ±4096 bound is the typing clamp, not a semantic limit.
  Widget _numRow(BuildContext ctx, String name, double value, ValueChanged<double> onChanged,
      {bool integer = true, double step = 1, double min = -4096, double max = 4096}) {
    final shown = integer ? value.round().toString() : value.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
            width: 64,
            child: Text(name,
                style: const TextStyle(fontSize: 12, color: Colors.white60))),
        miniBtn('−', () => onChanged((value - step).clamp(min, max))),
        InkWell(
          onTap: () => editSliderValue(ctx, name, value, min, max, onChanged,
              integer: integer, decimals: 2),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(shown,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white24)),
          ),
        ),
        miniBtn('+', () => onChanged((value + step).clamp(min, max))),
      ]),
    );
  }

  // ---- Scene settings ----------------------------------------------------------------------

  Future<void> _sceneSettingsSheet() async {
    await showAppSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return sheetScaffold([
          sheetHeader(
            thumb: null,
            title: _sceneTitle,
            subtitle: '${_state.w}×${_state.h}',
            onRename: () {
              Navigator.pop(ctx);
              _renameScene();
            },
          ),
          sheetSection('Frame rate'),
          Wrap(spacing: 6, children: [
            for (final f in kSceneFpsMilli)
              ChoiceChip(
                label: Text(fpsLabel(f), style: const TextStyle(fontSize: 12)),
                selected: _state.millifps == f,
                onSelected: (_) {
                  _act('SetFps($f)');
                  setSheet(() {});
                },
              ),
          ]),
          sheetSection('Duration'),
          Builder(builder: (_) {
            final children = <Widget>[];
            labeledSlider(
                ctx, children, 'Frames', _state.frameCount.toDouble(), 1, 1024, (v) {
              _act('SetFrameCount(${v.round()})');
              setSheet(() {});
            });
            return Row(children: children);
          }),
          sheetSection('Background'),
          Builder(builder: (_) {
            final argb = colorOfHex(_state.background) ?? 0x00000000;
            return Row(children: [
              swatchButton(Color(argb), () async {
                final picked = await showDialog<Color>(
                  context: ctx,
                  builder: (_) => ColorPickerDialog(initial: Color(argb)),
                );
                if (picked == null) return;
                final hex = hexOfColor(picked.toARGB32());
                if (hex == _state.background) return;
                _act('SetBackground($hex)');
                setSheet(() {});
              }),
              const SizedBox(width: 8),
              Text(_state.background,
                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Alpha 0 keeps the canvas transparent',
                    style: TextStyle(fontSize: 10, color: Colors.white38)),
              ),
            ]);
          }),
          sheetSection('Session'),
          Wrap(spacing: 8, children: [
            stateChip(
              icon: Icons.fiber_manual_record,
              label: 'Auto-key',
              value: _state.autoKey,
              accent: const Color(0x55CC4444),
              tooltip:
                  'On: manipulating an actor records a key at the playhead. Off: edits move the base pose.',
              onChanged: (v) {
                _sendSession('SetAutoKey($v)');
                _refreshState();
                setSheet(() {});
                setState(() {});
              },
            ),
          ]),
          const SizedBox(height: 10),
        ]);
      }),
    );
  }

  Future<void> _renameScene() async {
    if (_playing) _pause(); // reachable from the title tap, not only the menu
    final ctrl = TextEditingController(text: _sceneTitle);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename scene'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
            onSubmitted: (s) => Navigator.pop(ctx, s.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _sceneTitle = name);
    _autosave?.markActivity();
    await _autosave?.flushNow();
  }
}
