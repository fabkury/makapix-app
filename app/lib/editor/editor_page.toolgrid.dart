part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// Row-3 reorderable tool grid + its tiles, the shared slider/toggle/mini-button
// controls, and the new-document dialog.
extension _EditorToolgrid on _EditorPageState {
  // `selected` = the active draw tool (blue). `active` = an on toggle like Onion/Play (amber).
  // `enabled` = false dims the tile (e.g. Undo/Redo when there's nothing to undo/redo).
  Widget _tileVisual(ToolDef t, {required bool selected, bool hover = false, bool active = false, bool enabled = true}) {
    final s = _chromeScale;
    final fg = selected ? Colors.white : (active ? Colors.amber : Colors.white70);
    final tile = Container(
      width: 54 * s,
      height: 42 * s,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF4080C0) : const Color(0xFF26292E),
        borderRadius: BorderRadius.circular(6),
        border: hover
            ? Border.all(color: Colors.amber, width: 2)
            : (active ? Border.all(color: Colors.amber, width: 1.5) : null),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          t.iconWidget(size: 18 * s, color: fg),
          const SizedBox(height: 1),
          Text(t.label,
              style: TextStyle(fontSize: 8.5 * s, color: active ? Colors.amber : null), maxLines: 1, overflow: TextOverflow.clip),
        ],
      ),
    );
    return enabled ? tile : Opacity(opacity: 0.4, child: tile);
  }

  bool _actionActive(String dsl) => dsl == 'Onion' && _onion;

  bool _actionEnabled(String dsl) {
    // A pending move draft makes Undo/Redo live so either can discard it (see _doToolAction), even
    // when there's no committed history to step through.
    if (dsl == 'Undo') return _hasMoveDraft || _state['can_undo'] == true;
    if (dsl == 'Redo') return _hasMoveDraft || _state['can_redo'] == true;
    return true;
  }

  // Fire an action tool's action/toggle (not a tool selection).
  void _doToolAction(String dsl) {
    switch (dsl) {
      case 'Undo':
        // Undo/Redo first discard an in-progress move draft (same as navigating away or Cancel);
        // they only step the committed history once no draft is pending.
        if (_hasMoveDraft) {
          _cancelMoveDraft();
        } else if (_state['can_undo'] == true) {
          _act('Undo()');
        }
        break;
      case 'Redo':
        if (_hasMoveDraft) {
          _cancelMoveDraft();
        } else if (_state['can_redo'] == true) {
          _act('Redo()');
        }
        break;
      case 'Onion':
        setState(() => _onion = !_onion);
        _redraw();
        break;
    }
  }

  // A single row-3 tool tile. Tap selects; long-press-drag reorders with live preview. `others` is
  // the order minus the dragged tool, used to map a hovered tile to a drop index.
  Widget _toolTile(String dsl, List<String> others) {
    final isAction = _actionTools.contains(dsl);
    final t = _toolDef(dsl);
    final selected = !isAction && dsl == _tool;
    final active = isAction && _actionActive(dsl);
    final enabled = !isAction || _actionEnabled(dsl);
    final isDragged = dsl == _dragTool;
    // A GlobalKey so the dragged tile's State (and its ongoing drag) survives being re-parented
    // between the top and bottom Rows as the live preview reflows. Also used to read its bounds.
    final key = GlobalObjectKey('toolslot_$dsl');
    return DragTarget<String>(
      key: key,
      onWillAcceptWithDetails: (d) => d.data != dsl,
      onMove: (d) {
        final oi = others.indexOf(dsl);
        if (oi < 0) return;
        var insert = oi;
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        if (box != null) {
          final center = box.localToGlobal(box.size.center(Offset.zero));
          if (d.offset.dx > center.dx) insert = oi + 1; // dropped on the right half → after
        }
        if (_dropIndex != insert) setState(() => _dropIndex = insert);
      },
      builder: (ctx, cand, rej) {
        // While dragged, this tile shows a placeholder gap at its live position (the preview slot).
        final gap = Container(
          width: 54 * _chromeScale,
          height: 42 * _chromeScale,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.amber, width: 2),
            color: const Color(0x224080C0),
          ),
        );
        return LongPressDraggable<String>(
          data: dsl,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => setState(() {
            _dragTool = dsl;
            // start the gap where the tool currently sits (insertion index into the others list,
            // in visible space — the grid may hide the pinned tile in 3-row mode)
            final visible = _visibleOrder(_toolOrder);
            _dropIndex = visible.indexOf(dsl).clamp(0, visible.length - 1);
          }),
          onDragEnd: (_) => _commitToolDrag(),
          feedback: Material(color: Colors.transparent, child: _tileVisual(t, selected: true)),
          childWhenDragging: gap,
          child: GestureDetector(
            onTap: () => isAction ? _doToolAction(dsl) : _selectTool(dsl),
            child: _tileVisual(t, selected: selected && !isDragged, active: active, enabled: enabled),
          ),
        );
      },
    );
  }

  // A pinned action tile (Undo/Redo): fixed at the left of row-3, never scrolls, not reorderable.
  Widget _pinnedActionTile(ToolDef def) {
    return GestureDetector(
      onTap: () => _doToolAction(def.dsl),
      child: _tileVisual(def, selected: false, enabled: _actionEnabled(def.dsl)),
    );
  }

  // The pinned 3rd tile (3-row mode only): defaults to Play, but long-press picks any tool. It tap-
  // routes exactly like the grid's tile for that tool — an action tool (Onion) toggles via
  // _doToolAction; every other tool (incl. Play, whose controls live in row-1) selects via
  // _selectTool — so each tool keeps the behaviour it has in the grid.
  Widget _pinnedThirdTile() {
    final dsl = _pinnedThirdTool;
    final isAction = _actionTools.contains(dsl);
    final t = _toolDef(dsl);
    final selected = !isAction && dsl == _tool;
    final active = isAction && _actionActive(dsl);
    final enabled = !isAction || _actionEnabled(dsl);
    return GestureDetector(
      onTap: () => isAction ? _doToolAction(dsl) : _selectTool(dsl),
      onLongPress: _pinnedThirdConfigSheet,
      child: _tileVisual(t, selected: selected, active: active, enabled: enabled),
    );
  }

  // Long-press the pinned 3rd slot → pick which tool it holds. Lists every tool (Undo/Redo are the
  // fixed slots 1&2 and never appear in `tools`); the choice hides the tool from the grid and
  // persists. Leading uses iconWidget (not a raw Icon) because tool icons can be custom MpxIcons.
  void _pinnedThirdConfigSheet() {
    showAppSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => _sheetScaffold(ctx, [
        _sheetSection('Pinned tool'),
        for (final t in tools)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: t.dsl == _pinnedThirdTool,
            selectedTileColor: const Color(0x224080C0),
            leading: t.iconWidget(size: 22, color: t.dsl == _pinnedThirdTool ? Colors.white : Colors.white70),
            title: Text(t.label),
            trailing: t.dsl == _pinnedThirdTool ? const Icon(Icons.check, color: Color(0xFF4080C0)) : null,
            onTap: () {
              Navigator.pop(ctx);
              if (t.dsl == _pinnedThirdTool) return;
              setState(() => _pinnedThirdTool = t.dsl);
              _persistPinnedThirdTool();
            },
          ),
      ]),
    );
  }

  Widget _buildToolBar({Axis axis = Axis.horizontal}) {
    // Render from the live display order (visible space: 3-row mode hides the pinned tile, which is
    // pinned beside Undo/Redo instead). Long-press any tile to drag it; the rest reflow in real time, and the order
    // is committed on release. The "others" list (visible order minus the dragged tool) is the
    // index space for drop positions.
    //
    // Portrait: N bands of tiles scrolling horizontally, pinned Undo/Redo column at the left.
    // Landscape (vertical): the grid transposes — N tiles per row, rows scrolling vertically,
    // pinned Undo/Redo (+3rd) as a fixed top row. Tiles flow row-major left→right in BOTH modes,
    // so the drag-reorder drop-index math is shared.
    final vertical = axis == Axis.vertical;
    final order = _displayToolOrder();
    final others = _dragTool == null ? order : _visibleOrder(_toolOrder.where((t) => t != _dragTool).toList());
    final n = order.length;
    final bandsN = _threeRowToolbar ? 3 : 2; // portrait: band count; landscape: tiles per row
    final perBand = vertical ? bandsN : (n + bandsN - 1) ~/ bandsN;
    final bandCount = vertical ? (n + perBand - 1) ~/ perBand : bandsN;
    final gridRows = [
      for (var r = 0; r < bandCount; r++)
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = r * perBand; i < n && i < (r + 1) * perBand; i++) _toolTile(order[i], others),
        ]),
    ];
    // Undo / Redo (+ the configurable 3rd tile in 3-row/3-wide mode) pinned — fixed, don't scroll
    // with the rest.
    final pinned = Flex(
      direction: vertical ? Axis.horizontal : Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _pinnedActionTile(undoToolDef),
        _pinnedActionTile(redoToolDef),
        if (_threeRowToolbar) _pinnedThirdTile(),
      ],
    );
    final grid = SingleChildScrollView(
      scrollDirection: axis,
      child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: gridRows),
    );
    // Band size derives from the (possibly tablet-scaled) tile size: tile + 3px margin each side,
    // plus 4px of band padding in the fixed dimension.
    final s = _chromeScale;
    if (vertical) {
      return Container(
        width: bandsN * (54 * s + 6),
        color: const Color(0xFF15171A),
        child: Column(children: [
          pinned,
          Container(height: 1, color: Colors.black26),
          Expanded(child: grid),
        ]),
      );
    }
    return Container(
      height: bandsN * (42 * s + 6) + 4,
      color: const Color(0xFF15171A),
      child: Row(children: [
        pinned,
        Container(width: 1, color: Colors.black26),
        Expanded(child: grid),
      ]),
    );
  }

  Widget _slider(double v, double min, double max, ValueChanged<double> onChanged) {
    return SizedBox(
      width: 120,
      child: _GearedSlider(value: v, min: min, max: max, onChanged: onChanged),
    );
  }

  // A row-1 slider with a tappable label: tapping the "Name value" label opens a numeric
  // text-entry dialog so the exact value can be typed instead of dragged. The text path and
  // the drag path share the same [onChanged], keeping behaviour identical.
  void _labeledSlider(List<Widget> children, String name, double value, double min, double max,
      ValueChanged<double> onChanged, {bool integer = true, int decimals = 1}) {
    final shown = integer ? value.round().toString() : value.toStringAsFixed(decimals);
    children.add(InkWell(
      onTap: () => _editSliderValue(name, value, min, max, onChanged, integer: integer, decimals: decimals),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Text('$name $shown',
            style: const TextStyle(
                fontSize: 11,
                color: Colors.white60,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white24)),
      ),
    ));
    children.add(_slider(value, min, max, onChanged));
  }

  // Like _labeledSlider, but the slider position is LOGARITHMIC across [min,max], so the geometric
  // midpoint (e.g. 1.0 for 0.2..5) sits at the centre and each half spans the same ratio. The label
  // taps to type an exact value. `onChanged` receives the real value (not the slider position).
  void _labeledLogSlider(List<Widget> children, String name, double value, double min, double max,
      ValueChanged<double> onChanged) {
    final v = value.clamp(min, max);
    final lmin = math.log(min), lmax = math.log(max);
    double posOf(double x) => (math.log(x) - lmin) / (lmax - lmin); // value → 0..1
    double valOf(double t) => math.exp(lmin + t * (lmax - lmin)); // 0..1 → value
    children.add(InkWell(
      onTap: () => _editSliderValue(name, v, min, max, onChanged, integer: false),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Text('$name ${v.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 11,
                color: Colors.white60,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white24)),
      ),
    ));
    children.add(_slider(posOf(v), 0, 1, (t) => onChanged(valOf(t))));
  }

  // Like _labeledSlider, but the slider position follows a POWER curve across [min,max]
  // (value = min + (max−min)·t^γ with γ = _kPowSliderGamma): the low end of the range gets more
  // track than linear without the full log treatment (for 1..400, the track centre sits at ~100
  // vs linear's 200 and log's ~20). `onChanged` receives the real value (not the slider position).
  void _labeledPowSlider(List<Widget> children, String name, double value, double min, double max,
      ValueChanged<double> onChanged, {bool integer = true}) {
    final v = value.clamp(min, max);
    double posOf(double x) => math.pow((x - min) / (max - min), 1 / _kPowSliderGamma).toDouble();
    double valOf(double t) => min + (max - min) * math.pow(t, _kPowSliderGamma);
    final shown = integer ? v.round().toString() : v.toStringAsFixed(1);
    children.add(InkWell(
      onTap: () => _editSliderValue(name, v, min, max, onChanged, integer: integer),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Text('$name $shown',
            style: const TextStyle(
                fontSize: 11,
                color: Colors.white60,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white24)),
      ),
    ));
    children.add(_slider(posOf(v), 0, 1, (t) => onChanged(valOf(t))));
  }

  Future<void> _editSliderValue(String name, double value, double min, double max,
      ValueChanged<double> onChanged, {required bool integer, int decimals = 1}) async {
    String fmt(double d) => integer ? d.round().toString() : d.toStringAsFixed(decimals);
    final ctrl = TextEditingController(text: integer ? value.round().toString() : value.toStringAsFixed(2));
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    final entered = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: !integer, signed: min < 0),
          decoration: InputDecoration(labelText: 'Value (${fmt(min)} – ${fmt(max)})'),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())), child: const Text('OK')),
        ],
      ),
    );
    if (entered != null && entered.isFinite) {
      onChanged(entered.clamp(min, max).toDouble());
    }
  }

  Widget _toggle(List<String> opts, int sel, ValueChanged<int> onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ToggleButtons(
        isSelected: List.generate(opts.length, (i) => i == sel),
        onPressed: onTap,
        constraints: const BoxConstraints(minHeight: 30, minWidth: 44),
        borderRadius: BorderRadius.circular(6),
        children: opts
            .map((o) => Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(o, style: const TextStyle(fontSize: 11))))
            .toList(),
      ),
    );
  }

  Widget _miniBtn(String s, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: const Color(0xFF2E3237),
        ),
        onPressed: onTap,
        child: Text(s, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _swatchButton(Color c, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white54))),
      ),
    );
  }

  Future<void> _newDialog() async {
    final size = await showDialog<(int, int)>(
      context: context,
      builder: (_) => const _NewDocumentDialog(),
    );
    if (size != null) {
      final (w, h) = size;
      // A new canvas is a new library drawing; the previous one stays saved in My Drawings.
      await _switchToNewDrawing(title: 'Untitled', mutateEngine: () {
        _send('NewDocument($w,$h)');
        _send('SelectTool($_tool)');
        _clubSource = null;
      });
      if (mounted) {
        _refreshState();
        _redraw();
        setState(() {});
      }
    }
  }
}

