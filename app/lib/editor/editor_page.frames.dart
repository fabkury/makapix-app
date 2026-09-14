part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// The Frames page's editor half (ADR 0031): the host the page talks to, the route push, and
// the post-pop reconciliation. The page itself (app/lib/editor/frames/) never sees the engine.

class _EditorFramesHost implements FramesHost {
  _EditorFramesHost(this._s);
  final _EditorPageState _s;

  @override
  List<FrameInfo> get frames => parseFrameDetail(_s._state['frame_detail'] as List?);

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
  /// playback pauses, the Journal records the line, autosave is armed, the state refreshes,
  /// and the film roll reveals the active frame on return. A refusal is detected through the
  /// engine's `refusal_seq` telemetry advancing across the call.
  @override
  String? run(String dsl) {
    final before = _refusalSeq();
    _s._suppressRefusalToast = true; // the page shows the reason on its own status line
    try {
      _s._act(dsl);
    } finally {
      _s._suppressRefusalToast = false;
    }
    if (_refusalSeq() == before) return null;
    return (_s._state['last_refusal'] as String?) ?? 'The engine refused this change';
  }

  // Undo/Redo take the editor's tile path (ADR 0017): a pending Move draft is discarded first,
  // exactly as the editor's own tile does.
  @override
  void undo() => _s._doToolAction('Undo');

  @override
  void redo() => _s._doToolAction('Redo');

  @override
  Uint8List thumbBytes(int index, int tw, int th) => _s.engine.frameThumb(index, tw, th);

  @override
  int frameHash(int index) => _s.engine.frameHash(index);

  @override
  Future<void> openFrameSheet(int index) => _s._frameMenu(index);
}

extension _EditorFrames on _EditorPageState {
  /// Push the Frames page. Not a context change (the palette-page precedent, ADR 0011): an open
  /// Draft survives the trip and dies only when a batch verb runs. On return: a Go-to activates
  /// its frame; otherwise the active target may have moved (a batch delete removed it) and the
  /// layer group is cleared accordingly; the film roll re-syncs and reveals the active frame.
  Future<void> _openFramesPage() async {
    if (_playing) _pause();
    final activeBefore = engine.activeFrame;
    final goTo = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => FramesPage(
        host: _EditorFramesHost(this),
        columns: _framesColumns,
        onColumnsChanged: (c) {
          _framesColumns = c;
          _persistFramesColumns();
        },
      ),
    ));
    if (!mounted) return;
    if (goTo != null && goTo != engine.activeFrame && goTo < engine.frameCount) {
      _clearLayerGroup(); // a different frame (with its own layer stack) becomes active
      _act('SetActiveFrame($goTo)');
    } else {
      if (engine.activeFrame != activeBefore) _clearLayerGroup();
      _refreshState();
      _redraw();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureActiveFrameVisible();
    });
  }

  Future<void> _persistFramesColumns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kFramesColumnsPref, _framesColumns);
    } catch (_) {}
  }
}
