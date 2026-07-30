part of 'animator_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _AnimatorPageState — the editor part files' rationale: extensions on a State
// subclass trip a false positive calling the @protected setState.)

// Bytes crossing the app boundary: the Prop import flow (probe → Whole/Parts card → the
// engine's one import chokepoint), and export/share (the editor's exact thin-wrapper shape
// over lib/share/image_share.dart: scale dialog → background encode with progress → save or
// share sheet). The GIF alpha notice (design: disclosed threshold) fires before encoding.
extension _AnimatorFileIo on _AnimatorPageState {
  static const List<String> _importFormats = ['mkpx', 'png', 'gif', 'webp'];

  // ---- import ------------------------------------------------------------------------------

  Future<void> _importPropFlow() async {
    if (!_engineReady) return;
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _importFormats,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null) {
        _toast('Could not read that file.');
        return;
      }
      final base = (f.name.contains('.'))
          ? f.name.substring(0, f.name.lastIndexOf('.'))
          : f.name;
      await _importBytesAsProps(bytes, base);
    } catch (e) {
      _toast('Import failed: $e');
    }
  }

  /// The full import path (also the "Animate this drawing" landing): probe, offer the
  /// Whole/Parts card for multi-layer .mkpx, run the engine import, narrate the outcome.
  Future<bool> _importBytesAsProps(Uint8List bytes, String name) async {
    final probe = ImportProbe.parse(SceneEngine.probeImport(bytes));
    if (probe.isError) {
      _toast(probe.error == 'too_large'
          ? 'That file is too large to import.'
          : "That file isn't importable here (PNG, GIF, WebP, or .mkpx).");
      return false;
    }
    if (probe.w > kPropMaxDim || probe.h > kPropMaxDim) {
      _toast('Props can be at most $kPropMaxDim px per side.');
      return false;
    }

    var split = false;
    ui.Image? whole;
    final parts = <ui.Image?>[];
    if (probe.offersSplit) {
      // Preview render through a short-lived EDITOR engine (frameThumb/layerThumb are the
      // exact art the card is choosing over) — sync engine lifecycle, decode after dispose.
      Uint8List wholeRgba = Uint8List(0);
      final partRgbas = <Uint8List>[];
      var tw = 56, th = 56;
      final eng = Engine(8, 8);
      try {
        if (eng.load(bytes)) {
          final w = eng.width, h = eng.height;
          final fit = math.min(56 / w, 56 / h);
          tw = math.max(1, (w * fit).round());
          th = math.max(1, (h * fit).round());
          wholeRgba = eng.frameThumb(0, tw, th);
          for (var i = 0; i < probe.layerNames.length; i++) {
            partRgbas.add(eng.layerThumb(0, i, tw, th));
          }
        }
      } finally {
        eng.dispose();
      }
      whole = await _thumbFromRgba(wholeRgba, tw, th);
      for (final rgba in partRgbas) {
        parts.add(await _thumbFromRgba(rgba, tw, th));
      }
      if (!mounted) return false;
      final choice = await showDialog<bool>(
        context: context,
        builder: (_) => ImportPropDialog(
          probe: probe,
          wholePreview: whole,
          partPreviews: parts,
        ),
      );
      if (choice == null) {
        whole?.dispose();
        for (final img in parts) {
          img?.dispose();
        }
        return false; // canceled
      }
      split = choice;
    }

    final json = engine.importProp(bytes, splitLayers: split, placeActors: true, name: name);
    whole?.dispose();
    for (final img in parts) {
      img?.dispose();
    }
    Map<String, dynamic> result;
    try {
      result = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      result = const {'error': 'unknown'};
    }
    if (result['error'] != null) {
      final e = result['error'] as String;
      _toast(e.contains('memory budget')
          ? 'Not enough scene memory for that import.'
          : e.contains('1024')
              ? 'Props can be at most 1024 px per side.'
              : 'Import failed: $e');
      _refreshState();
      return false;
    }
    _frameCache.syncEpoch(engine.cacheEpoch);
    _refreshState();
    _redrawCurrent();
    if (mounted) setState(() {});

    // Progressive reveal: the first animated Prop teaches the two-clocks concept once.
    final props = (result['props'] as List?) ?? const [];
    final animated = props.any((p) => ((p as Map)['frames'] as num? ?? 1) > 1);
    if (animated && (_prefs?.getBool(_kCycleRevealPref) ?? false) == false) {
      _prefs?.setBool(_kCycleRevealPref, true);
      _toast('This prop has its own loop — it keeps playing while you animate it.');
    }
    return props.isNotEmpty;
  }

  // ---- export / share ----------------------------------------------------------------------

  Future<(Uint8List, String)?> _encodeSceneFlow({required String action}) async {
    if (!_engineReady || _state.frameCount < 1) return null;
    final remembered = _prefs?.getString(_kExportFormatPref) ?? 'GIF';
    final picked = await showExportScaleDialog(
      context: context,
      width: _state.w,
      height: _state.h,
      frames: _state.frameCount,
      title: '$action size',
      action: action,
      formats: const ['GIF', 'WebP'],
      initialFormat: remembered,
    );
    if (picked == null) return null;
    final (scale, format) = picked;
    _prefs?.setString(_kExportFormatPref, format);
    final isGif = format != 'WebP';
    if (isGif && _state.usesAlpha) {
      // The disclosed threshold (design 02/04): GIF carries 1-bit transparency.
      _toast('GIF: semi-transparent pixels export fully opaque or fully transparent.');
    }
    final title = isGif ? 'Rendering GIF…' : 'Rendering WebP…';
    if (!mounted) return null;
    final (bytes, canceled) = await encodeWithProgress(
      context: context,
      title: title,
      encode: () => SceneEngine.encodeSceneInBackground(
        engine.save(),
        format: isGif ? 'gif' : 'webp',
        scale: scale,
      ),
    );
    if (canceled || bytes.isEmpty) {
      if (!canceled) _toast('Export failed.');
      return null;
    }
    return (bytes, isGif ? 'gif' : 'webp');
  }

  Future<void> _exportFlow() async {
    final out = await _encodeSceneFlow(action: 'Export');
    if (out == null) return;
    final (bytes, ext) = out;
    await _saveExport(
      bytes,
      fileName: '${sanitizeShareFilename(_sceneTitle)}.$ext',
      ext: ext,
      done: 'Saved.',
    );
  }

  Future<void> _shareFlow() async {
    final out = await _encodeSceneFlow(action: 'Share');
    if (out == null) return;
    final (bytes, ext) = out;
    await shareImageBytes(
      bytes: bytes,
      filenameBase: sanitizeShareFilename(_sceneTitle),
      ext: ext,
      mime: ext == 'gif' ? 'image/gif' : 'image/webp',
      text: _sceneTitle,
    );
  }

  /// Save already-encoded bytes to a user-chosen file (the editor's platform rules: bytes go
  /// to the picker because Android/iOS write through the picker; desktop writes here).
  Future<void> _saveExport(Uint8List bytes,
      {required String fileName, required String ext, required String done}) async {
    try {
      final path = await FilePicker.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [ext],
        bytes: bytes,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
      if (mounted) _toast(done);
    } catch (e) {
      if (mounted) _toast('Could not save: $e');
    }
  }
}