// The New-document dialog: free-form width × height in the engine's full 1–256 range, with
// square presets as shortcuts. Sizes Makapix Club won't accept (the hardcoded ClubSizeRules:
// free-form band + small-size whitelist) get a red alert but remain creatable — the editor
// is deliberately not limited to publishable sizes. Pops `(w, h)` on Create.
class _NewDocumentDialog extends StatefulWidget {
  const _NewDocumentDialog();
  @override
  State<_NewDocumentDialog> createState() => _NewDocumentDialogState();
}

class _NewDocumentDialogState extends State<_NewDocumentDialog> {
  final _w = TextEditingController(text: '64');
  final _h = TextEditingController(text: '64');

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  int? _dim(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    return (v != null && v >= 1 && v <= 256) ? v : null;
  }

  Widget _field(TextEditingController c, String label) {
    return Expanded(
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 3,
        decoration: InputDecoration(labelText: label, counterText: '', isDense: true),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = _dim(_w), h = _dim(_h);
    final valid = w != null && h != null;
    final clubOk = !valid || ClubSizeRules.accepted(w, h);
    return AlertDialog(
      title: const Text('New document'),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _field(_w, 'Width'),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('×')),
            _field(_h, 'Height'),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, children: [
            for (final p in [16, 32, 64, 128, 256])
              ActionChip(
                label: Text('$p²'),
                onPressed: () => setState(() {
                  _w.text = '$p';
                  _h.text = '$p';
                }),
              ),
          ]),
          if (!valid) ...[
            const SizedBox(height: 10),
            const Text('Each side must be 1–256 pixels.', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
          if (valid && !clubOk) ...[
            const SizedBox(height: 10),
            _ClubSizeAlert(w, h),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: valid ? () => Navigator.pop(context, (w, h)) : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

// Tuning knob for the row-1 geared sliders: pixels of pointer travel per pixel of thumb travel.
// 1.0 restores direct (ungeared) dragging; higher makes the sliders "heavier" and easier to land
// on an exact number. Deliberately not user-configurable — adjust here on tester feedback.
const double _kSliderGearRatio = 4.0;

// Tuning knob for _labeledPowSlider's curve: 1.0 is linear, higher shifts ever more track toward
// the low end (log-like). 2.0 (square-root positioning) is the middle-of-the-road choice.
const double _kPowSliderGamma = 2.0;

// A Slider whose drag is geared down by [_kSliderGearRatio]: pointer travel is divided by the
// ratio before moving the thumb, so exact values are easy to hit. Pressing the track never jumps
// the thumb — only dragging moves it (the tappable "Name value" label covers typed exact values).
class _GearedSlider extends StatefulWidget {
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const _GearedSlider({required this.value, required this.min, required this.max, required this.onChanged});

  @override
  State<_GearedSlider> createState() => _GearedSliderState();
}

class _GearedSliderState extends State<_GearedSlider> {
  // Unrounded value accumulated across the current drag. Integer sliders round what we report and
  // hand the rounded value back on rebuild, so sub-unit progress must be kept here or slow drags
  // would never cross a unit boundary. Null when not dragging (then the parent's value is shown).
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final v = (_dragValue ?? widget.value).clamp(widget.min, widget.max);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => setState(() => _dragValue = v),
      onHorizontalDragUpdate: (d) {
        // Material insets the track by the 24px thumb-overlay radius on each side.
        final trackWidth = math.max(1.0, (context.size?.width ?? 120) - 48);
        final dv = d.delta.dx / _kSliderGearRatio / trackWidth * (widget.max - widget.min);
        // Clamp the accumulator itself so reversing at an end responds immediately.
        setState(() => _dragValue = ((_dragValue ?? v) + dv).clamp(widget.min, widget.max));
        widget.onChanged(_dragValue!);
      },
      onHorizontalDragEnd: (_) => setState(() => _dragValue = null),
      onHorizontalDragCancel: () => setState(() => _dragValue = null),
      // The Slider is display-only (the GestureDetector owns all input); the no-op onChanged
      // keeps it in the enabled visual state.
      child: AbsorbPointer(
        child: Slider(value: v, min: widget.min, max: widget.max, onChanged: (_) {}),
      ),
    );
  }
}

// Red informational alert: the given size isn't accepted by Makapix Club (the hardcoded
// ClubSizeRules). Shown in the New-document and Resize-canvas dialogs; never blocks either —
// the editor deliberately allows non-publishable sizes.
class _ClubSizeAlert extends StatelessWidget {
  final int width, height;
  const _ClubSizeAlert(this.width, this.height);

  @override
  Widget build(BuildContext context) {
    final nearest = ClubSizeRules.nearest(width, height);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Makapix Club doesn\'t accept $width × $height artworks, so it can\'t be posted '
            'to the Club at this size.\nNearest accepted size: ${nearest[0]} × ${nearest[1]}.',
            style: const TextStyle(fontSize: 12, color: Colors.redAccent),
          ),
        ),
      ]),
    );
  }
}
