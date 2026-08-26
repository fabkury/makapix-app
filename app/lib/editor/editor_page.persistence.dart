part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Extension on _EditorPageState — a State subclass — so calling @protected setState here is safe;
// the analyzer's check is a false positive for the part/extension split.)

// Local artwork persistence: the working library (each drawing is its own folder), silent crash-safe
// autosave of the current drawing, recovery on launch, and switching between drawings. The Rust
// engine is untouched — this is all shell-side over the existing `.mkpx` save/load FFI.
// The user's decision for the current drawing when new artwork is about to replace the canvas.
enum _OutgoingChoice { discard, save }

// ADR 0014: exactly one editor instance may touch a drawing's folder at a time. A fast pillar
// round-trip mounts the next editor while the previous one's teardown writes are still in flight,
// and the two raced over the same files [G-41]. The hazard is two instances in ONE process, so an
// in-process map of in-flight teardowns is the exact scope — no lock file, and therefore no
// stale-lock recovery to get wrong. Library-private so both editor_page.dart's dispose and this
// part's mount path can reach it.
final Map<String, Future<void>> _folderWriters = {};

/// Register [work] as the sole writer of [id]'s folder, queued after any previous writer.
Future<void> _withFolderLock(String id, Future<void> Function() work) {
  final prev = _folderWriters[id] ?? Future<void>.value();
  final next = prev.then((_) => work()).catchError((_) {});
  _folderWriters[id] = next;
  next.whenComplete(() {
    if (identical(_folderWriters[id], next)) _folderWriters.remove(id);
  });
  return next;
}

/// Await whatever teardown is still writing [id]'s folder, so a fresh mount never reads or
/// re-anchors underneath it.
Future<void> _awaitFolderIdle(String id) => _folderWriters[id] ?? Future<void>.value();

extension _EditorPersistence on _EditorPageState {
  // ---- startup ----------------------------------------------------------------

