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

  // Long-press menu of a layer tile. State-zone controls (chips, opacity, Up/Down) keep the
  // sheet open and update the canvas live; structural actions dismiss it. `cur` tracks the
  // layer as Up/Down move it through the stack, and each rebuild re-reads the layer's state
  // from the engine (the captured map would go stale while the sheet stays open).
  void _layerOptions(int initial) {
    int cur = initial;
    int? dragOpacity; // non-null while the opacity slider is being dragged
    showModalBottomSheet(
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

        return _sheetScaffold(ctx, [
          _sheetHeader(
            thumb: (cached != null && cached.hash == hash) ? cached : null,
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
              child: Text('${(opacity * 100 / 255).round()}%', textAlign: TextAlign.end),
            ),
          ]),
          _sheetSection('Arrange'),
          _sheetBtnRow([
            _sheetBtn(Icons.arrow_upward, 'Up', cur + 1 < count
                ? () {
                    _reorderLayerTracked(cur, cur + 1);
                    setS(() => cur++);
                  }
                : null),
            _sheetBtn(Icons.arrow_downward, 'Down', cur > 0
                ? () {
                    _reorderLayerTracked(cur, cur - 1);
                    setS(() => cur--);
                  }
                : null),
            _sheetBtn(Icons.call_merge, 'Merge down', (cur > 0 && !belowLocked)
                ? () {
                    Navigator.pop(ctx);
                    _act('MergeDown($cur)');
                  }
                : null),
          ]),
          _sheetSection('Create'),
          _sheetBtnRow([
            _sheetBtn(Icons.control_point_duplicate, 'Duplicate', () {
              Navigator.pop(ctx);
              _act('DuplicateLayer($cur)');
            }),
            _sheetBtn(Icons.add_box_outlined, 'New layer above', () {
              Navigator.pop(ctx);
              _act('AddLayerAt(${cur + 1})');
            }),
          ]),
          const SizedBox(height: 8),
          _sheetBtn(Icons.dynamic_feed, 'Copy to all frames', () {
            Navigator.pop(ctx);
            final all = List.generate(engine.frameCount, (k) => k)
                .where((k) => k != engine.activeFrame)
                .join(',');
            if (all.isNotEmpty) _act('SetActiveLayer($cur); DuplicateLayerToFrames($all)');
          }),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 4),
          _sheetDelete('Delete layer', count > 1
              ? () {
                  Navigator.pop(ctx);
                  _act('RemoveLayer($cur)');
                }
              : null),
        ]);
      }),
    );
  }

  // Prompt for a new layer name and apply it. Cancelling (or an empty name) leaves the layer as-is.
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
    if (name == null) return; // cancelled
    final clean = name.replaceAll(RegExp(r'[\r\n;]'), ' ').trim();
    if (clean.isEmpty) return;
    _act('RenameLayer($i, $clean)');
  }
}
