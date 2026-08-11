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
