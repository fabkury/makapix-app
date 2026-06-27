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
    if (_tool == 'MoveLayer') {
      // nudge the active layer 1px; dragging on the canvas also moves it (live)
      label('Move layer');
      children.add(IconButton(iconSize: 20, tooltip: 'Move layer left', onPressed: () => _nudgeLayer(-1, 0), icon: const Icon(Icons.chevron_left)));
      children.add(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        InkWell(onTap: () => _nudgeLayer(0, -1), child: const Icon(Icons.keyboard_arrow_up, size: 18)),
        InkWell(onTap: () => _nudgeLayer(0, 1), child: const Icon(Icons.keyboard_arrow_down, size: 18)),
      ]));
      children.add(IconButton(iconSize: 20, tooltip: 'Move layer right', onPressed: () => _nudgeLayer(1, 0), icon: const Icon(Icons.chevron_right)));
      children.add(const SizedBox(width: 6));
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _protectPixels,
          label: Text(_protectPixels ? 'Protect ✔' : 'Protect pixels'),
          selectedColor: const Color(0xFF30A050),
          onSelected: (v) {
            setState(() => _protectPixels = v);
            _send('SetProtectPixels($v)');
          },
        ),
      ));
    }
    final sizeTools = {'Pencil', 'Brush', 'Airbrush', 'Eraser', 'Dodge', 'Burn', 'Line', 'Rectangle', 'Ellipse'};
    if (sizeTools.contains(_tool)) {
      _labeledSlider(children, 'Size', _brushSize.toDouble(), 1, 32, (v) {
        setState(() => _brushSize = v.round());
        _send('SetBrushSize($_brushSize)');
      });
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
    if (_tool == 'Rectangle' || _tool == 'Ellipse') {
      children.add(_toggle(['Fill', 'Outline'], _shapeFill ? 0 : 1, (i) {
        setState(() => _shapeFill = i == 0);
        _send('SetShapeFill($_shapeFill)');
      }));
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
    if (_tool.startsWith('Select')) {
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
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit), title: const Text('Edit color'), onTap: () {
            Navigator.pop(ctx);
            _pickColor(initial: c, onPick: (nc) => _act('EditPaletteColor($i, ${_hex(nc)})'));
          }),
          ListTile(leading: const Icon(Icons.copy), title: const Text('Duplicate'), onTap: () { Navigator.pop(ctx); _act('DuplicatePaletteColor($i)'); }),
          ListTile(leading: const Icon(Icons.delete), title: const Text('Remove'), onTap: () { Navigator.pop(ctx); _act('RemovePaletteColor($i)'); }),
        ]),
      ),
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
