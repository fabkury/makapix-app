part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Extension on _EditorPageState — a State subclass — so calling @protected setState here is safe;
// the analyzer's check is a false positive for the part/extension split.)

// Local artwork persistence: the working library (each drawing is its own folder), silent crash-safe
// autosave of the current drawing, recovery on launch, and switching between drawings. The Rust
// engine is untouched — this is all shell-side over the existing `.mkpx` save/load FFI.
// Plan + rationale: docs/plans/persistence-autosave.md.
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

    final pending = ref.read(pendingClubEditProvider);
    if (pending != null) {
      await _consumeClubEdit(pending); // opens the artwork as a new library drawing
      return;
    }

    final curId = _prefs?.getString(_kCurrentDrawing);
    if (curId != null && await _store!.exists(curId) && await _loadDrawingIntoEngine(curId)) {
      final meta = await _store!.readMeta(curId);
      _adopt(curId, meta?.title ?? 'Untitled', meta?.createdAt ?? DateTime.now());
      if (mounted) {
        _refreshState();
        _redraw();
        setState(() {});
      }
    } else {
      // No restorable current drawing → track the default 64×64 doc as a fresh one.
      await _createFreshDrawing(title: 'Untitled');
      if (mounted) {
        _refreshState();
        _redraw();
        setState(() {});
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

  // Save the outgoing drawing, mutate the engine to new content (NewDocument / a loaded Club
  // artwork), then track that content as a brand-new library drawing. The old drawing stays in the
  // library, so switching never clobbers work.
  Future<void> _switchToNewDrawing({
    required String title,
    required void Function() mutateEngine,
  }) async {
    await _autosave?.flushNow();
    await _autosave?.stop();
    _autosave = null;
    mutateEngine();
    await _createFreshDrawing(title: title);
  }

  // Open an existing library drawing (from the gallery): save+stop the current one, load the target,
  // and adopt it.
  Future<void> _openExistingDrawing(String id) async {
    if (id == _drawingId) return;
    await _autosave?.flushNow();
    await _autosave?.stop();
    _autosave = null;
    final ok = await _loadDrawingIntoEngine(id);
    if (!ok && mounted) _toast('Could not open that drawing (file missing or corrupt)');
    final meta = await _store?.readMeta(id);
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
