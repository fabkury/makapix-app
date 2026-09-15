part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// The Layers page's editor half (ADR 0033): the host the page talks to, the route push, and
// the post-pop reconciliation. The page itself (app/lib/editor/layers/) never sees the engine.

class _EditorLayersHost implements LayersHost {
  _EditorLayersHost(this._s);
  final _EditorPageState _s;

  @override
  List<LayerRow> get layers => parseLayerDetail(_s._state['frame_detail'] as List?, _s.engine.activeFrame);

  @override
  int get activeLayerIndex => _s._activeLayerIndex();

  @override
  int get activeFrameIndex => _s.engine.activeFrame;

  @override
  int get frameCount => _s.engine.frameCount;

  @override
  ({int w, int h}) get canvasSize => (w: _s.engine.width, h: _s.engine.height);

  @override
  bool get canUndo => _s._state['can_undo'] == true;

  @override
  bool get canRedo => _s._state['can_redo'] == true;

  @override
  int get sendSeq => _s._sendSeq;

  int _refusalSeq() => ((_s._state['refusal_seq'] as num?) ?? 0).toInt();

  /// Every batch verb rides `_act`: Drafts die (the verbs are in the context-change list),
  /// playback pauses, the Journal records the line, autosave is armed, the state refreshes.
  /// A refusal is detected through the engine's `refusal_seq` telemetry advancing across the
  /// call; the page narrates it on its status line, so the editor's toast is suppressed.
  @override
  String? run(String dsl) {
    final before = _refusalSeq();
    _s._suppressRefusalToast = true;
    try {
      _s._act(dsl);
    } finally {
      _s._suppressRefusalToast = false;
    }
    if (_refusalSeq() == before) return null;
    return (_s._state['last_refusal'] as String?) ?? 'The engine refused this change';
  }

  @override
  void undo() => _s._doToolAction('Undo');

  @override
  void redo() => _s._doToolAction('Redo');

  @override
  Uint8List thumbBytes(int index, int tw, int th) => _s.engine.layerThumb(_s.engine.activeFrame, index, tw, th);

  @override
  int layerHash(int index) => _s.engine.layerHash(_s.engine.activeFrame, index);

  @override
  Future<void> openLayerSheet(int index) => _s._layerOptions(index);
}

extension _EditorLayers on _EditorPageState {
  /// The active frame's stack identity: layer ids in order plus the active layer's id. When it
  /// changed across the page, the strip's Move-group chips may point at the wrong rows.
  String _layerStackSignature() {
    final layers = _layerList();
    final active = _activeLayerIndex();
    final ids = [for (final l in layers) ((l as Map)['id'] as num?)?.toInt() ?? -1];
    final activeId = active < ids.length ? ids[active] : -1;
    return '${ids.join(',')}|$activeId';
  }

  /// Push the Layers page. Not a context change (the palette-page precedent, ADR 0011): an open
  /// Draft survives the trip and dies only when a batch verb runs. On return: Make active
  /// activates its layer; Use as Move group sets the group (the first member becomes active);
  /// otherwise the group is cleared when the stack or the active layer changed underneath it.
  Future<void> _openLayersPage() async {
    if (_playing) _pause();
    final before = _layerStackSignature();
    final result = await Navigator.of(context).push<LayersPageResult>(MaterialPageRoute(
      builder: (_) => LayersPage(
        host: _EditorLayersHost(this),
        roomyRows: _layersRoomyRows,
        onRoomyRowsChanged: (v) {
          _layersRoomyRows = v;
          _persistLayersRows();
        },
      ),
    ));
    if (!mounted) return;
    final group = result?.moveGroup;
    final activate = result?.activateIndex;
    if (group != null && group.isNotEmpty) {
      // SetActiveLayers: the first member becomes active and the set becomes the Move group;
      // the strip's chips mirror it.
      _act('SetActiveLayers(${group.join(', ')})');
      setState(() => _selLayers
        ..clear()
        ..addAll(group.where((i) => i < _layerList().length)));
    } else if (activate != null && activate < _layerList().length) {
      _clearLayerGroup();
      if (activate != _activeLayerIndex()) _act('SetActiveLayer($activate)');
    } else {
      if (_layerStackSignature() != before) _clearLayerGroup();
      _refreshState();
      _redraw();
    }
  }

  Future<void> _persistLayersRows() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLayersRoomyRowsPref, _layersRoomyRows);
    } catch (_) {}
  }
}
