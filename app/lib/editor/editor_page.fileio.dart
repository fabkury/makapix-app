part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// The Resize-canvas 3×3 anchor grid, indexed [y][x]: the engine DSL name, the arrow icon per
// cell, and the human phrase for the caption.
const _anchorNames = [
  ['TopLeft', 'Top', 'TopRight'],
  ['Left', 'Center', 'Right'],
  ['BottomLeft', 'Bottom', 'BottomRight'],
];
const _anchorIcons = [
  [Icons.north_west, Icons.north, Icons.north_east],
  [Icons.west, Icons.filter_center_focus, Icons.east],
  [Icons.south_west, Icons.south, Icons.south_east],
];
const _anchorHuman = [
  ['to the top-left', 'to the top', 'to the top-right'],
  ['to the left', 'at the center', 'to the right'],
  ['to the bottom-left', 'to the bottom', 'to the bottom-right'],
];

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
    if (!mounted) return;
    // Opening an external file is a NEW library drawing (never overwrites the current one). Ask
    // keep/discard/cancel for a non-blank canvas, release the current drawing accordingly, then
    // load; only adopt a new drawing if the load succeeds, so a corrupt file leaves the current
    // drawing intact.
    if (!await _releaseOutgoingDrawingInteractive('"$name"')) return;
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
    if (!mounted) return;
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
                    // Full-screen crop editor. Uses the OUTER _importImage `context` (not the dialog
                    // builder's `ctx`): the route stacks above the still-open import dialog and returns
                    // to it on pop, so `setS` runs normally.
                    final r = await Navigator.of(context).push<Rect>(MaterialPageRoute(
                      builder: (_) => CropPage(
                        bytes: bytes,
                        srcW: srcImg.width,
                        srcH: srcImg.height,
                        canvasW: engine.width,
                        canvasH: engine.height,
                      ),
                    ));
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
      // The layers file offered by the "Share the layers (.mkpx) file" checkbox —
      // compact profile, same as user-facing saves. The publish page decides
      // whether it is actually sent.
      mkpxBytes: engine.saveCompact(),
    );
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublishPage(draft: draft)));
  }

  // True when the document is pristine: a single frame with a single layer that has never been
  // painted (no allocated tiles). A layer whose pixels were all erased still has tiles, so that
  // counts as non-blank — conservative on purpose.
  bool _isBlankDocument() {
    try {
      final st = json.decode(engine.stateJson()) as Map<String, dynamic>;
      final frames = st['frame_detail'] as List? ?? const [];
      if (frames.length != 1) return false;
      final layers = (frames[0] as Map)['layers'] as List? ?? const [];
      if (layers.length != 1) return false;
      return ((layers[0] as Map)['present_tiles'] as num? ?? 1) == 0;
    } catch (_) {
      return false;
    }
  }

  // club → editor: load a downloaded Club artwork as a NEW library drawing and record its
  // provenance so publishing can offer Replace / remix. A non-blank canvas first asks
  // keep/discard/cancel for the current drawing (_releaseOutgoingDrawingInteractive); a blank
  // one is replaced silently.
  Future<void> _consumeClubEdit(ClubEditRequest req) async {
    ref.read(pendingClubEditProvider.notifier).state = null; // clear so it doesn't re-fire
    if (!_engineReady) return;
    if (!await _releaseOutgoingDrawingInteractive('"${req.sourceTitle}"')) return;
    var ok = true;
    if (req.isMkpx) {
      // A layers (.mkpx) file: load as a full document — layers, frames,
      // palettes intact. The engine auto-detects plain vs compact profile.
      ok = engine.load(req.bytes);
    } else {
      _send('NewDocument(${req.width},${req.height})');
      ok = engine.importImage(req.bytes, mode: 1, asLayer: false, startFrame: 0);
    }
    _send('SelectTool($_tool)');
    await _createFreshDrawing(title: req.sourceTitle);
    if (!mounted) return;
    if (!ok) _toast('Could not load this artwork into the editor.');
    setState(() {
      _clubSource = ClubEditSource(
        postId: req.sourcePostId,
        sqid: req.sourceSqid,
        title: req.sourceTitle,
        ownerHandle: req.sourceOwnerHandle,
        isOwner: req.isOwner,
        hasMkpx: req.sourceHasMkpx,
      );
    });
    _refreshState();
    _redraw();
  }

  // Save already-encoded export bytes to a user-chosen file. Mirrors _save(): `bytes` must go to
  // the picker because on Android/iOS the picker writes the file itself (and returns a content URI
  // that File() can't write to) — calling saveFile WITHOUT bytes throws on Android before any UI
  // shows, which is why the export buttons silently did nothing there. On desktop saveFile only
  // returns a path, so the write happens here. Encoding therefore runs BEFORE the dialog opens.
  Future<void> _saveExport(Uint8List bytes, {required String fileName, required String ext, required String done}) async {
    try {
      final path = await FilePicker.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [ext],
        bytes: bytes,
      );
      if (path == null) return; // the user cancelled
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
      if (mounted) _toast(done);
    } catch (e) {
      if (mounted) _toast('Could not save: $e');
    }
  }

  // export-dialog: every PNG/GIF/WebP export and every Share starts here (not .mkpx) — pick an
  // integer upscale factor for the output (nearest-neighbour, so pixel edges stay crisp) and,
  // when `formats` are offered (Share of an animation: GIF vs lossless WebP), the file format.
  // Returns (scale, format) — format is '' when no choice was offered — or null on Cancel. When
  // the chosen size is very large (see _kExportWarnPixels), the first press of Export/Share only
  // raises a red alert and relabels the button "… anyway" — the explicit re-confirmation for
  // exports that can take minutes and a lot of memory.
  Future<(int, String)?> _exportScaleDialog({
    required int frames,
    String title = 'Export size',
    String action = 'Export',
    List<String> formats = const [],
    String initialFormat = '',
  }) =>
      showExportScaleDialog(
        context: context,
        width: engine.width,
        height: engine.height,
        frames: frames,
        title: title,
        action: action,
        formats: formats,
        initialFormat: initialFormat,
      );

  // Encode the document to `format` off the UI thread behind a modal progress dialog. The dialog
  // polls the engine library's process-wide export progress (one step per frame composited + one
  // per frame encoded — a 1,024-frame × 64-layer document can take minutes) and offers Cancel,
  // which asks the encoder to stop at the next frame boundary. Returns (bytes, cancelled):
  // bytes is empty on failure or cancellation.
  Future<(Uint8List, bool)> _encodeWithProgress(String format,
          {required String title, int frame = 0, int layer = 0, int scale = 1}) =>
      encodeWithProgress(
        context: context,
        title: title,
        encode: () => Engine.encodeInBackground(engine.save(), // [F-12]
            format: format, frame: frame, layer: layer, scale: scale),
      );

  // A single-frame export — the active composited frame, or (layerOnly) the ACTIVE layer of it
  // alone (straight alpha, canvas-sized) — as PNG or lossless static WebP; the dialog's format
  // row chooses and the choice is remembered across sessions. Instant at 1× (no dialog flash),
  // behind the progress dialog when upscaled (a 32× frame can take seconds).
  Future<void> _exportStill({required bool layerOnly}) async {
    final frame = engine.activeFrame;
    final layer = layerOnly ? _activeLayerIndex() : 0;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final remembered = prefs.getString(_kExportStillFormatPref) ?? 'PNG';
    if (!mounted) return;
    final choice = await _exportScaleDialog(
      frames: 1,
      formats: const ['PNG', 'WebP'],
      initialFormat: remembered,
    );
    if (choice == null) return;
    final (scale, chosen) = choice;
    await prefs.setString(_kExportStillFormatPref, chosen);
    final webp = chosen == 'WebP';
    final format = layerOnly ? (webp ? 'layer-webp' : 'layer-png') : (webp ? 'frame-webp' : 'png');
    final ext = webp ? 'webp' : 'png';
    final baseName = layerOnly ? 'frame_${frame + 1}_layer_${layer + 1}' : 'frame_${frame + 1}';
    final done = layerOnly ? 'Exported layer ${layer + 1}' : 'Exported $chosen';
    final Uint8List bytes;
    if (scale == 1) {
      bytes = await Engine.encodeInBackground(engine.save(), format: format, frame: frame, layer: layer); // [F-12]
    } else {
      final (b, cancelled) =
          await _encodeWithProgress(format, frame: frame, layer: layer, scale: scale, title: 'Rendering $chosen…');
      if (cancelled) {
        _toast('Export cancelled');
        return;
      }
      bytes = b;
    }
    if (bytes.isEmpty) {
      _toast('Export failed');
      return;
    }
    await _saveExport(bytes,
        fileName: scale > 1 ? '${baseName}_${scale}x.$ext' : '$baseName.$ext',
        ext: ext,
        done: '$done (${bytes.length ~/ 1024} KiB)');
  }

  Future<void> _exportFrame() => _exportStill(layerOnly: false);
  Future<void> _exportLayer() => _exportStill(layerOnly: true);

  Future<void> _exportGif() async {
    final fc = engine.frameCount;
    final choice = await _exportScaleDialog(frames: fc);
    if (choice == null) return;
    final (scale, _) = choice;
    final (bytes, cancelled) = await _encodeWithProgress('gif', scale: scale, title: 'Rendering GIF…');
    if (cancelled) {
      _toast('Export cancelled');
      return;
    }
    if (bytes.isEmpty) {
      _toast('Export failed');
      return;
    }
    await _saveExport(bytes,
        fileName: scale > 1 ? 'animation_${scale}x.gif' : 'animation.gif',
        ext: 'gif',
        done: 'Exported GIF ($fc frames, ${bytes.length ~/ 1024} KiB)');
  }

  // Lossless animated WebP (static WebP for a single-frame document) — same engine export the
  // Club publish flow uses (that path stays at 1×), saved to a user-chosen file instead.
  Future<void> _exportWebp() async {
    final fc = engine.frameCount;
    final choice = await _exportScaleDialog(frames: fc);
    if (choice == null) return;
    final (scale, _) = choice;
    final (bytes, cancelled) = await _encodeWithProgress('webp', scale: scale, title: 'Rendering WebP…');
    if (cancelled) {
      _toast('Export cancelled');
      return;
    }
    if (bytes.isEmpty) {
      _toast('Export failed');
      return;
    }
    await _saveExport(bytes,
        fileName: scale > 1 ? 'animation_${scale}x.webp' : 'animation.webp',
        ext: 'webp',
        done: 'Exported WebP ($fc frames, ${bytes.length ~/ 1024} KiB)');
  }

  // Share the artwork with other apps via the system share sheet: animations as GIF (the format
  // chat/social apps handle best) or lossless WebP (needed when a frame exceeds GIF's 256
  // colours — the choice is remembered across sessions); stills always as PNG — deliberately
  // NEVER WebP, for receiver compatibility (the file EXPORTS offer WebP stills instead). The
  // bytes go to a temp file in the app's cache dir (no storage permission needed; share_plus
  // serves it to the receiver through its FileProvider).
  Future<void> _share() async {
    final fc = engine.frameCount;
    final animated = fc > 1;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final remembered = prefs.getString(_kShareFormatPref) ?? 'GIF';
    if (!mounted) return;
    final choice = await _exportScaleDialog(
      frames: fc,
      title: 'Share',
      action: 'Share',
      formats: animated ? const ['GIF', 'WebP'] : const [],
      initialFormat: remembered,
    );
    if (choice == null) return;
    final (scale, chosen) = choice;
    final (format, ext, mime) = !animated
        ? ('png', 'png', 'image/png')
        : chosen == 'WebP'
            ? ('webp', 'webp', 'image/webp')
            : ('gif', 'gif', 'image/gif');
    if (animated) await prefs.setString(_kShareFormatPref, chosen);

    final Uint8List bytes;
    if (!animated && scale == 1) {
      bytes = await Engine.encodeInBackground(engine.save(), format: 'png', frame: engine.activeFrame); // [F-12]
    } else {
      final (b, cancelled) = await _encodeWithProgress(format,
          frame: engine.activeFrame, scale: scale, title: 'Rendering ${animated ? chosen : 'PNG'}…');
      if (cancelled) {
        _toast('Share cancelled');
        return;
      }
      bytes = b;
    }
    if (bytes.isEmpty) {
      _toast('Share failed');
      return;
    }

    try {
      await shareImageBytes(bytes: bytes, filenameBase: _drawingTitle, ext: ext, mime: mime);
    } catch (e) {
      if (mounted) _toast('Could not share: $e');
    }
  }

  Future<void> _resizeCanvasDialog() async {
    double w = engine.width.toDouble();
    double h = engine.height.toDouble();
    int ax = 1, ay = 1; // anchor cell: 0 = left/top, 1 = centre, 2 = right/bottom
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Resize canvas'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [const SizedBox(width: 20, child: Text('W')), Expanded(child: Slider(value: w.clamp(1, 256), min: 1, max: 256, divisions: 255, label: '${w.toInt()}', onChanged: (v) => setS(() => w = v))), SizedBox(width: 36, child: Text('${w.toInt()}'))]),
            Row(children: [const SizedBox(width: 20, child: Text('H')), Expanded(child: Slider(value: h.clamp(1, 256), min: 1, max: 256, divisions: 255, label: '${h.toInt()}', onChanged: (v) => setS(() => h = v))), SizedBox(width: 36, child: Text('${h.toInt()}'))]),
            // 3×3 anchor grid: which edge/corner the existing content stays pinned to.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                const SizedBox(width: 20),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  for (var y = 0; y < 3; y++)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      for (var x = 0; x < 3; x++)
                        InkWell(
                          onTap: () => setS(() {
                            ax = x;
                            ay = y;
                          }),
                          child: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.all(1),
                            decoration: BoxDecoration(
                              color: (ax == x && ay == y) ? const Color(0xFF4080C0) : const Color(0xFF26292E),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(_anchorIcons[y][x], size: 16, color: (ax == x && ay == y) ? Colors.white : Colors.white54),
                          ),
                        ),
                    ]),
                ]),
                const SizedBox(width: 12),
                Expanded(child: Text('Anchor: content stays pinned ${_anchorHuman[ay][ax]}.', style: const TextStyle(fontSize: 12, color: Colors.white70))),
              ]),
            ),
            Wrap(spacing: 6, children: [for (final p in [16, 32, 64, 128, 256]) ActionChip(label: Text('$p²'), onPressed: () => setS(() { w = p.toDouble(); h = p.toDouble(); }))]),
            if (!ClubSizeRules.accepted(w.toInt(), h.toInt())) ...[
              const SizedBox(height: 10),
              _ClubSizeAlert(w.toInt(), h.toInt()),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () { _act('ResizeCanvas(${w.toInt()}, ${h.toInt()}, ${_anchorNames[ay][ax]})'); Navigator.pop(ctx); }, child: const Text('Resize')),
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
