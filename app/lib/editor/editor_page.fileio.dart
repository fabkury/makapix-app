part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// Save/open .mkpx, image import, PNG/GIF export, Post-to-Club, edit/remix intake,
// and the resize/duration dialogs + colour-picker entry point.
extension _EditorFileIo on _EditorPageState {
  Future<void> _save() async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save .mkpx',
      fileName: 'untitled.mkpx',
      type: FileType.custom,
      allowedExtensions: ['mkpx'],
    );
    if (path == null) return;
    final bytes = engine.save();
    await File(path).writeAsBytes(bytes);
    _toast('Saved ${bytes.length ~/ 1024} KiB → ${path.split(RegExp(r"[\\/]")).last}');
  }

  Future<void> _open() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['mkpx']);
    if (res == null || res.files.single.path == null) return;
    final bytes = await File(res.files.single.path!).readAsBytes();
    if (engine.load(bytes)) {
      _clubSource = null;
      _refreshState();
      _redraw();
      _toast('Opened ${res.files.single.name}');
    } else {
      _toast('Failed to load (corrupt or wrong version)');
    }
    setState(() {});
  }

  Future<void> _importImage() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'gif', 'jpg', 'jpeg', 'bmp', 'webp', 'apng'],
    );
    if (res == null || res.files.single.path == null) return;
    final bytes = await File(res.files.single.path!).readAsBytes();

    final srcImg = await _decodeBytes(bytes);
    int mode = 0; // Fit
    bool asLayer = true;
    Rect? cropRect; // in source pixels
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Import ${res.files.single.name} (${srcImg.width}×${srcImg.height})'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Scaling', style: TextStyle(fontSize: 12, color: Colors.white60)),
            const SizedBox(height: 4),
            ToggleButtons(
              isSelected: [mode == 0, mode == 1, mode == 2],
              onPressed: (i) => setS(() { mode = i; if (i != 2) cropRect = null; }),
              children: const [Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Fit')), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Stretch')), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Crop'))],
            ),
            if (mode == 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.crop, size: 16),
                  label: Text(cropRect == null ? 'Select crop area…' : 'Crop: ${cropRect!.width.toInt()}×${cropRect!.height.toInt()}'),
                  onPressed: () async {
                    final r = await showDialog<Rect>(context: context, builder: (_) => CropDialog(image: srcImg));
                    if (r != null) setS(() => cropRect = r);
                  },
                ),
              ),
            const SizedBox(height: 12),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Add as new layer in existing frames'),
              subtitle: const Text('(off = import as new frames)', style: TextStyle(fontSize: 11)),
              value: asLayer,
              onChanged: (v) => setS(() => asLayer = v),
            ),
            Text('Start at frame ${engine.activeFrame + 1}', style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final done = engine.importImage(bytes,
        mode: mode,
        asLayer: asLayer,
        startFrame: engine.activeFrame,
        cropX: cropRect?.left.toInt() ?? 0,
        cropY: cropRect?.top.toInt() ?? 0,
        cropW: cropRect?.width.toInt() ?? 0,
        cropH: cropRect?.height.toInt() ?? 0);
    if (done) {
      _refreshState();
      _redraw();
      _toast('Imported ${res.files.single.name} (${engine.frameCount} frames)');
    } else {
      _toast('Import failed (unsupported or too large)');
    }
    setState(() {});
  }

  // Post to Makapix Club: export the document (static→PNG, animated→GIF) and open
  // the publish flow (lib/club). The engine stays here; lib/club gets only bytes.
  Future<void> _postToClub() async {
    if (!_engineReady) return;
    final animated = engine.frameCount > 1;
    final bytes = animated ? engine.exportGif() : engine.exportPng(engine.activeFrame);
    if (bytes.isEmpty) {
      _toast('Export failed');
      return;
    }
    final draft = PublishDraft(
      bytes: bytes,
      format: animated ? 'gif' : 'png',
      filename: animated ? 'art.gif' : 'art.png',
      width: engine.width,
      height: engine.height,
      frameCount: engine.frameCount,
      source: _clubSource,
    );
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublishPage(draft: draft)));
  }

  // club → editor: load a downloaded Club artwork as a fresh document and record
  // its provenance so publishing can offer Replace / remix.
  Future<void> _consumeClubEdit(ClubEditRequest req) async {
    ref.read(pendingClubEditProvider.notifier).state = null; // clear so it doesn't re-fire
    if (!_engineReady) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open in editor'),
        content: Text('Load "${req.sourceTitle}" into the editor? This replaces your current document.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open')),
        ],
      ),
    );
    if (go != true) return;
    _send('NewDocument(${req.width},${req.height})');
    final ok = engine.importImage(req.bytes, mode: 1, asLayer: false, startFrame: 0);
    if (!ok) _toast('Could not load this artwork into the editor.');
    setState(() {
      _clubSource = ClubEditSource(
        postId: req.sourcePostId,
        sqid: req.sourceSqid,
        title: req.sourceTitle,
        ownerHandle: req.sourceOwnerHandle,
        isOwner: req.isOwner,
      );
    });
    _send('SelectTool($_tool)');
    _refreshState();
    _redraw();
    if (mounted) _toast('Loaded "${req.sourceTitle}" — edit, then Post to Club');
  }

  Future<void> _exportPng() async {
    final path = await FilePicker.saveFile(fileName: 'frame_${engine.activeFrame + 1}.png', type: FileType.custom, allowedExtensions: ['png']);
    if (path == null) return;
    final bytes = engine.exportPng(engine.activeFrame);
    if (bytes.isEmpty) {
      _toast('Export failed');
      return;
    }
    await File(path).writeAsBytes(bytes);
    _toast('Exported PNG (${bytes.length ~/ 1024} KiB)');
  }

  Future<void> _exportGif() async {
    final path = await FilePicker.saveFile(fileName: 'animation.gif', type: FileType.custom, allowedExtensions: ['gif']);
    if (path == null) return;
    final bytes = engine.exportGif();
    if (bytes.isEmpty) {
      _toast('Export failed');
      return;
    }
    await File(path).writeAsBytes(bytes);
    _toast('Exported GIF (${engine.frameCount} frames, ${bytes.length ~/ 1024} KiB)');
  }

  Future<void> _resizeCanvasDialog() async {
    double w = engine.width.toDouble();
    double h = engine.height.toDouble();
    bool center = true;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Resize canvas'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [const SizedBox(width: 20, child: Text('W')), Expanded(child: Slider(value: w.clamp(8, 256), min: 8, max: 256, divisions: 248, label: '${w.toInt()}', onChanged: (v) => setS(() => w = v))), SizedBox(width: 36, child: Text('${w.toInt()}'))]),
            Row(children: [const SizedBox(width: 20, child: Text('H')), Expanded(child: Slider(value: h.clamp(8, 256), min: 8, max: 256, divisions: 248, label: '${h.toInt()}', onChanged: (v) => setS(() => h = v))), SizedBox(width: 36, child: Text('${h.toInt()}'))]),
            SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Anchor center'), subtitle: const Text('(off = top-left)', style: TextStyle(fontSize: 11)), value: center, onChanged: (v) => setS(() => center = v)),
            Wrap(spacing: 6, children: [for (final p in [16, 32, 48, 64, 128, 256]) ActionChip(label: Text('$p²'), onPressed: () => setS(() { w = p.toDouble(); h = p.toDouble(); }))]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () { _act('ResizeCanvas(${w.toInt()}, ${h.toInt()}, $center)'); Navigator.pop(ctx); }, child: const Text('Resize')),
          ],
        ),
      ),
    );
  }

  Future<void> _editDuration() async {
    final frames = (_state['frame_detail'] as List?);
    int curUs = 100000;
    if (frames != null && engine.activeFrame < frames.length) {
      curUs = frames[engine.activeFrame]['duration_us'] ?? 100000;
    }
    double ms = curUs / 1000.0;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Frame ${engine.activeFrame + 1} duration'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${ms.toStringAsFixed(1)} ms  (${(1000 / ms).toStringAsFixed(1)} fps)'),
            Slider(value: ms.clamp(16.6, 1000), min: 16.6, max: 1000, onChanged: (v) => setS(() => ms = v)),
            Wrap(spacing: 6, children: [
              for (final f in [60, 30, 24, 12, 8])
                ActionChip(label: Text('${f}fps'), onPressed: () => setS(() => ms = 1000 / f)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
                onPressed: () {
                  _act('SetFrameDuration(${engine.activeFrame}, ${ms.toStringAsFixed(2)})');
                  Navigator.pop(ctx);
                },
                child: const Text('This frame')),
            FilledButton(
                onPressed: () {
                  _act('SetAllDurations(${ms.toStringAsFixed(2)})');
                  Navigator.pop(ctx);
                },
                child: const Text('All frames')),
          ],
        ),
      ),
    );
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
  }

  Future<void> _pickColor({required Color initial, required ValueChanged<Color> onPick}) async {
    final c = await showDialog<Color>(context: context, builder: (_) => ColorPickerDialog(initial: initial));
    if (c != null) onPick(c);
  }
}
