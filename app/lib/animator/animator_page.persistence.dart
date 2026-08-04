part of 'animator_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _AnimatorPageState — the editor part files' rationale: extensions on a State
// subclass trip a false positive calling the @protected setState.)

// Local persistence: the current library scene + its autosave (the editor's exact model —
// the pillar is fully remounted on every shell switch, so continuity is: autosave flush in
// dispose → silent restore of the last-open scene here). Also consumes the cross-pillar
// AnimatorRequest (mount-time re-read + the build() listener — the two-listener bridge).
extension _AnimatorPersistence on _AnimatorPageState {
  Future<void> _initPersistence() async {
    _prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationSupportDirectory();
    _store = SceneStore(dir);
    if (!mounted) return;

    final zoomIx = _prefs!.getInt(_kTimelineZoomPref);
    if (zoomIx != null && zoomIx >= 0 && zoomIx < TimelineZoom.values.length) {
      _timelineZoom = TimelineZoom.values[zoomIx];
    }

    // Silent restore of the last-open scene; else start a fresh default scene.
    final currentId = _prefs!.getString(_kCurrentScene);
    var restored = false;
    if (currentId != null && await _store!.exists(currentId)) {
      restored = await _loadSceneIntoEngine(currentId);
      if (restored) {
        final meta = await _store!.readMeta(currentId);
        _adopt(currentId, meta?.title ?? 'Untitled',
            meta?.createdAt ?? DateTime.now().toUtc());
      }
    }
    if (!restored) {
      await _createFreshScene(const NewSceneSpec(64, 64, 12500, 25), title: 'Untitled');
    }

    _refreshState();
    _redrawCurrent();
    if (mounted) setState(() {});

    // Consume a request that arrived before this pillar was mounted (see the ordering note
    // in the editor's persistence: consume AFTER the real current scene is restored).
    final pending = ref.read(pendingAnimatorProvider);
    if (pending != null && mounted) await _consumeAnimatorRequest(pending);
  }

  // ---- autosave wiring ---------------------------------------------------------------------

  void _startAutosave() {
    final id = _sceneId, store = _store;
    if (id == null || store == null) return;
    _autosave = AutosaveController<SceneMeta>(
      id: id,
      writeDoc: store.writeDoc,
      writeMeta: store.writeMeta,
      serialize: () => _engineReady ? engine.save() : Uint8List(0),
      buildMeta: _buildMeta,
      onError: _onAutosaveError,
    )..start();
  }

  SceneMeta _buildMeta() => SceneMeta(
        id: _sceneId ?? 'unknown',
        title: _sceneTitle,
        createdAt: _sceneCreatedAt,
        updatedAt: DateTime.now().toUtc(),
        width: _engineReady ? engine.width : 0,
        height: _engineReady ? engine.height : 0,
        frameCount: _engineReady ? engine.frameCount : 1,
        fpsMilli: _state.millifps,
      );

  void _onAutosaveError(Object e) {
    debugPrint('animator autosave error: $e');
    final now = DateTime.now();
    if (_lastAutosaveWarn == null ||
        now.difference(_lastAutosaveWarn!) > const Duration(seconds: 30)) {
      _lastAutosaveWarn = now;
      if (mounted) _toast("Couldn't autosave — check device storage");
    }
  }

  // ---- scene identity transitions ----------------------------------------------------------

  /// Adopt an already-loaded scene as current and begin autosaving it — the universal
  /// scene-switch funnel (open / new / gallery / bridge / startup).
  void _adopt(String id, String title, DateTime createdAt) {
    _autosave?.stop();
    _sceneId = id;
    _sceneTitle = title;
    _sceneCreatedAt = createdAt;
    _prefs?.setString(_kCurrentScene, id);
    _frameCache.clear();
    _frameVN.value?.dispose();
    _frameVN.value = null;
    _selTween = null;
    _focusActor = null;
    _keyDrag = null;
    _memRefusalsSeen = -1;
    _fitView();
    _startAutosave();
  }

  Future<bool> _loadSceneIntoEngine(String id) async {
    final bytes = await _store!.readDoc(id, validate: (b) => engine.load(b));
    return bytes != null;
  }

  Future<void> _createFreshScene(NewSceneSpec spec, {required String title}) async {
    final id = SceneStore.newId();
    _send('NewScene(${spec.width}, ${spec.height}, ${spec.fpsMilli})');
    _send('SetFrameCount(${spec.frames})');
    _adopt(id, title, DateTime.now().toUtc());
    _refreshState();
    _redrawCurrent();
    await _autosave?.flushNow();
    if (mounted) setState(() {});
  }

  /// Flush the outgoing scene; silently drop it from the library if it never gained content
  /// (an empty cast — the blank-scene auto-discard, so Untitleds don't litter My Scenes).
  Future<void> _releaseOutgoing() async {
    await _autosave?.flushNow();
    await _autosave?.stop();
    _autosave = null;
    final id = _sceneId;
    if (id != null && _state.cast.isEmpty && _state.actors.isEmpty) {
      await _store?.delete(id);
    }
  }

