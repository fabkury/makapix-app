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
    final fg = selected ? Colors.white : (active ? Colors.amber : Colors.white70);
    final tile = Container(
      width: 54,
      height: 42,
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
          Icon(t.icon, size: 18, color: fg),
          const SizedBox(height: 1),
          Text(t.label, style: TextStyle(fontSize: 8.5, color: active ? Colors.amber : null), maxLines: 1, overflow: TextOverflow.clip),
        ],
      ),
    );
    return enabled ? tile : Opacity(opacity: 0.4, child: tile);
  }

  // The (possibly dynamic) ToolDef for an action tool — Play/Pause swaps icon+label with playback.
  ToolDef _actionDef(String dsl) =>
      dsl == 'PlayPause' ? ToolDef('PlayPause', _playing ? Icons.pause : Icons.play_arrow, _playing ? 'Pause' : 'Play') : _toolDef(dsl);

  bool _actionActive(String dsl) => (dsl == 'Onion' && _onion) || (dsl == 'PlayPause' && _playing);

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
      case 'PlayPause':
        _playing ? _pause() : _play();
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
    final t = isAction ? _actionDef(dsl) : _toolDef(dsl);
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
          width: 54,
          height: 42,
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
            // start the gap where the tool currently sits (insertion index into the others list)
            _dropIndex = _toolOrder.indexOf(dsl).clamp(0, _toolOrder.length - 1);
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

  Widget _buildToolBar() {
    // Render from the live display order. Long-press any tile to drag it; the rest reflow in real
    // time, and the order is committed on release. The "others" list (order minus the dragged tool)
    // is the index space for drop positions.
    final order = _displayToolOrder();
    final others = _dragTool == null ? order : _toolOrder.where((t) => t != _dragTool).toList();
    final n = order.length;
    final cols = (n + 1) ~/ 2; // top row holds the first half
    final top = [for (var i = 0; i < cols; i++) _toolTile(order[i], others)];
    final bottom = [for (var i = cols; i < n; i++) _toolTile(order[i], others)];
    return Container(
      height: 100,
      color: const Color(0xFF15171A),
      child: Row(children: [
        // Undo (top) / Redo (bottom) pinned at the left — fixed, don't scroll with the rest.
        Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          _pinnedActionTile(undoToolDef),
          _pinnedActionTile(redoToolDef),
        ]),
        Container(width: 1, color: Colors.black26),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: top),
              Row(children: bottom),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _slider(double v, double min, double max, ValueChanged<double> onChanged) {
    return SizedBox(
      width: 120,
      child: Slider(value: v.clamp(min, max), min: min, max: max, onChanged: onChanged),
    );
  }

  // A row-1 slider with a tappable label: tapping the "Name value" label opens a numeric
  // text-entry dialog so the exact value can be typed instead of dragged. The text path and
  // the drag path share the same [onChanged], keeping behaviour identical.
  void _labeledSlider(List<Widget> children, String name, double value, double min, double max,
      ValueChanged<double> onChanged, {bool integer = true}) {
    final shown = integer ? value.round().toString() : value.toStringAsFixed(1);
    children.add(InkWell(
      onTap: () => _editSliderValue(name, value, min, max, onChanged, integer: integer),
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

  Future<void> _editSliderValue(String name, double value, double min, double max,
      ValueChanged<double> onChanged, {required bool integer}) async {
    String fmt(double d) => integer ? d.round().toString() : d.toStringAsFixed(1);
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
    int w = 64, h = 64;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New document'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final preset in [16, 32, 48, 64, 128, 256])
            ListTile(
              dense: true,
              title: Text('$preset × $preset'),
              onTap: () {
                w = preset;
                h = preset;
                Navigator.pop(ctx, true);
              },
            ),
        ]),
      ),
    );
    if (ok == true) {
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
