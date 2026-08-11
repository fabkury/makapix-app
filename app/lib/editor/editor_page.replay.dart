part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Extension on _EditorPageState — a State subclass — so calling @protected setState here is safe;
// the analyzer's check is a false positive for the part/extension split.)

// The Journal glue (CONTEXT.md "Journal"; ADR 0003): attaching the always-on recorder to the
// current drawing at every identity transition, cutting chapters at non-DSL mutations, and the
// replay baseline burst that makes the live engine and a future replay converge from a common
// origin. Recording itself is one line in `_send`; everything here is lifecycle.

/// How the Journal attaches at a drawing-identity transition (see `_attachJournal`).
enum _JournalMode {
  /// An existing library drawing was (re)loaded: reconcile with the autosave via markers,
  /// trimming an orphaned tail — or re-anchor on the engine's actual content.
  resume,

  /// A brand-new drawing whose content should be replayable from empty (the fresh path).
  /// Falls back to a base-anchored chapter when the canvas is no longer pristine (the user
  /// can start drawing in the moments before persistence resolves at startup).
  freshBlank,

  /// A brand-new drawing whose content arrived as bytes (external open, Club edit/remix):
  /// chapter 1 anchors on the engine's current content.
  freshFromBytes,
}

extension _EditorReplay on _EditorPageState {
  /// Attach the Journal for drawing [id]. Called from `_adopt` (the universal switch
  /// funnel) BEFORE `_startAutosave`, whose `preWrite` awaits [_journalAttaching] so the
  /// first marker can never race the attach.
  Future<void> _attachJournal(String id, _JournalMode mode, {String reason = 'fresh'}) async {
    final store = _store;
    if (store == null) return;
    final j = JournalRecorder(dir: store.dirFor(id));
    try {
      switch (mode) {
        case _JournalMode.resume:
          // The FNV of the bytes actually in the engine: stashed by _loadDrawingIntoEngine,
          // or (the failed-open re-attach path) read back without an engine.load validator.
          var docBytes = _resumeDocBytes;
          _resumeDocBytes = null;
          docBytes ??= await store.readDoc(id);
          final fnv = docBytes == null ? null : AutosaveController.fnv1a64(docBytes);
          final outcome = await j.attachResume(docFnv: fnv);
          if (!mounted || !_engineReady) return;
          _journal = j;
          if (outcome == JournalAttachOutcome.reanchorNeeded) {
            await j.cutChapter(engine.saveCompact(), reason: 'reanchor');
          }
          _emitReplayBaseline();
        case _JournalMode.freshBlank:
          if (!mounted || !_engineReady) return;
          if (_isBlankDocument()) {
            await j.attachFresh();
            _journal = j;
            // From-empty chapter: the recorded NewDocument is the replay's origin. The live
            // engine takes the same (blank→blank) reset so both worlds share it.
            _send('NewDocument(${engine.width},${engine.height})');
            _resendEngineTool();
          } else {
            // The user outran persistence init and already drew — anchor on reality.
            await j.attachFreshWithBase(engine.saveCompact(), reason: 'fresh');
            _journal = j;
          }
          _emitReplayBaseline();
        case _JournalMode.freshFromBytes:
          if (!mounted || !_engineReady) return;
          await j.attachFreshWithBase(engine.saveCompact(), reason: reason);
          _journal = j;
          _emitReplayBaseline();
      }
    } catch (e) {
      // A journal failure must never break editing; the next attach self-heals.
      debugPrint('journal attach failed: $e');
      _journal = j;
    }
  }

  /// Cut a chapter at a non-DSL mutation that just landed in the CURRENT drawing (today:
  /// a successful mid-session image import), anchoring on the post-mutation document.
  Future<void> _journalCutAndBaseline(String reason) async {
    final j = _journal;
    if (j == null || !_engineReady) return;
    try {
      await j.cutChapter(engine.saveCompact(), reason: reason);
    } catch (e) {
      debugPrint('journal chapter cut failed: $e');
    }
    _emitReplayBaseline();
  }