  Future<void> _switchToScene(String id) async {
    if (id == _sceneId) return;
    await _releaseOutgoing();
    if (!await _loadSceneIntoEngine(id)) {
      _toast("Couldn't open that scene.");
      // Recover: keep working on a fresh scene rather than a broken session.
      await _createFreshScene(const NewSceneSpec(64, 64, 12500, 25), title: 'Untitled');
      return;
    }
    final meta = await _store!.readMeta(id);
    _adopt(id, meta?.title ?? 'Untitled', meta?.createdAt ?? DateTime.now().toUtc());
    _refreshState();
    _redrawCurrent();
    if (mounted) setState(() {});
  }

  /// Returns true iff a new scene was actually created (false = dialog canceled).
  Future<bool> _newSceneFlow({int? prefillW, int? prefillH, String? title}) async {
    final spec = await showDialog<NewSceneSpec>(
      context: context,
      builder: (_) => NewSceneDialog(
        initialWidth: prefillW ?? 64,
        initialHeight: prefillH ?? 64,
      ),
    );
    if (spec == null) return false;
    await _releaseOutgoing();
    await _createFreshScene(spec, title: title ?? 'Untitled');
    return true;
  }

  Future<void> _openSceneGallery() async {
    final store = _store;
    if (store == null) return;
    if (_playing) _pause(); // park the playhead before the flush serializes the scene
    await _autosave?.flushNow();
    if (!mounted) return;
    final result = await Navigator.of(context).push<SceneGalleryResult>(
      MaterialPageRoute(
        builder: (_) => SceneGalleryPage(store: store, currentId: _sceneId),
      ),
    );
    switch (result?.action) {
      case SceneGalleryAction.open:
        await _switchToScene(result!.id!);
      case SceneGalleryAction.newScene:
        await _newSceneFlow();
      case null:
        break;
    }
  }

  /// "Open scene file…" landing: validate the bytes in a throwaway session, copy them into
  /// the library as a NEW scene titled after the file, then switch to it. Opening the same
  /// file twice deliberately makes two scenes — the picked file is never written back.
  Future<void> _importSceneBytes(Uint8List bytes, String title) async {
    final store = _store;
    if (store == null) return;
    var ok = false;
    int w = 0, h = 0, frames = 1, fps = 12500;
    final probe = SceneEngine.forLoad();
    try {
      ok = probe.load(bytes);
      if (ok) {
        w = probe.width;
        h = probe.height;
        frames = probe.frameCount;
        fps = SceneState.parse(probe.stateJson()).millifps;
      }
    } finally {
      probe.dispose();
    }
    if (!ok) {
      _toast("That .mkps can't be opened (corrupt, or over the scene memory budget).");
      return;
    }
    final id = SceneStore.newId();
    final now = DateTime.now().toUtc();
    await store.writeDoc(id, bytes);
    await store.writeMeta(SceneMeta(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
      width: w,
      height: h,
      frameCount: frames,
      fpsMilli: fps,
    ));
    await _switchToScene(id);
    if (mounted) _toast('Opened "$title" into My Scenes.');
  }

  // ---- the cross-pillar bridge -------------------------------------------------------------

  Future<void> _consumeAnimatorRequest(AnimatorRequest req) async {
    // Clear first so it doesn't re-fire (the editor bridge's rule).
    ref.read(pendingAnimatorProvider.notifier).state = null;
    if (!_engineReady || _store == null) return;
    if (_playing) _pause(); // external requests open modals over a live scene
    switch (req) {
      case NewScene():
        await _newSceneFlow();
      case OpenScene(:final id):
        await _switchToScene(id);
      case AnimateDrawing(:final id):
        await _animateDrawing(id);
      case OpenSceneBytes(:final bytes, :final title):
        // An "Open in Makapix" .mkps handed over by the OS — the same landing as the
        // in-app "Open scene file…" picker flow.
        await _importSceneBytes(bytes, title);
    }
  }

  /// "Animate this drawing": read the editor-library drawing, open a prefilled New-scene
  /// dialog, then run the standard import flow (Whole/Parts card included) on the bytes.
  Future<void> _animateDrawing(String id) async {
    final dir = await getApplicationSupportDirectory();
    final drawings = DrawingStore(dir);
    final bytes = await drawings.readDoc(id);
    if (bytes == null) {
      _toast("Couldn't read that drawing.");
      return;
    }
    final meta = await drawings.readMeta(id);
    final probe = ImportProbe.parse(SceneEngine.probeImport(bytes));
    if (probe.isError) {
      _toast("That drawing can't be imported.");
      return;
    }
    if (!mounted) return;
    final title = meta?.title ?? 'Untitled';
    final created = await _newSceneFlow(
      prefillW: probe.w.clamp(kSceneMinDim, kSceneMaxDim),
      prefillH: probe.h.clamp(kSceneMinDim, kSceneMaxDim),
      title: title,
    );
    if (created) {
      await _importBytesAsProps(bytes, title);
    }
  }
}
