part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _EditorPageState — see editor_page.timeline.dart for the rationale.)

// The long-press bottom sheets of the timeline strips (layers + frames), rebuilt as
// "grouped zones": an identity header (thumbnail + name), a state zone whose controls keep
// the sheet open (toggle chips, opacity, reorder), sectioned action rows sharing one button
// idiom, and the destructive action isolated at the bottom. Both sheets share the small
// building blocks below so they stay visually in lockstep.
extension _EditorSheets on _EditorPageState {
  // ── shared building blocks ────────────────────────────────────────────────

  // Identity thumbnail on the transparent checkerboard, matching the strip tiles.
  Widget _sheetThumb(ThumbCache? cached) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF101214),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black26),
        ),
        padding: const EdgeInsets.all(2),
        child: CustomPaint(
          painter: const CheckerPainter(),
          child: cached != null
              ? RawImage(image: cached.img, fit: BoxFit.contain, filterQuality: FilterQuality.none)
              : const SizedBox.shrink(),
        ),
      );

  // Header: thumbnail + bold title (+ optional rename affordance) + muted subtitle.
  Widget _sheetHeader({
    required ThumbCache? thumb,
    required String title,
    required String subtitle,
    VoidCallback? onRename,
  }) =>
      Row(children: [
        _sheetThumb(thumb),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: onRename,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis),
                ),
                if (onRename != null) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.edit, size: 14, color: Colors.white54),
                ],
              ]),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ]),
        ),
      ]);

  Widget _sheetSection(String label) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, letterSpacing: 1.2, color: Colors.white38, fontWeight: FontWeight.w600)),
      );

  // One action button; every non-destructive action in the sheets uses this idiom.
  Widget _sheetBtn(IconData icon, String label, VoidCallback? onTap) => FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis, maxLines: 1),
      );

  // A row of equal-width action buttons.
  Widget _sheetBtnRow(List<Widget> buttons) => Row(children: [
        for (var k = 0; k < buttons.length; k++) ...[
          if (k > 0) const SizedBox(width: 8),
          Expanded(child: buttons[k]),
        ],
      ]);

  // The lone destructive action at the bottom of a sheet.
  Widget _sheetDelete(String label, VoidCallback? onTap) => SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          onPressed: onTap,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(label),
        ),
      );

  // An icon toggle chip for the state zone (visible / locked / move-group).
  Widget _stateChip({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? accent,
    String? tooltip,
  }) {
    final chip = FilterChip(
      showCheckmark: false,
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: value,
      selectedColor: accent,
      visualDensity: VisualDensity.compact,
      onSelected: onChanged,
    );
    return tooltip != null ? Tooltip(message: tooltip, child: chip) : chip;
  }

  Widget _sheetScaffold(BuildContext ctx, List<Widget> children) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children),
          ),
        ),
      );

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

  // The live mini-stack: a read-only mirror of the layers film strip inside the layer sheet,
  // so Up/Down reordering stays visible while the sheet covers the real strip (portrait puts
  // it at the bottom of the screen, exactly where every bottom sheet rises). Index order
  // left→right = bottom→top of stack, matching the strip. Blue border = the sheet's layer,
  // amber = move-group members, dimmed = hidden. Built lazily so big stacks only regenerate
  // the thumbnails actually on screen.
  Widget _sheetLayerStrip({
    required List<dynamic> layers,
    required int cur,
    required int frame,
    required ScrollController controller,
    required double tileW,
    required VoidCallback refresh,
    required ValueChanged<int> onTap,
  }) =>
      SizedBox(
        height: 44,
        child: StripScroller(
          axis: Axis.horizontal,
          controller: controller,
          child: ListView.builder(
            controller: controller,
            scrollDirection: Axis.horizontal,
            itemExtent: tileW + 4,
            itemCount: layers.length,
            itemBuilder: (_, i) {
              final l = layers[i] as Map<String, dynamic>;
              final hash = engine.layerHash(frame, i);
              final cached = _layerThumbs[_layerKey(frame, i)];
              if (cached == null || cached.hash != hash) {
                _genLayerThumb(frame, i, hash).then((_) => refresh());
              }
              final sel = i == cur;
              final inGroup = _selLayers.contains(i);
              return GestureDetector(
                // Retarget the sheet only (like long-pressing the tile on the real strip):
                // the engine's active layer stays put, so no side effect survives the sheet.
                onTap: () => onTap(i),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101214),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: sel ? const Color(0xFF4080C0) : (inGroup ? Colors.amber : Colors.black26),
                      width: (sel || inGroup) ? 2 : 1,
                    ),
                  ),
                  child: Opacity(
                    opacity: l['visible'] == true ? 1 : 0.35,
                    child: CustomPaint(
                      painter: const CheckerPainter(),
                      child: cached != null
                          ? RawImage(image: cached.img, fit: BoxFit.contain, filterQuality: FilterQuality.none)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

  // Long-press menu of a layer tile. Everything except rename and Copy to all frames keeps the
  // sheet open so repeated taps chain: `cur` tracks the layer as Up/Down move it through the
  // stack, follows a duplicate/new layer/merge result, and the builder's clamp catches it after
  // a delete. Each rebuild re-reads the layer's state from the engine (the captured map would
  // go stale while the sheet stays open).
  void _layerOptions(int initial) {
    if (_playing) _pause();
    int cur = initial;
    int? dragOpacity; // non-null while the opacity slider is being dragged
    // [G-30] The opacity the drag STARTED from. History records store the frame as it was just
    // before the recorded edit, and the previews have already moved it — so the pre-drag value is
    // restored (silently) an instant before the one committing SetLayerOpacity, or Undo would
    // restore the previewed value and appear to do nothing.
    int? preDragOpacity;
    // Mini-stack scroll state. The fixed tile extent keeps offsets computable without layout
    // queries (the _ensureActiveFrameVisible precedent); showCur centers the sheet's layer.
    final (tw, th) = _thumbSize();
    final stripTileW = (40.0 * tw / th).clamp(26.0, 72.0);
    final stripCtrl = ScrollController();
    var stripScrolledIn = false;
    void showCur({bool animate = true}) {
      if (!stripCtrl.hasClients) return;
      final pos = stripCtrl.position;
      final ext = stripTileW + 4;
      final target =
          (cur * ext - (pos.viewportDimension - ext) / 2).clamp(0.0, pos.maxScrollExtent);
      if (animate) {
        stripCtrl.animateTo(target,
            duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      } else {
        stripCtrl.jumpTo(target);
      }
    }

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
        final blend = '${l['blend'] ?? 'Normal'}';

        final frame = engine.activeFrame;
        final hash = engine.layerHash(frame, cur);
        final key = _layerKey(frame, cur);
        final cached = _layerThumbs[key];
        if (cached == null || cached.hash != hash) {
          _genLayerThumb(frame, cur, hash).then((_) {
            if (ctx.mounted) setS(() {});
          });
        }

        if (!stripScrolledIn) {
          stripScrolledIn = true; // open already scrolled to the pressed layer's tile
          WidgetsBinding.instance.addPostFrameCallback((_) => showCur(animate: false));
        }

        return _sheetScaffold(ctx, [
          if (count > 1) ...[
            _sheetLayerStrip(
              layers: layers,
              cur: cur,
              frame: frame,
              controller: stripCtrl,
              tileW: stripTileW,
              refresh: () {
                if (ctx.mounted) setS(() {});
              },
              onTap: (i) {
                setS(() {
                  cur = i;
                  dragOpacity = null; // the new layer's opacity reads fresh from the engine
                });
                showCur();
              },
            ),
            const SizedBox(height: 8),
          ],
          _sheetHeader(
            thumb: cached, // stale-while-revalidate: old thumb beats a checkerboard flash
            title: '${l['name']}',
            subtitle: 'Layer ${cur + 1} of $count',
            onRename: () {
              Navigator.pop(ctx);
              _renameLayer(cur, '${l['name']}');
            },
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _stateChip(
              icon: visible ? Icons.visibility : Icons.visibility_off,
              label: 'Visible',
              value: visible,
              onChanged: (v) {
                _act('SetLayerVisible($cur, $v)');
                setS(() {});
              },
            ),
            _stateChip(
              icon: locked ? Icons.lock : Icons.lock_open,
              label: 'Locked',
              value: locked,
              onChanged: (v) {
                _act('SetLayerLocked($cur, $v)');
                setS(() {});
              },
            ),
            _stateChip(
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
                  if (_controlDragDead) return; // a Command ended this drag [ADR 0010]
                  // Latch the drag as an in-flight Gesture, with a revert to the pre-drag value.
                  preDragOpacity ??= opacity;
                  _beginControlDrag(opacity.toDouble(), (pv) {
                    _send('SetLayerOpacityPreview($cur, ${pv.round()})');
                    _redraw();
                  });
                  setS(() => dragOpacity = v.round());
                  // [G-30] Preview only — no undo record, no Journal line. The single
                  // committing SetLayerOpacity is sent from onChangeEnd below.
                  _send('SetLayerOpacityPreview($cur, ${v.round()})');
                  _redraw();
                },
                onChangeEnd: (v) {
                  _endControlDrag();
                  // Rewind the (unrecorded) preview to where the drag began, so the committing
                  // record snapshots the ORIGINAL opacity as its "before" and Undo really undoes.
                  final pre = preDragOpacity;
                  if (pre != null) _send('SetLayerOpacityPreview($cur, $pre)');
                  // [G-30] ONE undoable step for the whole drag — the same granularity the
                  // typed-entry path has always had.
                  _act('SetLayerOpacity($cur, ${v.round()})');
                  _refreshState();
                  setState(() {});
                  setS(() {
                    dragOpacity = null;
                    preDragOpacity = null;
                  });
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
          Row(children: [
            const Icon(Icons.gradient, size: 18, color: Colors.white70),
            const SizedBox(width: 4),
            const Text('Blend'),
            const Spacer(),
            InkWell(
              onTap: () async {
                await _blendPicker(cur);
                if (ctx.mounted) setS(() {}); // reveal the committed mode
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(blendDisplayName(blend), style: const TextStyle(color: Colors.white70)),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.white54),
                ]),
              ),
            ),
          ]),
          _sheetSection('Arrange'),
          _sheetBtnRow([
            _sheetBtn(Icons.arrow_upward, 'Up', cur + 1 < count
                ? () {
                    _reorderLayerTracked(cur, cur + 1);
                    setS(() => cur++);
                    showCur();
                  }
                : null),
            _sheetBtn(Icons.arrow_downward, 'Down', cur > 0
                ? () {
                    _reorderLayerTracked(cur, cur - 1);
                    setS(() => cur--);
                    showCur();
                  }
                : null),
            _sheetBtn(Icons.call_merge, 'Merge down', (cur > 0 && !belowLocked)
                ? () {
                    _clearLayerGroup(); // the engine collapses its group to the merged layer
                    _act('MergeDown($cur)');
                    setS(() => cur--); // follow the merged result below
                    // Post-frame: the strip must relayout its shrunken roll first.
                    WidgetsBinding.instance.addPostFrameCallback((_) => showCur());
                  }
                : null),
          ]),
          _sheetSection('Create'),
          _sheetBtnRow([
            _sheetBtn(Icons.control_point_duplicate, 'Duplicate', () {
              _clearLayerGroup(); // focus moves to the copy; the engine resets its group too
              _act('DuplicateLayer($cur)');
              // Follow the copy (the engine made it active) — unless the layer cap
              // made the verb a silent no-op.
              setS(() {
                if (_layerList().length > count) cur++;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) => showCur());
            }),
            _sheetBtn(Icons.add_box_outlined, 'New layer above', () {
              _clearLayerGroup();
              _act('AddLayerAt(${cur + 1})');
              setS(() {
                if (_layerList().length > count) cur++;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) => showCur());
            }),
          ]),
          const SizedBox(height: 8),
          _sheetBtn(Icons.dynamic_feed, 'Copy to all frames', () {
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
          _sheetDelete('Delete layer', count > 1
              ? () {
                  _remapLayerGroupRemoved(cur); // matches the engine's own remap
                  _act('RemoveLayer($cur)');
                  setS(() => cur = cur.clamp(0, count - 2)); // count-1 layers remain
                  WidgetsBinding.instance.addPostFrameCallback((_) => showCur());
                }
              : null),
        ]);
      }),
    ).whenComplete(stripCtrl.dispose);
  }

  // Grouped blend-mode picker, apply-on-close: taps preview live via PreviewLayerBlend (a
  // direct engine mutation, no undo record), and closing by ANY path — pop, swipe, back —
  // first restores the original, then commits the selection iff it changed as ONE undo step
  // (SetLayerBlend; the engine's equality guard backstops the check). An autosave firing
  // mid-preview could persist the previewed mode; the window is the open sheet, accepted.
  Future<void> _blendPicker(int cur) async {
    final layers = _layerList();
    if (cur >= layers.length) return;
    final orig = '${(layers[cur] as Map<String, dynamic>)['blend'] ?? 'Normal'}';
    var sel = orig;
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => _sheetScaffold(ctx, [
          for (final (label, modes) in kBlendGroups) ...[
            _sheetSection(label),
            for (final m in modes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                selected: m == sel,
                selectedTileColor: const Color(0x224080C0),
                title: Text(blendDisplayName(m)),
                trailing:
                    m == sel ? const Icon(Icons.check, color: Color(0xFF4080C0)) : null,
                onTap: () {
                  setS(() => sel = m);
                  _send('PreviewLayerBlend($cur, $m)');
                  _redraw();
                },
              ),
          ],
        ]),
      ),
    );
    // Restore BEFORE committing so edit_frame snapshots the true original as `before`.
    _send('PreviewLayerBlend($cur, $orig)');
    if (sel != orig) {
      _act('SetLayerBlend($cur, $sel)');
    } else {
      _redraw();
    }
  }

  // ── the frame sheet ───────────────────────────────────────────────────────

  // Long-press menu of a film-roll frame, mirroring the layer sheet's zones. Every action keeps
  // the sheet open so repeated taps chain (move-move-move, duplicate-duplicate, delete-delete):
  // `cur` tracks the frame across reorders, follows a new duplicate/blank, and the builder's
  // clamp catches it after a delete. Duration lives in the state zone (tap opens the existing
  // duration dialog for this frame).
  void _frameMenu(int initial) {
    if (_playing) _pause();
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

        return _sheetScaffold(ctx, [
          _sheetHeader(
            thumb: cached, // stale-while-revalidate: old thumb beats a checkerboard flash
            title: 'Frame ${cur + 1} of $count',
            subtitle: '${ms.toStringAsFixed(1)} ms · ${(1000 / ms).toStringAsFixed(1)} fps',
          ),
          const SizedBox(height: 12),
          _sheetBtn(Icons.timer_outlined, 'Edit duration…', () {
            Navigator.pop(ctx);
            // [G-36] Act on the named frame; no activation, so cancelling costs nothing and the
            // artist's drawing target never moves behind a dialog (ADR 0013).
            _editDuration(frame: cur);
          }),
          _sheetSection('Arrange'),
          _sheetBtnRow([
            _sheetBtn(Icons.chevron_left, 'Move left', cur > 0
                ? () {
                    _act('ReorderFrame($cur, ${cur - 1})');
                    setS(() => cur--);
                  }
                : null),
            _sheetBtn(Icons.chevron_right, 'Move right', cur + 1 < count
                ? () {
                    _act('ReorderFrame($cur, ${cur + 1})');
                    setS(() => cur++);
                  }
                : null),
          ]),
          _sheetSection('Create'),
          _sheetBtnRow([
            _sheetBtn(Icons.control_point_duplicate, 'Duplicate', () {
              _clearLayerGroup(); // a different frame becomes active
              _act('DuplicateFrame($cur)');
              // Follow the copy (the engine made it active) — unless the frame cap
              // made the verb a silent no-op.
              setS(() {
                if (engine.frameCount > count) cur++;
              });
            }),
            _sheetBtn(Icons.add_box_outlined, 'New frame after', () {
              _clearLayerGroup();
              _act('AddFrameAt(${cur + 1})');
              setS(() {
                if (engine.frameCount > count) cur++;
              });
            }),
          ]),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 4),
          _sheetDelete('Delete frame', count > 1
              ? () {
                  _clearLayerGroup(); // a different frame (with its own layer stack) may become active
                  _act('RemoveFrame($cur)');
                  setS(() {}); // the builder clamps cur to the shrunken roll
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
