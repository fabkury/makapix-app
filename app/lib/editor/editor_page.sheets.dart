part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _EditorPageState — see editor_page.timeline.dart for the rationale.)

// The long-press bottom sheets of the timeline strips (layers + frames), rebuilt as
// "grouped zones": an identity header (thumbnail + name), a state zone whose controls keep
// the sheet open (toggle chips, opacity, reorder), sectioned action rows sharing one button
// idiom, and the destructive action isolated at the bottom. Both sheets share the small
// building blocks below so they stay visually in lockstep.
extension _EditorSheets on _EditorPageState {

  // Reorder a layer while keeping the move-group membership pointing at the same layers
  // (the group is a set of indices, so a reorder must swap the two slots' membership).
  void _reorderLayerTracked(int from, int to) {
    final hadFrom = _selLayers.remove(from);
    final hadTo = _selLayers.remove(to);
    if (hadFrom) _selLayers.add(to);
    if (hadTo) _selLayers.add(from);
    _act('ReorderLayer($from, $to)');
    if (_selLayers.length > 1) _syncLayerSel();
  }

  // ── the layer sheet ───────────────────────────────────────────────────────

  // Long-press menu of a layer tile. State-zone controls (chips, opacity, Up/Down) keep the
  // sheet open and update the canvas live; structural actions dismiss it. `cur` tracks the
  // layer as Up/Down move it through the stack, and each rebuild re-reads the layer's state
  // from the engine (the captured map would go stale while the sheet stays open).
  void _layerOptions(int initial) {
    int cur = initial;
    int? dragOpacity; // non-null while the opacity slider is being dragged
    showAppSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final layers = _layerList();
        if (layers.isEmpty) return const SizedBox.shrink();
        if (cur >= layers.length) cur = layers.length - 1;
        final l = layers[cur] as Map<String, dynamic>;
        final count = layers.length;
        final visible = l['visible'] == true;
        final locked = l['locked'] == true;
        final inGroup = _selLayers.contains(cur);
        final belowLocked = cur > 0 && (layers[cur - 1] as Map<String, dynamic>)['locked'] == true;
        final opacity = dragOpacity ?? ((l['opacity'] ?? 255) as int);

        final frame = engine.activeFrame;
        final hash = engine.layerHash(frame, cur);
        final key = _layerKey(frame, cur);
        final cached = _layerThumbs[key];
        if (cached == null || cached.hash != hash) {
          _genLayerThumb(frame, cur, hash).then((_) {
            if (ctx.mounted) setS(() {});
          });
        }

        return sheetScaffold([
          sheetHeader(
            thumb: cached?.img, // stale-while-revalidate: old thumb beats a checkerboard flash
            title: '${l['name']}',
            subtitle: 'Layer ${cur + 1} of $count',
            onRename: () {
              Navigator.pop(ctx);
              _renameLayer(cur, '${l['name']}');
            },
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            stateChip(
              icon: visible ? Icons.visibility : Icons.visibility_off,
              label: 'Visible',
              value: visible,
              onChanged: (v) {
                _act('SetLayerVisible($cur, $v)');
                setS(() {});
              },
            ),
            stateChip(
              icon: locked ? Icons.lock : Icons.lock_open,
              label: 'Locked',
              value: locked,
              onChanged: (v) {
                _act('SetLayerLocked($cur, $v)');
                setS(() {});
              },
            ),
            stateChip(
              icon: Icons.open_with,
              label: 'Move group',
              value: inGroup,
              accent: const Color(0x59FFC107), // translucent amber, matching the tile badge
              tooltip: 'Move together with the Move tool (when nothing is selected)',
              onChanged: (v) {
                setState(() {
                  if (v) {
                    _selLayers.add(cur);
                  } else {
                    _selLayers.remove(cur);
                  }
                });
                _syncLayerSel();
                setS(() {});
              },
            ),
          ]),
          Row(children: [
            const Icon(Icons.opacity, size: 18, color: Colors.white70),
            const SizedBox(width: 4),
            const Text('Opacity'),
            Expanded(
              child: Slider(
                value: opacity.toDouble(),
                max: 255,
                onChanged: (v) {
                  setS(() => dragOpacity = v.round());
                  _send('SetLayerOpacity($cur, ${v.round()})');
                  _redraw();
                },
                onChangeEnd: (_) {
                  _refreshState();
                  setState(() {});
                  setS(() => dragOpacity = null);
                },
              ),
            ),
            SizedBox(
              width: 40,
              // Tap-to-type, the editor-wide slider convention (underline = tappable). Raw
              // engine units (0–255), matching what the dialog accepts.
              child: InkWell(
                onTap: () => _editSliderValue('Opacity', opacity.toDouble(), 0, 255, (v) {
                  _act('SetLayerOpacity($cur, ${v.round()})');
                  setS(() {});
                }, integer: true),
                borderRadius: BorderRadius.circular(4),
                child: Text('$opacity',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white24)),
              ),
            ),
          ]),
          sheetSection('Arrange'),
          sheetBtnRow([
            sheetBtn(Icons.arrow_upward, 'Up', cur + 1 < count
                ? () {
                    _reorderLayerTracked(cur, cur + 1);
                    setS(() => cur++);
                  }
                : null),
            sheetBtn(Icons.arrow_downward, 'Down', cur > 0
                ? () {
                    _reorderLayerTracked(cur, cur - 1);
                    setS(() => cur--);
                  }
                : null),
            sheetBtn(Icons.call_merge, 'Merge down', (cur > 0 && !belowLocked)
                ? () {
                    Navigator.pop(ctx);
                    _clearLayerGroup(); // the engine collapses its group to the merged layer
                    _act('MergeDown($cur)');
                  }
                : null),
          ]),
          sheetSection('Create'),
          sheetBtnRow([
            sheetBtn(Icons.control_point_duplicate, 'Duplicate', () {
              Navigator.pop(ctx);
              _clearLayerGroup(); // focus moves to the copy; the engine resets its group too
              _act('DuplicateLayer($cur)');
            }),
            sheetBtn(Icons.add_box_outlined, 'New layer above', () {
              Navigator.pop(ctx);
              _clearLayerGroup();
              _act('AddLayerAt(${cur + 1})');
            }),
          ]),
          const SizedBox(height: 8),
          sheetBtn(Icons.dynamic_feed, 'Copy to all frames', () {
            Navigator.pop(ctx);
            final all = List.generate(engine.frameCount, (k) => k)
                .where((k) => k != engine.activeFrame)
                .join(',');
            if (all.isNotEmpty) {
              _clearLayerGroup(); // SetActiveLayer collapses the engine group to [cur]
              _act('SetActiveLayer($cur); DuplicateLayerToFrames($all)');
            }
          }),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 4),
          sheetDelete('Delete layer', count > 1
              ? () {
                  Navigator.pop(ctx);
                  _remapLayerGroupRemoved(cur); // matches the engine's own remap
                  _act('RemoveLayer($cur)');
                }
              : null),
        ]);
      }),
    );
  }

  // ── the frame sheet ───────────────────────────────────────────────────────

  // Long-press menu of a film-roll frame, mirroring the layer sheet's zones. Move left/right
  // keep the sheet open and `cur` tracks the frame across reorders; duration lives in the
  // state zone (tap opens the existing duration dialog for this frame).
  void _frameMenu(int initial) {
    int cur = initial;
    showAppSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final count = engine.frameCount;
        if (cur >= count) cur = count - 1;
        final frames = (_state['frame_detail'] as List?) ?? [];
        final us = cur < frames.length ? (((frames[cur]['duration_us'] as num?) ?? 100000).toInt()) : 100000;
        final ms = us / 1000.0;

        final hash = engine.frameHash(cur);
        final cached = _frameThumbs[cur];
        if (cached == null || cached.hash != hash) {
          _genFrameThumb(cur, hash).then((_) {
            if (ctx.mounted) setS(() {});
          });
        }

        return sheetScaffold([
          sheetHeader(
            thumb: cached?.img, // stale-while-revalidate: old thumb beats a checkerboard flash
            title: 'Frame ${cur + 1} of $count',
            subtitle: '${ms.toStringAsFixed(1)} ms · ${(1000 / ms).toStringAsFixed(1)} fps',
          ),
          const SizedBox(height: 12),
          sheetBtn(Icons.timer_outlined, 'Edit duration…', () {
            Navigator.pop(ctx);
            if (cur != engine.activeFrame) _clearLayerGroup(); // frame switch invalidates the group
            _act('SetActiveFrame($cur)');
            _editDuration();
          }),
          sheetSection('Arrange'),
          sheetBtnRow([
            sheetBtn(Icons.chevron_left, 'Move left', cur > 0
                ? () {
                    _act('ReorderFrame($cur, ${cur - 1})');
                    setS(() => cur--);
                  }
                : null),
            sheetBtn(Icons.chevron_right, 'Move right', cur + 1 < count
                ? () {
                    _act('ReorderFrame($cur, ${cur + 1})');
                    setS(() => cur++);
                  }
                : null),
          ]),
          sheetSection('Create'),
          sheetBtnRow([
            sheetBtn(Icons.control_point_duplicate, 'Duplicate', () {
              Navigator.pop(ctx);
              _clearLayerGroup(); // a different frame becomes active
              _act('DuplicateFrame($cur)');
            }),
            sheetBtn(Icons.add_box_outlined, 'New frame after', () {
              Navigator.pop(ctx);
              _clearLayerGroup();
              _act('AddFrameAt(${cur + 1})');
            }),
          ]),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 4),
          sheetDelete('Delete frame', count > 1
              ? () {
                  Navigator.pop(ctx);
                  _clearLayerGroup(); // a different frame (with its own layer stack) may become active
                  _act('RemoveFrame($cur)');
                }
              : null),
        ]);
      }),
    );
  }

  // Prompt for a new layer name and apply it. Canceling (or an empty name) leaves the layer as-is.
  // Newlines and ';' are stripped because they would split the DSL command; commas survive (the
  // parser keeps everything after the index as the name).
  Future<void> _renameLayer(int i, String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename layer'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Rename')),
        ],
      ),
    );
    if (name == null) return; // canceled
    final clean = name.replaceAll(RegExp(r'[\r\n;]'), ' ').trim();
    if (clean.isEmpty) return;
    _act('RenameLayer($i, $clean)');
  }
}
