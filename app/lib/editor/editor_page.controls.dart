part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// Row-1 tool options (per-tool sliders/toggles) and the row-2 palette manager.
extension _EditorControls on _EditorPageState {
  Widget _buildToolOptions() {
    final children = <Widget>[];
    void label(String s) => children.add(Padding(
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Text(s, style: const TextStyle(fontSize: 11, color: Colors.white60))));

    if (_isShapeTool && _hasShapeDraft) {
      // Commit / cancel the uncommitted figure. Drag the on-canvas handles to fine-tune first.
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 34), backgroundColor: const Color(0xFF30A050)),
          onPressed: _commitShape,
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Commit'),
        ),
      ));
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), foregroundColor: const Color(0xFFE06060)),
          onPressed: _cancelShapeDraft,
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Cancel'),
        ),
      ));
      children.add(const SizedBox(width: 8));
    }

    if (_precisionCapable) {
      // The Precision toggle: turns the active paint tool into its off-finger reticle mode.
      // Remembered per tool (see _precisionOn).
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _isPrecision,
          avatar: Icon(Icons.gps_fixed, size: 16, color: _isPrecision ? Colors.white : Colors.white60),
          label: Text(_isPrecision ? 'Precision ✔' : 'Precision'),
          selectedColor: const Color(0xFF30A050),
          onSelected: _setPrecision,
        ),
      ));
    }
    if (_isPrecision) {
      // off-finger reticle nudge pad (1px steps), shared by every precision tool
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge left', onPressed: () => _nudgeCursor(-1, 0), icon: const Icon(Icons.chevron_left)));
      children.add(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        InkWell(onTap: () => _nudgeCursor(0, -1), child: const Icon(Icons.keyboard_arrow_up, size: 18)),
        InkWell(onTap: () => _nudgeCursor(0, 1), child: const Icon(Icons.keyboard_arrow_down, size: 18)),
      ]));
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge right', onPressed: () => _nudgeCursor(1, 0), icon: const Icon(Icons.chevron_right)));
      children.add(const SizedBox(width: 4));
      if (_tool == 'Airbrush') {
        // SPRAY (one airbrush dab at the reticle, off-finger)
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 34), backgroundColor: const Color(0xFF4080C0)),
            onPressed: () { _send('AirbrushCursor()'); _refreshState(); _redraw(); setState(() {}); },
            icon: const Icon(Icons.blur_on, size: 16),
            label: const Text('Spray'),
          ),
        ));
      } else {
        // DRAW (single stamp at the reticle)
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 34), backgroundColor: const Color(0xFF4080C0)),
            onPressed: () { _send('PlotCursor()'); _refreshState(); _redraw(); setState(() {}); },
            icon: const Icon(Icons.brush, size: 16),
            label: const Text('Draw'),
          ),
        ));
      }
      // PEN toggle (continuous stroke/spray while dragging the reticle)
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _penDown,
          label: Text(_penDown ? 'Pen ✔' : 'Pen'),
          selectedColor: const Color(0xFF30A050),
          onSelected: (v) {
            setState(() => _penDown = v);
            _send(v ? 'CursorPenDown()' : 'CursorPenUp()');
            _refreshState();
            _redraw();
          },
        ),
      ));
    }
    if (_tool == 'Move') {
      // With a selection, Move moves the selected pixels; with none, it moves the layer/move-group.
      // The arrow pad nudges whichever (engine decides via NudgeMove); dragging on the canvas does
      // the same live. Off-canvas edge mode: Protect (layer moves only) / Wrap (both layer and
      // pixel moves) / both off = Regular. Protect and Wrap are mutually exclusive.
      final hasSel = _outlineEdges.isNotEmpty;
      label(hasSel ? 'Move pixels' : 'Move layer');
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge left', onPressed: () => _nudgeMove(-1, 0), icon: const Icon(Icons.chevron_left)));
      children.add(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        InkWell(onTap: () => _nudgeMove(0, -1), child: const Icon(Icons.keyboard_arrow_up, size: 18)),
        InkWell(onTap: () => _nudgeMove(0, 1), child: const Icon(Icons.keyboard_arrow_down, size: 18)),
      ]));
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge right', onPressed: () => _nudgeMove(1, 0), icon: const Icon(Icons.chevron_right)));
      children.add(const SizedBox(width: 6));
      if (!hasSel) {
        // Protect only applies to layer moves, so it's hidden while moving a selection.
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: FilterChip(
            selected: _protectPixels,
            label: Text(_protectPixels ? 'Protect ✔' : 'Protect pixels'),
            selectedColor: const Color(0xFF30A050),
            onSelected: (v) {
              setState(() {
                _protectPixels = v;
                if (v) _wrap = false;
              });
              _send('SetProtectPixels($_protectPixels); SetWrap($_wrap)');
            },
          ),
        ));
      }
      // Wrap applies to both layer and pixel moves.
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _wrap,
          label: Text(_wrap ? 'Wrap ✔' : 'Wrap'),
          selectedColor: const Color(0xFF30A050),
          onSelected: (v) {
            setState(() {
              _wrap = v;
              if (v) _protectPixels = false;
            });
            _send('SetProtectPixels($_protectPixels); SetWrap($_wrap)');
          },
        ),
      ));
    }
    if (_tool == 'Ruler') {
      label('Ruler');
      children.add(_miniBtn('Clear', () {
        setState(() {
          _rulerA = null;
          _rulerB = null;
          _rulerDrag = 0;
        });
      }));
    }
    // Brush footprint SIZE: every tool whose mark is a stamp/spray of `brush_size` — i.e. the
    // pixel/paint tools, the airbrush spray radius, and dodge/burn. The figure tools (Line/Rect/
    // Ellipse) ignore brush_size (they use line_width + fill), so they're deliberately excluded.
    const sizeTools = {'Pencil', 'Brush', 'Airbrush', 'Eraser', 'Dodge', 'Burn'};
    // Stamp SHAPE (Round/Square): only tools that stamp a footprint of `brush_shape`. The airbrush
    // always sprays a disc (no shape), and figures don't stamp — both are excluded.
    const shapeTools = {'Pencil', 'Brush', 'Eraser', 'Dodge', 'Burn'};
    if (sizeTools.contains(_tool)) {
      _labeledSlider(children, 'Size', _brushSize.toDouble(), 1, 32, (v) {
        setState(() => _brushSize = v.round());
        _send('SetBrushSize($_brushSize)');
      });
    }
    if (shapeTools.contains(_tool)) {
      label('Shape');
      children.add(_toggle(['Round', 'Square'], _round ? 0 : 1, (i) {
        setState(() => _round = i == 0);
        _send('SetBrushShape(${_round ? 'Round' : 'Square'})');
      }));
    }
    if (_tool == 'Airbrush' || _tool == 'Dodge' || _tool == 'Burn') {
      _labeledSlider(children, 'Intensity', _intensity.toDouble(), 1, 255, (v) {
        setState(() => _intensity = v.round());
        _send('SetIntensity($_intensity)');
      });
    }
    // Stamp spacing (% of brush size) for the stamp-trail tools. Tap the label to type a value.
    if (_tool == 'Brush' || _tool == 'Airbrush') {
      _labeledSlider(children, 'Spacing', _spacing.toDouble(), 1, 1000, (v) {
        setState(() => _spacing = v.round());
        _send('SetSpacing($_spacing)');
      });
    }
    if (_tool == 'Bucket' || _tool == 'SelectByColor') {
      _labeledSlider(children, 'Threshold', _threshold.toDouble(), 0, 255, (v) {
        setState(() => _threshold = v.round());
        _send('SetThreshold($_threshold)');
      });
      children.add(_toggle(['Contiguous', 'Global'], _contiguous ? 0 : 1, (i) {
        setState(() => _contiguous = i == 0);
        _send('SetContiguous($_contiguous)');
      }));
    }
    // Stroke width for figures that have one: Line always, Rect/Ellipse only in Outline mode.
    void addWidth() {
      _labeledSlider(children, 'Width', _lineWidth.toDouble(), 1, 16, (v) {
        setState(() => _lineWidth = v.round());
        _send('SetLineWidth($_lineWidth)');
        if (_hasShapeDraft) _redraw(); // the pending preview reflects the new width live
      });
    }

    if (_tool == 'Line') {
      addWidth();
    }
    if (_tool == 'Rectangle' || _tool == 'Ellipse') {
      children.add(_toggle(['Fill', 'Outline'], _shapeFill ? 0 : 1, (i) {
        setState(() => _shapeFill = i == 0);
        _send('SetShapeFill($_shapeFill)');
        if (_hasShapeDraft) _redraw(); // the pending preview reflects fill/outline live
      }));
      if (!_shapeFill) addWidth(); // outline thickness (filled shapes ignore line_width)
      // Lock the shape's aspect ratio (width:height) to the slider value — e.g. ratio 1 makes the
      // Rectangle draw squares and the Ellipse draw circles.
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _lockRatio,
          label: Text(_lockRatio ? 'Ratio ✔' : 'Lock Ratio'),
          selectedColor: const Color(0xFF30A050),
          onSelected: (v) {
            setState(() => _lockRatio = v);
            if (v) _reapplyRatio(); // snap the pending draft to the ratio immediately
          },
        ),
      ));
      if (_lockRatio) {
        // Logarithmic 0.2..5 with 1.0 at the centre (each half spans an equal ratio range).
        _labeledLogSlider(children, 'Ratio', _ratio, 0.2, 5.0, (v) {
          setState(() => _ratio = v);
          _reapplyRatio();
        });
      }
    }
    if (_tool == 'Gradient') {
      children.add(_toggle(['Linear', 'Radial'], _radial ? 1 : 0, (i) {
        setState(() => _radial = i == 1);
        _send('SetGradientType(${_radial ? 'Radial' : 'Linear'})');
      }));
      children.add(_swatchButton(_gradA, () => _pickColor(initial: _gradA, onPick: (c) {
            setState(() => _gradA = c);
            _send('SetGradientStops([${_hex(_gradA)}@0, ${_hex(_gradB)}@1])');
          })));
      children.add(_swatchButton(_gradB, () => _pickColor(initial: _gradB, onPick: (c) {
            setState(() => _gradB = c);
            _send('SetGradientStops([${_hex(_gradA)}@0, ${_hex(_gradB)}@1])');
          })));
    }
    if (_tool == 'SelectLayer') {
      const accent = Color(0xFF00E5FF); // matches the cyan preview overlay
      // Alpha cutoff: pixels with alpha > threshold (the opaque pixels) are "selected"
      // (0 = all non-transparent; raise to keep only more-opaque pixels).
      _labeledSlider(children, 'Threshold', _alphaCutoff.toDouble(), 0, 254, (v) {
        setState(() => _alphaCutoff = v.round());
        _send('SetAlphaCutoff($_alphaCutoff)');
        _redraw(); // refresh the live preview overlay
      });
      // Replace/Add/Subtract/Intersect — each runs the alpha→selection op now; the last one used
      // stays highlighted (the "active" option).
      for (final m in const ['Replace', 'Add', 'Subtract', 'Intersect']) {
        final active = _selLyrMode == m;
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: active ? accent : const Color(0xFF2A2D31),
              foregroundColor: active ? Colors.black : Colors.white70,
            ),
            onPressed: () {
              setState(() => _selLyrMode = m);
              _act('SelectByAlpha($m)');
            },
            child: Text(m),
          ),
        ));
      }
      children.add(const SizedBox(width: 6));
      children.add(_miniBtn('All', () => _act('SelectAll()')));
      children.add(_miniBtn('None', () => _act('SelectNone()')));
    }
    if (_tool.startsWith('Select') && _tool != 'SelectLayer') {
      children.add(_toggle(['Replace', 'Add', 'Subtract', 'Intersect'],
          ['Replace', 'Add', 'Subtract', 'Intersect'].indexOf(_selMode), (i) {
        setState(() => _selMode = ['Replace', 'Add', 'Subtract', 'Intersect'][i]);
        _send('SetSelectionMode($_selMode)');
      }));
      children.add(_miniBtn('All', () => _act('SelectAll()')));
      children.add(_miniBtn('None', () => _act('SelectNone()')));
      children.add(_miniBtn('Invert', () => _act('InvertSelection()')));
      children.add(_miniBtn('Fill', () => _act('FillSelection()')));
      children.add(_miniBtn('Clear', () => _act('ClearSelection()')));
      children.add(_miniBtn('Copy', () => _act('Copy()')));
      children.add(_miniBtn('Cut', () => _act('Cut()')));
      children.add(_miniBtn('Paste', () => _act('Paste()')));
      children.add(_miniBtn('Crop→Sel', () => _act('CropToSelection()')));
    }
    if (_tool == 'HsvShift') {
      _labeledSlider(children, 'H', _hsvH, -180, 180, (v) => setState(() => _hsvH = v));
      _labeledSlider(children, 'S', _hsvS, -1, 1, (v) => setState(() => _hsvS = v), integer: false);
      _labeledSlider(children, 'V', _hsvV, -1, 1, (v) => setState(() => _hsvV = v), integer: false);
      children.add(_miniBtn('Apply', () {
        _send('SetHsvShift($_hsvH, $_hsvS, $_hsvV)');
        _act('ApplyHsvShift()');
      }));
    }
    if (_tool == 'Flip') {
      children.add(_miniBtn('Flip H', () => _act('FlipH()')));
      children.add(_miniBtn('Flip V', () => _act('FlipV()')));
    }
    if (_tool == 'Rotate') {
      children.add(IconButton(iconSize: 18, tooltip: 'Rotate 90° CW', onPressed: () => _act('Rotate(1)'), icon: const Icon(Icons.rotate_right)));
      children.add(IconButton(iconSize: 18, tooltip: 'Rotate 90° CCW', onPressed: () => _act('Rotate(3)'), icon: const Icon(Icons.rotate_left)));
      children.add(_miniBtn('Rotate 180', () => _act('Rotate(2)')));
    }
    if (_tool == 'Invert') {
      children.add(_miniBtn('Invert colours', () => _act('Invert()')));
    }
    if (_tool == 'Resize') {
      children.add(_miniBtn('Resize…', _resizeCanvasDialog));
    }

    return Container(
      height: 48,
      width: double.infinity, // span full width so narrow content doesn't expose the black background on each side
      color: const Color(0xFF202327),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [const SizedBox(width: 4), ...children, const SizedBox(width: 8)]),
      ),
    );
  }

  Widget _buildPalette() {
    // Swatches are laid out in two rows that scroll horizontally together: each column holds the
    // top swatch (even index) and the bottom swatch (odd index), filled column by column.
    final cols = (_palette.length + 1) ~/ 2;
    return Container(
      color: const Color(0xFF1C1F22),
      child: SizedBox(
        height: 60,
        child: Row(children: [
          GestureDetector(
            onTap: () => _pickColor(initial: _primary, onPick: _setPrimary),
            child: Container(
              width: 32, height: 32, margin: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white70, width: 2)),
              child: const Icon(Icons.edit, size: 13, color: Colors.white70),
            ),
          ),
          IconButton(iconSize: 18, tooltip: 'Add current color', onPressed: () => _act('AddPaletteColor(${_hex(_primary)})'), icon: const Icon(Icons.add_circle_outline)),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: cols,
              itemBuilder: (_, col) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [_paletteSwatch(col * 2), _paletteSwatch(col * 2 + 1)],
              ),
            ),
          ),
          // palette controls: tucked into a button after the last swatch
          IconButton(iconSize: 18, tooltip: 'Palette controls', onPressed: _paletteControlsMenu, icon: const Icon(Icons.palette, color: Colors.white70)),
        ]),
      ),
    );
  }

  Widget _paletteSwatch(int i) {
    if (i >= _palette.length) return const SizedBox(width: 30); // keep the column width for an odd last swatch
    final c = _palette[i];
    return GestureDetector(
      onTap: () => _setPrimary(c),
      onLongPress: () => _paletteSwatchMenu(i, c),
      child: Container(
        width: 26,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.black26)),
      ),
    );
  }

  void _paletteControlsMenu() {
    final names = (_state['palette_names'] as List?)?.cast<String>() ?? ['Default'];
    final active = (_state['active_palette'] as int?) ?? 0;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < names.length; i++)
            ListTile(
              leading: Icon(i == active ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
              title: Text(names[i]),
              onTap: () { Navigator.pop(ctx); _act('SetActivePalette($i)'); },
            ),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.add_box_outlined), title: const Text('New palette'), onTap: () { Navigator.pop(ctx); _newPalette(); }),
          ListTile(leading: const Icon(Icons.save_alt), title: const Text('Save palette'), onTap: () { Navigator.pop(ctx); _savePalette(); }),
          ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('Load palette (.json/.gpl)'), onTap: () { Navigator.pop(ctx); _loadPalette(); }),
        ]),
      ),
    );
  }

  void _paletteSwatchMenu(int i, Color c) {
    // The palette is a 2-row column-major grid (even index = top of its column, odd = bottom), so
    // left/right move a whole column (±2) and up/down swap the two rows of the column (±1). The
    // sheet follows the swatch as it moves so you can nudge it several steps without reopening.
    int cur = i;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final n = _palette.length;
        final color = (cur >= 0 && cur < n) ? _palette[cur] : c;
        final row = cur % 2;
        final left = cur - 2 >= 0 ? cur - 2 : null;
        final right = cur + 2 < n ? cur + 2 : null;
        final up = row == 1 ? cur - 1 : null;
        final down = (row == 0 && cur + 1 < n) ? cur + 1 : null;
        void move(int? partner) {
          if (partner == null) return;
          _act('SwapPaletteColors($cur, $partner)');
          setS(() => cur = partner); // follow the swatch to its new slot
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white24)),
              ),
              title: Text('Color ${cur + 1} of $n'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(tooltip: 'Move left', onPressed: left == null ? null : () => move(left), icon: const Icon(Icons.arrow_back)),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(iconSize: 20, tooltip: 'Move up', onPressed: up == null ? null : () => move(up), icon: const Icon(Icons.arrow_upward)),
                  IconButton(iconSize: 20, tooltip: 'Move down', onPressed: down == null ? null : () => move(down), icon: const Icon(Icons.arrow_downward)),
                ]),
                IconButton(tooltip: 'Move right', onPressed: right == null ? null : () => move(right), icon: const Icon(Icons.arrow_forward)),
              ]),
            ),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.edit), title: const Text('Edit color'), onTap: () {
              Navigator.pop(ctx);
              _pickColor(initial: color, onPick: (nc) => _act('EditPaletteColor($cur, ${_hex(nc)})'));
            }),
            ListTile(leading: const Icon(Icons.copy), title: const Text('Duplicate'), onTap: () { Navigator.pop(ctx); _act('DuplicatePaletteColor($cur)'); }),
            ListTile(leading: const Icon(Icons.delete), title: const Text('Remove'), onTap: () { Navigator.pop(ctx); _act('RemovePaletteColor($cur)'); }),
          ]),
        );
      }),
    );
  }

  Future<void> _newPalette() async {
    final ctrl = TextEditingController(text: 'Palette');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New palette'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) _act('NewPalette(${name.trim()})');
  }

  Future<void> _savePalette() async {
    final path = await FilePicker.saveFile(fileName: 'palette.gpl', type: FileType.custom, allowedExtensions: ['gpl', 'json']);
    if (path == null) return;
    final names = (_state['palette_names'] as List?)?.cast<String>() ?? ['Palette'];
    final active = (_state['active_palette'] as int?) ?? 0;
    final pname = active < names.length ? names[active] : 'Palette';
    final sb = StringBuffer('GIMP Palette\nName: $pname\nColumns: 0\n#\n');
    for (final c in _palette) {
      sb.writeln('${c.red}\t${c.green}\t${c.blue}\t${_hex(c)}');
    }
    await File(path).writeAsString(sb.toString());
    _toast('Saved palette (${_palette.length} colors)');
  }

  Future<void> _loadPalette() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['gpl', 'json', 'txt']);
    if (res == null || res.files.single.path == null) return;
    final text = await File(res.files.single.path!).readAsString();
    final colors = _parsePalette(text);
    if (colors.isEmpty) {
      _toast('No colors found');
      return;
    }
    _send('NewPalette(${res.files.single.name.split('.').first})');
    for (final c in colors) {
      _send('AddPaletteColor(${_hex(c)})');
    }
    _refreshState();
    setState(() {});
    _toast('Loaded ${colors.length} colors');
  }

  List<Color> _parsePalette(String text) {
    final out = <Color>[];
    // try JSON array of hex strings
    final t = text.trim();
    if (t.startsWith('[')) {
      try {
        for (final h in (json.decode(t) as List)) {
          out.add(_parseHex(h.toString()));
        }
        return out;
      } catch (_) {}
    }
    // GIMP .gpl: lines of "R G B  name"
    for (final line in text.split('\n')) {
      final l = line.trim();
      if (l.isEmpty || l.startsWith('#') || l.startsWith('GIMP') || l.startsWith('Name:') || l.startsWith('Columns:')) continue;
      final parts = l.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final r = int.tryParse(parts[0]), g = int.tryParse(parts[1]), b = int.tryParse(parts[2]);
        if (r != null && g != null && b != null) out.add(Color.fromARGB(255, r, g, b));
      }
    }
    return out;
  }

  // The static visual of a tool tile (icon + label, highlighted when selected/hovered).
}