  // Resolve the on-disk library, then either silently restore the last drawing, hand off to a
  // pending Club edit (which opens as its own new drawing), or start a fresh tracked drawing.
  Future<void> _initPersistence() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _store = DrawingStore(dir);
      _prefs = await SharedPreferences.getInstance();
      // Stored keyboard Bindings (6.B-ready; the file doesn't exist until a rebinding UI
      // writes it). Fail-soft inside loadBindings: any trouble keeps the defaults.
      final bindings = await loadBindings(dir, _keyboardBindings);
      if (mounted && !identical(bindings, _keyboardBindings)) {
        setState(() => _keyboardBindings = bindings);
      }
    } catch (e) {
      debugPrint('persistence init failed (editor still usable, no autosave): $e');
      return;
    }
    if (!mounted) return;

    final curId = _prefs?.getString(_kCurrentDrawing);
    // ADR 0014 [G-41]: a fast pillar round-trip can mount this editor while the previous one's
    // teardown is still writing the same folder. Wait for it before reading a byte.
    if (curId != null) await _awaitFolderIdle(curId);
    if (!mounted) return;
    if (curId != null && await _store!.exists(curId) && await _loadDrawingIntoEngine(curId)) {
      final meta = await _store!.readMeta(curId);
      _restoreProvenance(_resumeDocBytes);
      _adopt(curId, meta?.title ?? 'Untitled', meta?.createdAt ?? DateTime.now());
    } else {
      // No restorable current drawing → track the default 64×64 doc as a fresh one.
      _provenance = DocProvenance.fresh();
      await _createFreshDrawing(title: 'Untitled');
    }
    if (mounted) {
      _refreshState();
      _redraw();
    }

    // ADR 0014 [G-39]: from here on the canvas may accept strokes — before this point a stroke
    // would have been clobbered by the restore and left pixels in no Journal.
    _persistenceReady = true;

    // Consume any pending Club "Edit in Makapix" request only AFTER the real current drawing is
    // back in the engine, so the replace-ask judges (and can save/discard) the actual document —
    // not the placeholder 64×64 the engine boots with.
    final pending = ref.read(pendingClubEditProvider);
    if (pending != null && mounted) await _consumeClubEdit(pending);

    // Consume any pending local-library request from the profile's Private tab. The editor is
    // freshly mounted on every switch into this pillar, so reading here on mount is sufficient
    // (mirrors the Club-edit path). _openExistingDrawing / _switchToNewDrawing carry their own
    // keep/discard prompt for the outgoing drawing.
    final localReq = ref.read(pendingLocalLibraryProvider);
    if (localReq != null && mounted) {
      ref.read(pendingLocalLibraryProvider.notifier).state = null; // consume once
      switch (localReq) {
        case OpenLocalDrawing(:final id):
          await _openExistingDrawing(id);
        case NewLocalDrawing():
          await _switchToNewDrawing(title: 'Untitled', mutateEngine: () {
            _send('NewDocument(64,64)');
            _resendEngineTool();
          });
          if (mounted) {
            _refreshState();
            _redraw();
          }
      }
    }
  }

  // ---- the autosave wiring ----------------------------------------------------

  void _startAutosave() {
    final id = _drawingId, store = _store;
    if (id == null || store == null) return;
    _autosave = AutosaveController(
      id: id,
      store: store,
      // Provenance rides in the META chunk of every library save, so the sticky import bit and
      // the parent-sqid list survive save-to-local / reopen (artwork-provenance message 0002).
      serialize: () => _engineReady ? engine.saveWithMeta(_provenance.toMeta()) : Uint8List(0),
      buildMeta: _buildMeta,
      onError: _onAutosaveError,
      // Journal write-ahead: flush the recorder and append a marker for the exact bytes
      // about to be written, awaiting a still-in-flight attach first so the first marker
      // can never race it. [replay]
      // [G-42] Reads the WRITER handle, not _journal: dispose nulls _journal immediately, so
      // the final flush's preWrite used to find nothing and every session end re-anchored. The
      // writer handle is cleared only by a real release.
      preWrite: (fnv) async {
        await _journalAttaching;
        await _journalWriter?.markerBeforeSave(fnv);
      },
    )..start();
  }

  DrawingMeta _buildMeta() => DrawingMeta(
        id: _drawingId ?? 'unknown',
        title: _drawingTitle,
        createdAt: _drawingCreatedAt,
        updatedAt: DateTime.now(),
        width: _engineReady ? engine.width : 0,
        height: _engineReady ? engine.height : 0,
        frameCount: _engineReady ? engine.frameCount : 1,
      );

  void _onAutosaveError(Object e) {
    debugPrint('autosave error: $e');
    final now = DateTime.now();
    if (_lastAutosaveWarn == null || now.difference(_lastAutosaveWarn!) > const Duration(seconds: 30)) {
      _lastAutosaveWarn = now;
      if (mounted) _toast("Couldn't autosave — check device storage");
    }
  }

  // Rename the open drawing (the ☰ header's pencil). The explicit writeMeta matters: autosave
  // short-circuits when the document bytes are unchanged, so a title-only edit would otherwise
  // never reach disk.
  Future<void> _renameCurrentDrawing() async {
    final name = await showRenameDrawingDialog(context, initialTitle: _drawingTitle);
    if (name == null || name.isEmpty || name == _drawingTitle || !mounted) return;
    setState(() => _drawingTitle = name);
    await _store?.writeMeta(_buildMeta());
  }

  // ---- drawing identity transitions -------------------------------------------

  // Adopt an already-loaded drawing as the current one (no engine change) and begin autosaving it.
  // This is the universal document-switch funnel (open / new / gallery / Club edit / startup), so
  // it drops thumbnails cached against the previous document — they are keyed by frame/layer index
  // and would otherwise flash stale for one frame and leak the old ui.Images. [audit]
  void _adopt(String id, String title, DateTime createdAt,
      {_JournalMode journalMode = _JournalMode.resume, String journalReason = 'fresh'}) {
    // ADR 0011: a document switch is a context change, so no Draft survives it. Without this a
    // pending figure or transform could commit into an entirely different document [G-17].
    _cancelDraftsForContextChange();
    _resetThumbCaches();
    _drawingId = id;
    _drawingTitle = title;
    _drawingCreatedAt = createdAt;
    _prefs?.setString(_kCurrentDrawing, id);
    // Attach the Journal BEFORE the autosave starts: its preWrite awaits this future, so
    // the first marker lands after the attach settles. [replay]
    _journal = null;
    _journalAttaching = _attachJournal(id, journalMode, reason: journalReason);
    _startAutosave();
  }

  // Begin tracking a brand-new library drawing for whatever the engine currently holds, writing it
  // to disk immediately so it exists in the gallery and is crash-safe from the first moment.
  // [contentFromBytes] marks content that arrived as bytes (external open / Club edit): the
  // Journal then anchors chapter 1 on the engine's current document instead of starting empty.
  Future<void> _createFreshDrawing({
    required String title,
    bool contentFromBytes = false,
    String reason = 'fresh',
  }) async {
    _adopt(DrawingStore.newId(), title, DateTime.now(),
        journalMode: contentFromBytes ? _JournalMode.freshFromBytes : _JournalMode.freshBlank,
        journalReason: reason);
    await _autosave?.flushNow();
  }

  // Load a drawing's bytes into the engine, falling back to its `.bak` on a corrupt primary. Uses
  // `engine.load` as the validator so the right file is both chosen and loaded in one pass. A
  // content-hash warning is NOT corruption (the primary still loads — a hash-rule difference must
  // never resurrect an older backup); only real load failures fall back.
  Future<bool> _loadDrawingIntoEngine(String id) async {
    final store = _store;
    if (store == null || !_engineReady) return false;
    final bytes = await store.readDoc(id, validate: (b) {
      final s = engine.load(b);
      if (s == LoadStatus.okWithWarnings) {
        debugPrint('drawing $id loaded with a content-hash warning');
      }
      return s.loaded;
    });
    // Stash the WINNING bytes (primary or .bak — whatever readDoc returned) for the
    // Journal's resume reconciliation; never hook inside the validator, which can run
    // twice. [replay]
    _resumeDocBytes = bytes;
    return bytes != null;
  }

  // Restore the working document's provenance from the bytes it was just loaded from: our META
  // keys when present, else "unknown" (a legacy/foreign file — creation_method is then omitted at
  // publish rather than guessed). Callers pass the WINNING bytes (primary or .bak).
  void _restoreProvenance(Uint8List? bytes) {
    _provenance = (bytes == null || bytes.isEmpty)
        ? DocProvenance.unknown()
        : DocProvenance.fromMeta(Engine.readMkpxMeta(bytes) ?? const {});
  }

  // Stop tracking the outgoing drawing before a switch: either flush-and-keep it in the library,
  // or delete it (the caller decided — blank auto-discard or the user's explicit choice).
  Future<void> _releaseOutgoing({required bool discard}) async {
    if (!discard) await _autosave?.flushNow();
    await _autosave?.stop(); // waits for any in-flight write before a delete pulls the folder
    _autosave = null;
    // Detach the Journal before any delete pulls the folder (Windows file locks); the
    // keep-branch flushNow above already routed the final marker through preWrite. [replay]
    final j = _journal;
    _journal = null;
    _journalWriter = null; // a real release DOES clear the writer handle [G-42]
    _journalAttaching = null;
    if (j != null) await j.detach();
    final id = _drawingId;
    if (discard && id != null) {
      try {
        await _store?.delete(id);
      } catch (_) {/* best-effort: an orphaned folder is harmless */}
    }
  }

  // Ask what should happen to the outgoing drawing WITHOUT acting on it yet (ADR 0014: load,
  // then adopt). Separating the question from the release is what lets a caller probe the
  // incoming document first and abandon the whole switch if it will not load — so a corrupt
  // target can neither take the outgoing drawing's identity [G-37] nor cause it to be released
  // and then resurrected [G-38]. Returns null when the artist cancels.
  Future<_OutgoingChoice?> _askOutgoingChoice(String incoming) async {
    if (!_engineReady || !mounted) return null;
    if (_isBlankDocument()) return _OutgoingChoice.discard; // nothing to protect, never asked
    final choice = await showDialog<_OutgoingChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Open $incoming?'),
        content: Text('What should happen to your current drawing, "$_drawingTitle"?'),
        // Discard sits alone at the far LEFT, opposite Keep, so a mis-click near the usual
        // confirm corner can't destroy work; it also re-confirms below. On narrow phones the
        // row can't fit, so the dialog's OverflowBar stacks the buttons vertically — reversed
        // (`up`) so Keep lands on top and Discard at the bottom, farthest from the thumb.
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE06060)),
            onPressed: () => Navigator.pop(ctx, _OutgoingChoice.discard),
            child: const Text('Discard it'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _OutgoingChoice.save),
            child: const Text('Keep in My Drawings'),
          ),
        ],
      ),
    );
    if (choice == null) return null;
    if (choice == _OutgoingChoice.discard) {
      if (!mounted) return null;
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Discard "$_drawingTitle"?'),
          content: const Text('It will not be kept in My Drawings. This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (sure != true) return null; // declined → the whole load is canceled
    }
    return choice;
  }

  // Ask AND release, for the callers whose incoming content cannot fail to load (New, and the
  // byte-carrying paths that already hold their content in hand).
  Future<bool> _releaseOutgoingDrawingInteractive(String incoming) async {
    final choice = await _askOutgoingChoice(incoming);
    if (choice == null) return false;
    await _releaseOutgoing(discard: choice == _OutgoingChoice.discard);
    return true;
  }

  // Create a New drawing: a non-blank canvas gets the same keep/discard/cancel ask as loading
  // artwork (see _releaseOutgoingDrawingInteractive; a blank one is replaced silently), then the
  // engine is mutated to the new content and tracked as a brand-new library drawing.
  Future<void> _switchToNewDrawing({
    required String title,
    required void Function() mutateEngine,
  }) async {
    if (!await _releaseOutgoingDrawingInteractive('a new drawing')) return;
    mutateEngine();
    _provenance = DocProvenance.fresh(); // a new document is provably never-imported from birth
    await _createFreshDrawing(title: title);
  }

  // Open an existing library drawing (from the gallery): ask keep/discard/cancel for a non-blank
  // current one, release it accordingly, then load the target and adopt it.
  Future<void> _openExistingDrawing(String id) async {
    if (id == _drawingId) return;
    final meta = await _store?.readMeta(id);
    if (!mounted) return;
    // ADR 0014, load-then-adopt. Ask first, but do NOT release the outgoing drawing yet: its
    // identity, journal and autosave only change once the incoming document is proven to load.
    final choice = await _askOutgoingChoice('"${meta?.title ?? 'Untitled'}"');
    if (choice == null) return;
    final outgoingId = _drawingId;
    await _autosave?.flushNow(); // the outgoing is now on disk, so rollback below is exact
    final ok = await _loadDrawingIntoEngine(id);
    if (!ok) {
      // Nothing was released, so the outgoing drawing still owns its identity — put its bytes
      // back under it and leave the target untouched [G-37, G-38].
      if (outgoingId != null) await _loadDrawingIntoEngine(outgoingId);
      if (mounted) {
        _toast('Could not open that drawing (file missing or corrupt)');
        _refreshState();
        _redraw();
      }
      return;
    }
    await _releaseOutgoing(discard: choice == _OutgoingChoice.discard);
    _clubSource = null;
    _restoreProvenance(_resumeDocBytes);
    _adopt(id, meta?.title ?? 'Untitled', meta?.createdAt ?? DateTime.now());
    if (mounted) {
      _refreshState();
      _redraw();
    }
  }

  // ---- the gallery ------------------------------------------------------------

  Future<void> _openGallery() async {
    final store = _store;
    if (store == null) {
      _toast('Library is still loading…');
      return;
    }
    if (_playing) _pause();
    await _autosave?.flushNow(); // make sure the current drawing shows up fresh in the list
    if (!mounted) return;
    final result = await Navigator.of(context).push<GalleryResult>(
      MaterialPageRoute(builder: (_) => GalleryPage(store: store, currentId: _drawingId)),
    );
    if (!mounted) return;
    // A gallery rename of the open drawing lands in meta.json only; re-adopt the title so the
    // next autosave doesn't stamp the old one back.
    final id = _drawingId;
    if (id != null) {
      final meta = await store.readMeta(id);
      if (!mounted) return;
      if (meta != null && meta.title != _drawingTitle) {
        setState(() => _drawingTitle = meta.title);
      }
    }
    if (result == null) return;
    switch (result.action) {
      case GalleryAction.open:
        await _openExistingDrawing(result.id!);
        break;
      case GalleryAction.newDrawing:
        await _switchToNewDrawing(title: 'Untitled', mutateEngine: () {
          _send('NewDocument(64,64)');
          _resendEngineTool();
        });
        if (mounted) {
          _refreshState();
          _redraw();
        }
        break;
    }
  }
}
