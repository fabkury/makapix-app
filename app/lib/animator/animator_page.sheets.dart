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