  /// ☰ → "Watch replay": open the read-only Replay viewer over this drawing's Journal.
  /// The viewer gets its OWN engine (EngineReplayHost); the live editing session idles
  /// untouched underneath, so there is nothing to restore on pop.
  Future<void> _watchReplay() async {
    final store = _store, id = _drawingId;
    if (store == null || id == null || !_engineReady) {
      _toast('The replay is still being prepared…');
      return;
    }
    if (_playing) _pause();
    // Flush doc + journal (the drain's preWrite appends the final marker), so the viewer
    // reads a journal that includes everything up to this moment.
    await _autosave?.flushNow();
    await _journal?.flush();
    final dir = store.dirFor(id);
    String journalText;
    final bases = <String, Uint8List>{};
    try {
      journalText = await File(p.join(dir.path, kJournalFileName)).readAsString();
      await for (final f in dir.list()) {
        if (f is File && RegExp(r'chapter-\d+\.mkpx$').hasMatch(p.basename(f.path))) {
          bases[p.basename(f.path)] = await f.readAsBytes();
        }
      }
    } catch (_) {
      _toast('This drawing has no replay yet — draw something first!');
      return;
    }
    if (!mounted) return;
    final host = EngineReplayHost(journalText: journalText, bases: bases);
    // Timelapse platforms: desktop exports WebP/GIF via the shipped encoders; Android's
    // MediaCodec channel enables MP4 (iOS's VideoToolbox channel ships unverified until
    // the next Codemagic build). Platforms without a route hide the button.
    final canExport = !Platform.isIOS;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (pageCtx) => ReplayPage(
        host: host,
        title: _drawingTitle,
        onShareTimelapse:
            canExport ? () => _shareTimelapse(pageCtx, host, journalText, bases) : null,
      ),
    ));
  }

  /// "Share timelapse" (CONTEXT.md "Timelapse"): preset dialog → plan → export isolate →
  /// deliver. Mobile produces a silent H.264 MP4 via the platform channel; Windows keeps
  /// WebP/GIF via the shipped encoders (ADR 0004).
  Future<void> _shareTimelapse(
    BuildContext pageCtx,
    ReplayHost host,
    String journalText,
    Map<String, Uint8List> bases,
  ) async {
    if (!host.ready) return;
    final isMobile = Platform.isAndroid || Platform.isIOS;
    var shape = TimelapseShape.square;
    var seconds = 30;
    var format = 'webp'; // Windows-only choice; mobile is always MP4
    final ok = await showDialog<bool>(
      context: pageCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Share timelapse'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Shape', style: TextStyle(fontSize: 12, color: Colors.white60)),
            const SizedBox(height: 4),
            ToggleButtons(
              isSelected: [shape == TimelapseShape.square, shape == TimelapseShape.portrait],
              onPressed: (i) => setS(() => shape = TimelapseShape.values[i]),
              children: const [
                Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Square')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Portrait')),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Drawing time', style: TextStyle(fontSize: 12, color: Colors.white60)),
            const SizedBox(height: 4),
            ToggleButtons(
              isSelected: [seconds == 15, seconds == 30, seconds == 60],
              onPressed: (i) => setS(() => seconds = const [15, 30, 60][i]),
              children: const [
                Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('15 s')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('30 s')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('60 s')),
              ],
            ),
            if (!isMobile) ...[
              const SizedBox(height: 12),
              const Text('Format', style: TextStyle(fontSize: 12, color: Colors.white60)),
              const SizedBox(height: 4),
              ToggleButtons(
                isSelected: [format == 'webp', format == 'gif'],
                onPressed: (i) => setS(() => format = const ['webp', 'gif'][i]),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('WebP')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('GIF')),
                ],
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isMobile ? 'Share' : 'Export')),
          ],
        ),
      ),
    );
    if (ok != true || !pageCtx.mounted) return;

    // A cycle beyond 60 s: the artist chooses — one complete play (may exceed platform
    // upload limits) or a whole-frame ~60 s excerpt. A full play is otherwise never cut.
    final durations = host.endFrameDurationsUs;
    var fullCycle = true;
    if (durations.length > 1 && cycleUs(durations) > 60_000_000) {
      final mins = (cycleUs(durations) / 60_000_000).toStringAsFixed(1);
      final choice = await showDialog<bool>(
        context: pageCtx,
        builder: (ctx) => AlertDialog(
          title: const Text('Long animation'),
          content: Text('This animation\'s full cycle runs $mins minutes. The finale can '
              'play it once in full (a long video that may exceed some platforms\' upload '
              'limits) or show the first ~60 seconds.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('~60 s excerpt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Full cycle')),
          ],
        ),
      );
      if (choice == null || !pageCtx.mounted) return;
      fullCycle = choice;
    }

    final entries = planTimelapse(
      actionCount: host.actionCount,
      seconds: seconds,
      frameDurationsUs: durations,
      fullCycleFinale: fullCycle,
    );

    // The finale wordmark: baked asset, centered in the bottom letterbox band — skipped
    // when the band is too tight (never over the pixels).
    Uint8List? wmRgba;
    var wmW = 0, wmH = 0, wmX = 0, wmY = 0;
    try {
      final data = await rootBundle.load('assets/icons/wordmark.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final img = (await codec.getNextFrame()).image;
      final raw = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      img.dispose();
      codec.dispose();
      if (raw != null) {
        final (endW, endH) = host.endSize;
        final n = letterboxScale(endW, endH, shape.outW, shape.outH);
        final wmScale = (n / 2).ceil().clamp(2, 6); // readable but subordinate to the art
        wmW = img.width * wmScale;
        wmH = img.height * wmScale;
        wmRgba = _scaleRgbaNearest(raw.buffer.asUint8List(), img.width, img.height, wmScale);
        final place = wordmarkPlacement(
          contentW: endW * n,
          contentH: endH * n,
          outW: shape.outW,
          outH: shape.outH,
          wmW: wmW,
          wmH: wmH,
        );
        if (place == null) {
          wmRgba = null; // band too tight — ship unbranded rather than covering art
        } else {
          wmX = place.x;
          wmY = place.y;
        }
      }
    } catch (_) {/* no wordmark is never a reason to fail an export */}

    final exporter = TimelapseExporter();
    final mode = isMobile ? 'mp4' : format;
    String? mp4Path;
    if (mode == 'mp4') {
      final tmp = await getTemporaryDirectory();
      mp4Path = p.join(tmp.path, 'timelapse_${DateTime.now().millisecondsSinceEpoch}.mp4');
    }
    if (!pageCtx.mounted) return;

    // Notifier-driven modal progress (the encodeWithProgress shape, but the replay loop
    // reports through the exporter, not the engine's static counters).
    var dialogOpen = true;
    unawaited(showDialog<void>(
      context: pageCtx,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Rendering timelapse…'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ValueListenableBuilder<double>(
              valueListenable: exporter.progress,
              builder: (_, v, _) => LinearProgressIndicator(value: v),
            ),
          ]),
          actions: [
            TextButton(onPressed: exporter.cancel, child: const Text('Cancel')),
          ],
        ),
      ),
    ).whenComplete(() => dialogOpen = false));

    TimelapseResult result;
    try {
      result = await exporter.run(
        journalText: journalText,
        bases: bases,
        entries: entries,
        shape: shape,
        mode: mode,
        mp4Path: mp4Path,
        bitrateBps: shape == TimelapseShape.portrait ? 3_500_000 : 2_500_000,
        wordmarkRgba: wmRgba,
        wmW: wmW,
        wmH: wmH,
        wmX: wmX,
        wmY: wmY,
      );
    } catch (e) {
      if (pageCtx.mounted && dialogOpen) Navigator.of(pageCtx, rootNavigator: true).pop();
      if (pageCtx.mounted) {
        ScaffoldMessenger.maybeOf(pageCtx)
            ?.showSnackBar(SnackBar(content: Text('Timelapse export failed: $e')));
      }
      return;
    }
    if (pageCtx.mounted && dialogOpen) Navigator.of(pageCtx, rootNavigator: true).pop();
    if (!pageCtx.mounted || result.isCanceled) return;

    final baseName = '${sanitizeShareFilename(_drawingTitle)}-timelapse';
    if (result.mp4Path != null) {
      await shareVideoFile(result.mp4Path!, filename: '$baseName.mp4');
    } else if (result.bytes != null) {
      await _saveExport(result.bytes!,
          fileName: '$baseName.$mode', ext: mode, done: 'Timelapse exported');
    }
  }

  /// Integer nearest-neighbor upscale of straight-RGBA bytes (the wordmark's pre-scale;
  /// tiny inputs, plain Dart is fine).
  static Uint8List _scaleRgbaNearest(Uint8List src, int w, int h, int scale) {
    final out = Uint8List(w * scale * h * scale * 4);
    final ow = w * scale;
    for (var y = 0; y < h * scale; y++) {
      final sy = y ~/ scale;
      for (var x = 0; x < ow; x++) {
        final si = (sy * w + x ~/ scale) * 4;
        final di = (y * ow + x) * 4;
        out[di] = src[si];
        out[di + 1] = src[si + 1];
        out[di + 2] = src[si + 2];
        out[di + 3] = src[si + 3];
      }
    }
    return out;
  }

  /// The replay baseline burst, emitted THROUGH `_send` after every attach and every
  /// chapter cut: re-point the engine at the current tool, re-push every tool setting,
  /// the primary color and gradient stops, and a fresh `SetSeed`. Both the live session
  /// and a future replay execute the same lines, so they converge regardless of what a
  /// load/import did to session state — and the explicit seed makes Airbrush replays
  /// bit-exact (`mkpx_load` resets the RNG; the shell otherwise never seeds it).
  void _emitReplayBaseline() {
    if (!_engineReady) return;
    _resendEngineTool();
    _pushToolSettings();
    _send('SetPrimaryColor(${_hex(_primary)})');
    if (_tool == 'Gradient') {
      _send('SetGradientType(${_radial ? 'Radial' : 'Linear'})');
      _send('SetGradientSmoothstep($_gradSmooth)');
      _send(_gradStopsDsl());
    }
    _send('SetSeed(${DateTime.now().millisecondsSinceEpoch})');
  }
}
