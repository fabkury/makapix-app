part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// Save/open .mkpx, image import, PNG/GIF export, Post-to-Club, edit/remix intake,
// and the resize/duration dialogs + colour-picker entry point.
extension _EditorFileIo on _EditorPageState {
  // Export a portable .mkpx to a user-chosen location. (This is separate from the automatic library
  // autosave, which keeps the working drawing safe regardless — see editor_page.persistence.dart.)
  Future<void> _save() async {
    // A portable, user-visible file → the compact (DEFLATE) profile. The library autosave and the
    // render-snapshot paths (PNG/GIF/WebP export) keep the cheap plain profile; `_open` loads either.
    final bytes = engine.saveCompact();
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save .mkpx',
        fileName: 'untitled.mkpx',
        type: FileType.custom,
        allowedExtensions: ['mkpx'],
        bytes: bytes, // required on Android/iOS — the picker writes the file itself there
      );
      if (path == null) return; // the user cancelled
      // On desktop, saveFile returns a path WITHOUT writing, so write here. On mobile the picker
      // already wrote the file (and `path` is a content URI that File() can't write to), so skip.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
      if (mounted) _toast('Saved ${bytes.length ~/ 1024} KiB');
    } catch (e) {
      if (mounted) _toast('Could not save: $e');
    }
  }

  Future<void> _open() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['mkpx']);
    if (res == null || res.files.single.path == null) return;
    final name = res.files.single.name;
    final bytes = await File(res.files.single.path!).readAsBytes();
    // Opening an external file is a NEW library drawing (never overwrites the current one). Save +
    // stop the current drawing first, then load; only adopt a new drawing if the load succeeds, so
    // a corrupt file leaves the current drawing intact.
    await _autosave?.flushNow();
    await _autosave?.stop();
    _autosave = null;
    if (engine.load(bytes)) {
      _clubSource = null;
      await _createFreshDrawing(title: name.replaceAll(RegExp(r'\.mkpx$', caseSensitive: false), ''));
      if (mounted) _toast('Opened $name');
    } else {
      _startAutosave(); // load failed; resume autosaving the still-current drawing
      if (mounted) _toast('Failed to load (corrupt or wrong version)');
    }
    if (mounted) {
      _refreshState();
      _redraw();
      setState(() {});
    }
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

  // Post to Makapix Club: export the document as a LOSSLESS WebP (static for one frame, animated
  // WebP for many) — the recommended Club format — and open the publish flow (lib/club). The engine
  // stays here; lib/club gets only bytes.
  Future<void> _postToClub() async {
    if (!_engineReady) return;
    final w = engine.width, h = engine.height, fc = engine.frameCount;
    // Encode off the UI thread so a multi-frame WebP doesn't jank/ANR. [audit F-12]
    final docBytes = engine.save();
    _toast('Rendering WebP…');
    final bytes = await Engine.encodeInBackground(docBytes, format: 'webp');
    if (!mounted) return;
    if (bytes.isEmpty) {
      _toast('Export failed');
      return;
    }
    final draft = PublishDraft(
      bytes: bytes,
      format: 'webp',
      filename: 'art.webp',
      width: w,
      height: h,
      frameCount: fc,
      source: _clubSource,
    );
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublishPage(draft: draft)));
  }

  // club → editor: load a downloaded Club artwork as a NEW library drawing (the user's current
  // drawing is preserved in My Drawings, never clobbered) and record its provenance so publishing
  // can offer Replace / remix.
  Future<void> _consumeClubEdit(ClubEditRequest req) async {
    ref.read(pendingClubEditProvider.notifier).state = null; // clear so it doesn't re-fire
    if (!_engineReady) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open in editor'),
        content: Text('Open "${req.sourceTitle}" as a new drawing? Your current drawing is kept in My Drawings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open')),
        ],
      ),
    );
    if (go != true) return;
    var ok = true;
    await _switchToNewDrawing(
      title: req.sourceTitle,
      mutateEngine: () {
        _send('NewDocument(${req.width},${req.height})');
        ok = engine.importImage(req.bytes, mode: 1, asLayer: false, startFrame: 0);
        _send('SelectTool($_tool)');
      },
    );
    if (!mounted) return;
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
    _refreshState();
    _redraw();
    if (mounted) _toast('Loaded "${req.sourceTitle}" — edit, then Post to Club');
  }

  Future<void> _exportPng() async {
    final path = await FilePicker.saveFile(fileName: 'frame_${engine.activeFrame + 1}.png', type: FileType.custom, allowedExtensions: ['png']);
    if (path == null) return;
    final docBytes = engine.save();
    final bytes = await Engine.encodeInBackground(docBytes, format: 'png', frame: engine.activeFrame); // [F-12]
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
    final fc = engine.frameCount;
    final docBytes = engine.save();
    _toast('Rendering GIF…');
    final bytes = await Engine.encodeInBackground(docBytes, format: 'gif'); // [F-12]
    if (bytes.isEmpty) {
      _toast('Export failed');
      return;
    }
    await File(path).writeAsBytes(bytes);
    _toast('Exported GIF ($fc frames, ${bytes.length ~/ 1024} KiB)');
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
