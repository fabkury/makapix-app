part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// The frame film-roll and the layer strip: cached thumbnails, frame/layer menus,
// move-group selection, and their builders.
extension _EditorTimeline on _EditorPageState {
  Future<void> _genFrameThumb(int i, int hash) async {
    if (_thumbInFlight.contains(i)) return;
    _thumbInFlight.add(i);
    final (tw, th) = _thumbSize();
    final bytes = engine.frameThumb(i, tw, th);
    if (bytes.length < tw * th * 4) {
      _thumbInFlight.remove(i);
      return;
    }
    final img = await _decode(bytes, tw, th);
    _thumbInFlight.remove(i);
    if (!mounted) {
      img.dispose();
      return;
    }
    _frameThumbs[i]?.img.dispose();
    _frameThumbs[i] = ThumbCache(hash, img);
    if (_frameThumbs.length > 80) {
      final victim = _frameThumbs.keys.firstWhere((k) => k != engine.activeFrame, orElse: () => -1);
      if (victim >= 0) _frameThumbs.remove(victim)?.img.dispose();
    }
    setState(() {});
  }

  // Horizontal "film roll" of frame thumbnails at the top of the canvas area.
  Widget _buildFilmRoll() {
    final count = engine.frameCount;
    final active = engine.activeFrame;
    final (tw, th) = _thumbSize();
    final tileW = (46.0 * tw / th).clamp(28.0, 84.0);
    return Container(
      height: 70,
      color: const Color(0xFF15171A),
      child: Row(children: [
        _editorMenuButton(), // ☰ — the former top-bar items (file/import/export/grid/fit), left of the strip
        Container(width: 1, color: Colors.black26),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemBuilder: (_, i) {
              final hash = engine.frameHash(i);
              final cached = _frameThumbs[i];
              if (cached == null || cached.hash != hash) _genFrameThumb(i, hash);
              final sel = i == active;
              return GestureDetector(
                onTap: () => _act('SetActiveFrame($i)'),
                onLongPress: () => _frameMenu(i),
                child: Container(
                  width: tileW + 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101214),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: sel ? const Color(0xFF4080C0) : Colors.black26, width: sel ? 2 : 1),
                  ),
                  child: Column(children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.all(2),
                        color: const Color(0xFF3A3D42),
                        alignment: Alignment.center,
                        child: cached != null
                            ? RawImage(image: cached.img, fit: BoxFit.contain, filterQuality: FilterQuality.none)
                            : const SizedBox.shrink(),
                      ),
                    ),
                    Text('${i + 1}', style: TextStyle(fontSize: 9, color: sel ? Colors.white : Colors.white54)),
                  ]),
                ),
              );
            },
          ),
        ),
        Container(width: 1, color: Colors.black26),
        IconButton(iconSize: 20, tooltip: 'Add frame', onPressed: () => _act('AddFrame()'), icon: const Icon(Icons.add_box)),
      ]),
    );
  }

  // The editor's ☰ menu (left of the film-strip): everything that used to be in the top bar except
  // the Undo/Redo/Play/Onion actions (which are now row-3 tools).
  PopupMenuItem<String> _menuRow(String value, IconData icon, String label) => PopupMenuItem<String>(
        value: value,
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)]),
      );

  Widget _editorMenuButton() {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu),
      onSelected: _onEditorMenu,
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text('Makapix · ${engine.width}×${engine.height}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        const PopupMenuDivider(),
        _menuRow('club', Icons.public, 'Club'),
        const PopupMenuDivider(),
        _menuRow('new', Icons.insert_drive_file_outlined, 'New'),
        _menuRow('library', Icons.collections_bookmark_outlined, 'My Drawings'),
        _menuRow('open', Icons.folder_open, 'Open'),
        _menuRow('save', Icons.save, 'Save'),
        const PopupMenuDivider(),
        _menuRow('import', Icons.image_outlined, 'Import image…'),
        _menuRow('png', Icons.photo_outlined, 'Export frame as PNG…'),
        _menuRow('gif', Icons.gif_box_outlined, 'Export animation as GIF…'),
        _menuRow('post', Icons.cloud_upload_outlined, 'Post to Makapix Club'),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<String>(value: 'grid', checked: _grid, child: const Text('Grid')),
        _menuRow('fit', Icons.fit_screen, 'Fit to screen'),
      ],
    );
  }

  void _onEditorMenu(String v) {
    switch (v) {
      case 'club':
        ref.read(openClubProvider.notifier).state++;
        break;
      case 'new':
        _newDialog();
        break;
      case 'library':
        _openGallery();
        break;
      case 'open':
        _open();
        break;
      case 'save':
        _save();
        break;
      case 'import':
        _importImage();
        break;
      case 'png':
        _exportPng();
        break;
      case 'gif':
        _exportGif();
        break;
      case 'post':
        _postToClub();
        break;
      case 'grid':
        setState(() => _grid = !_grid);
        _redraw();
        break;
      case 'fit':
        _fitView();
        break;
    }
  }

  void _frameMenu(int i) {
    final count = engine.frameCount;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(dense: true, title: Text('Frame ${i + 1} of $count', style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(leading: const Icon(Icons.copy), title: const Text('Duplicate'), onTap: () { Navigator.pop(ctx); _act('DuplicateFrame($i)'); }),
          ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Duration…'), onTap: () { Navigator.pop(ctx); _act('SetActiveFrame($i)'); _editDuration(); }),
          ListTile(leading: const Icon(Icons.chevron_left), title: const Text('Move left'), enabled: i > 0, onTap: () { Navigator.pop(ctx); _act('ReorderFrame($i, ${i - 1})'); }),
          ListTile(leading: const Icon(Icons.chevron_right), title: const Text('Move right'), enabled: i + 1 < count, onTap: () { Navigator.pop(ctx); _act('ReorderFrame($i, ${i + 1})'); }),
          ListTile(leading: const Icon(Icons.delete, color: Colors.redAccent), title: const Text('Delete'), enabled: count > 1, onTap: () { Navigator.pop(ctx); _act('RemoveFrame($i)'); }),
        ]),
      ),
    );
  }

  List<dynamic> _layerList() {
    final frames = (_state['frame_detail'] as List?) ?? [];
    final active = engine.activeFrame;
    if (active < frames.length) {
      return (frames[active]['layers'] as List?) ?? [];
    }
    return [];
  }

  int _activeLayerIndex() {
    final frames = (_state['frame_detail'] as List?);
    if (frames != null && engine.activeFrame < frames.length) {
      return frames[engine.activeFrame]['active_layer'] ?? 0;
    }
    return 0;
  }

  // Push the current move-group to the engine's layer selection so both the Move-tool layer drag
  // and the nudge buttons act on the whole group (or just the active layer when none is grouped).
  void _syncLayerSel() {
    if (_selLayers.length > 1) {
      // SetMoveGroup sets the move-group without changing the active layer (it stays put).
      final list = (_selLayers.toList()..sort()).join(',');
      _send('SetMoveGroup($list)');
    } else {
      _send('SetActiveLayer(${_activeLayerIndex()})');
    }
  }

  // Nudge whatever the Move tool would drag: the selected pixels if there's a selection, else the
  // active layer / move-group (the engine decides via NudgeMove).
  void _nudgeMove(int dx, int dy) {
    if (_moveSelectionMode) {
      _act('MoveSelection($dx,$dy)'); // move only the selection mask
      return;
    }
    _syncLayerSel();
    _act('NudgeMove($dx,$dy)');
  }

  Future<void> _genLayerThumb(int frame, int layer, int hash) async {
    final key = _layerKey(frame, layer);
    if (_layerThumbInFlight.contains(key)) return;
    _layerThumbInFlight.add(key);
    final (tw, th) = _thumbSize();
    final bytes = engine.layerThumb(frame, layer, tw, th);
    if (bytes.length < tw * th * 4) {
      _layerThumbInFlight.remove(key);
      return;
    }
    final img = await _decode(bytes, tw, th);
    _layerThumbInFlight.remove(key);
    if (!mounted) {
      img.dispose();
      return;
    }
    _layerThumbs[key]?.img.dispose();
    _layerThumbs[key] = ThumbCache(hash, img);
    if (_layerThumbs.length > 60) {
      final victim = _layerThumbs.keys.firstWhere((k) => k != key, orElse: () => -1);
      if (victim >= 0) _layerThumbs.remove(victim)?.img.dispose();
    }
    setState(() {});
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

  void _layerOptions(int i, Map<String, dynamic> l, int count) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        int opacity = l['opacity'] ?? 255;
        bool locked = l['locked'] ?? false;
        bool inGroup = _selLayers.contains(i);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: () { Navigator.pop(ctx); _renameLayer(i, '${l['name']}'); },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text('${l['name']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit, size: 14, color: Colors.white54),
                  ]),
                ),
              ),
              Row(children: [
                const Text('Opacity'),
                Expanded(child: Slider(value: opacity.toDouble(), max: 255, onChanged: (v) { setS(() => opacity = v.round()); _send('SetLayerOpacity($i, $opacity)'); _redraw(); })),
                Text('$opacity'),
              ]),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Locked'), value: locked, onChanged: (v) { setS(() => locked = v); _act('SetLayerLocked($i, $v)'); }),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('In move group'),
                subtitle: const Text('Move together with the Move tool (when nothing is selected)', style: TextStyle(fontSize: 11)),
                value: inGroup,
                onChanged: (v) {
                  setS(() => inGroup = v);
                  setState(() {
                    if (v) {
                      _selLayers.add(i);
                    } else {
                      _selLayers.remove(i);
                    }
                  });
                  _syncLayerSel();
                },
              ),
              Wrap(spacing: 8, children: [
                ActionChip(avatar: const Icon(Icons.control_point_duplicate, size: 16), label: const Text('Duplicate'), onPressed: () { Navigator.pop(ctx); _act('DuplicateLayer($i)'); }),
                ActionChip(avatar: const Icon(Icons.arrow_upward, size: 16), label: const Text('Up'), onPressed: i + 1 < count ? () { Navigator.pop(ctx); _act('ReorderLayer($i, ${i + 1})'); } : null),
                ActionChip(avatar: const Icon(Icons.arrow_downward, size: 16), label: const Text('Down'), onPressed: i > 0 ? () { Navigator.pop(ctx); _act('ReorderLayer($i, ${i - 1})'); } : null),
                ActionChip(avatar: const Icon(Icons.dynamic_feed, size: 16), label: const Text('Copy to all frames'), onPressed: () {
                  Navigator.pop(ctx);
                  final all = List.generate(engine.frameCount, (k) => k).where((k) => k != engine.activeFrame).join(',');
                  if (all.isNotEmpty) _act('SetActiveLayer($i); DuplicateLayerToFrames($all)');
                }),
                ActionChip(avatar: const Icon(Icons.delete, size: 16), label: const Text('Delete'), onPressed: count > 1 ? () { Navigator.pop(ctx); _act('RemoveLayer($i)'); } : null),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  // Layers as a horizontal film-strip (mirrors the frame film-roll): each tile shows just that
  // layer on a checkerboard (transparent) background. "Add layer" sits to the left; duplicate and
  // the other per-layer actions live in the long-press menu.
  Widget _buildLayers(List<dynamic> layers) {
    final frames = (_state['frame_detail'] as List?);
    int activeLayer = 0;
    if (frames != null && engine.activeFrame < frames.length) {
      activeLayer = frames[engine.activeFrame]['active_layer'] ?? 0;
    }
    final frame = engine.activeFrame;
    final (tw, th) = _thumbSize();
    final tileW = (40.0 * tw / th).clamp(26.0, 72.0);
    return Container(
      height: 56,
      color: const Color(0xFF1A1C1F),
      child: Row(children: [
        IconButton(iconSize: 20, tooltip: 'Add layer', onPressed: () => _act('AddLayer()'), icon: const Icon(Icons.add_box)),
        Container(width: 1, color: Colors.black26),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: layers.length,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemBuilder: (_, i) {
              final l = layers[i] as Map<String, dynamic>;
              final sel = i == activeLayer;
              final inGroup = _selLayers.contains(i);
              final visible = l['visible'] == true;
              final hash = engine.layerHash(frame, i);
              final key = _layerKey(frame, i);
              final cached = _layerThumbs[key];
              if (cached == null || cached.hash != hash) _genLayerThumb(frame, i, hash);
              return GestureDetector(
                onTap: () { setState(() => _selLayers.clear()); _act('SetActiveLayer($i)'); },
                onLongPress: () => _layerOptions(i, l, layers.length),
                child: Container(
                  width: tileW + 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101214),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      // active layer always shows blue (it stays put while grouped); other
                      // grouped layers show amber.
                      color: sel ? const Color(0xFF4080C0) : (inGroup ? Colors.amber : Colors.black26),
                      width: (sel || inGroup) ? 2 : 1,
                    ),
                  ),
                  child: Stack(fit: StackFit.expand, children: [
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: Opacity(
                        opacity: visible ? 1 : 0.35,
                        child: CustomPaint(
                          painter: const CheckerPainter(),
                          child: cached != null
                              ? RawImage(image: cached.img, fit: BoxFit.contain, filterQuality: FilterQuality.none)
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    // quick visibility toggle (top-left)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => _act('SetLayerVisible($i, ${!visible})'),
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          color: const Color(0xCC000000),
                          child: Icon(visible ? Icons.visibility : Icons.visibility_off, size: 13, color: Colors.white70),
                        ),
                      ),
                    ),
                    // top-right badges: in-move-group (amber move icon, ~ the size of the top-left
                    // visibility icon) and locked. A Row keeps them from overlapping.
                    if (inGroup || l['locked'] == true)
                      Positioned(
                        right: 1,
                        top: 1,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (inGroup)
                            Container(
                              padding: const EdgeInsets.all(1),
                              color: const Color(0xCC000000),
                              child: const Icon(Icons.open_with, size: 13, color: Colors.amber),
                            ),
                          if (l['locked'] == true)
                            const Padding(
                              padding: EdgeInsets.only(left: 1),
                              child: Icon(Icons.lock, size: 12, color: Colors.white54),
                            ),
                        ]),
                      ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

}
