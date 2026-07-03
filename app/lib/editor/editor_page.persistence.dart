part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Extension on _EditorPageState — a State subclass — so calling @protected setState here is safe;
// the analyzer's check is a false positive for the part/extension split.)

// Local artwork persistence: the working library (each drawing is its own folder), silent crash-safe
// autosave of the current drawing, recovery on launch, and switching between drawings. The Rust
// engine is untouched — this is all shell-side over the existing `.mkpx` save/load FFI.
// Plan + rationale: docs/plans/persistence-autosave.md.
// The user's decision for the current drawing when new artwork is about to replace the canvas.
enum _OutgoingChoice { discard, save }

extension _EditorPersistence on _EditorPageState {
  // ---- startup ----------------------------------------------------------------

  // Resolve the on-disk library, then either silently restore the last drawing, hand off to a
  // pending Club edit (which opens as its own new drawing), or start a fresh tracked drawing.
  Future<void> _initPersistence() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _store = DrawingStore(dir);
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('persistence init failed (editor still usable, no autosave): $e');
      return;
    }
    if (!mounted) return;

    final curId = _prefs?.getString(_kCurrentDrawing);
    if (curId != null && await _store!.exists(curId) && await _loadDrawingIntoEngine(curId)) {
      final meta = await _store!.readMeta(curId);
      _adopt(curId, meta?.title ?? 'Untitled', meta?.createdAt ?? DateTime.now());
    } else {
      // No restorable current drawing → track the default 64×64 doc as a fresh one.
      await _createFreshDrawing(title: 'Untitled');
    }
    if (mounted) {
      _refreshState();
      _redraw();
      setState(() {});
    }

    // Consume any pending Club "Edit in Makapix" request only AFTER the real current drawing is
    // back in the engine, so the replace-ask judges (and can save/discard) the actual document —
    // not the placeholder 64×64 the engine boots with.
    final pending = ref.read(pendingClubEditProvider);
    if (pending != null && mounted) await _consumeClubEdit(pending);
  }

  // ---- the autosave wiring ----------------------------------------------------

  void _startAutosave() {
    final id = _drawingId, store = _store;
    if (id == null || store == null) return;
    _autosave = AutosaveController(
      id: id,
      store: store,
      serialize: () => _engineReady ? engine.save() : Uint8List(0),
      buildMeta: _buildMeta,
      onError: _onAutosaveError,
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

  // ---- drawing identity transitions -------------------------------------------

  // Adopt an already-loaded drawing as the current one (no engine change) and begin autosaving it.
  void _adopt(String id, String title, DateTime createdAt) {
    _drawingId = id;
    _drawingTitle = title;
    _drawingCreatedAt = createdAt;
    _prefs?.setString(_kCurrentDrawing, id);
    _startAutosave();
  }

  // Begin tracking a brand-new library drawing for whatever the engine currently holds, writing it
  // to disk immediately so it exists in the gallery and is crash-safe from the first moment.
  Future<void> _createFreshDrawing({required String title}) async {
    _adopt(DrawingStore.newId(), title, DateTime.now());
    await _autosave?.flushNow();
  }

  // Load a drawing's bytes into the engine, falling back to its `.bak` on a corrupt primary. Uses
  // `engine.load` as the validator so the right file is both chosen and loaded in one pass.
  Future<bool> _loadDrawingIntoEngine(String id) async {
    final store = _store;
    if (store == null || !_engineReady) return false;
    final bytes = await store.readDoc(id, validate: (b) => engine.load(b));
    return bytes != null;
  }

  // Stop tracking the outgoing drawing before a switch: either flush-and-keep it in the library,
  // or delete it (the caller decided — blank auto-discard or the user's explicit choice).
  Future<void> _releaseOutgoing({required bool discard}) async {
    if (!discard) await _autosave?.flushNow();
    await _autosave?.stop(); // waits for any in-flight write before a delete pulls the folder
    _autosave = null;
    final id = _drawingId;
    if (discard && id != null) {
      try {
        await _store?.delete(id);
      } catch (_) {/* best-effort: an orphaned folder is harmless */}
    }
  }

  // Silent release: a blank drawing (single never-painted layer — see _isBlankDocument) is
  // deleted from the library instead of flushed, so switching away never accumulates empty
  // Untitled entries; anything else is saved as before.
  Future<void> _releaseOutgoingDrawing() =>
      _releaseOutgoing(discard: _engineReady && _isBlankDocument());

  // Interactive release, for every path that LOADS artwork over the canvas (Club edit, Open,
  // gallery). A blank canvas has nothing to protect and releases silently; otherwise the user
  // chooses: keep the current drawing in My Drawings, discard it, or cancel the load.
  // Returns false when cancelled — the caller must abort.
  Future<bool> _releaseOutgoingDrawingInteractive(String incoming) async {
    if (!_engineReady || !mounted) return false;
    if (_isBlankDocument()) {
      await _releaseOutgoing(discard: true);
      return true;
    }
    final choice = await showDialog<_OutgoingChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Open $incoming?'),
        content: Text('What should happen to your current drawing, "$_drawingTitle"?'),
        // Discard sits alone at the far LEFT, opposite Keep, so a mis-click near the usual
        // confirm corner can't destroy work; it also re-confirms below.
        actions: [
          Row(children: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFE06060)),
              onPressed: () => Navigator.pop(ctx, _OutgoingChoice.discard),
              child: const Text('Discard it'),
            ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _OutgoingChoice.save),
              child: const Text('Keep in My Drawings'),
            ),
          ]),
        ],
      ),
    );
    if (choice == null) return false;
    if (choice == _OutgoingChoice.discard) {
      if (!mounted) return false;
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
      if (sure != true) return false; // declined → the whole load is cancelled
    }
    await _releaseOutgoing(discard: choice == _OutgoingChoice.discard);
    return true;
  }

  // Save the outgoing drawing, mutate the engine to new content (NewDocument / a loaded Club
  // artwork), then track that content as a brand-new library drawing. The old drawing stays in the
  // library (blank ones are discarded), so switching never clobbers work.
  Future<void> _switchToNewDrawing({
    required String title,
    required void Function() mutateEngine,
  }) async {
    await _releaseOutgoingDrawing();
    mutateEngine();
    await _createFreshDrawing(title: title);
  }

  // Open an existing library drawing (from the gallery): ask keep/discard/cancel for a non-blank
  // current one, release it accordingly, then load the target and adopt it.
  Future<void> _openExistingDrawing(String id) async {
    if (id == _drawingId) return;
    final meta = await _store?.readMeta(id);
    if (!mounted) return;
    if (!await _releaseOutgoingDrawingInteractive('"${meta?.title ?? 'Untitled'}"')) return;
    final ok = await _loadDrawingIntoEngine(id);
    if (!ok && mounted) _toast('Could not open that drawing (file missing or corrupt)');
    _clubSource = null;
    _adopt(id, meta?.title ?? 'Untitled', meta?.createdAt ?? DateTime.now());
    if (mounted) {
      _refreshState();
      _redraw();
      setState(() {});
    }
  }

  // ---- the gallery ------------------------------------------------------------

  Future<void> _openGallery() async {
    final store = _store;
    if (store == null) {
      _toast('Library is still loading…');
      return;
    }
    await _autosave?.flushNow(); // make sure the current drawing shows up fresh in the list
    if (!mounted) return;
    final result = await Navigator.of(context).push<GalleryResult>(
      MaterialPageRoute(builder: (_) => GalleryPage(store: store, currentId: _drawingId)),
    );
    if (result == null || !mounted) return;
    switch (result.action) {
      case GalleryAction.open:
        await _openExistingDrawing(result.id!);
        break;
      case GalleryAction.newDrawing:
        await _switchToNewDrawing(title: 'Untitled', mutateEngine: () {
          _send('NewDocument(64,64)');
          _send('SelectTool($_tool)');
        });
        if (mounted) {
          _refreshState();
          _redraw();
          setState(() {});
        }
        break;
    }
  }
}
