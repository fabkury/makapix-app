part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _EditorPageState — the setState calls here are the State's own; see the note in
// editor_page.toolgrid.dart.)

// The physical-keyboard seam (DESIGN.md; ADR 0009): _EditorKeyboardHost is the real
// EditorAccess — every keyboard Command lands on the SAME shell pathway as its on-screen
// control (draft bookkeeping, playback pauses, and the Journal tap come along for free), and
// raw DSL never appears here except through the same _act lines the buttons themselves use.

class _EditorKeyboardHost implements EditorAccess {
  _EditorKeyboardHost(this._s);
  final _EditorPageState _s;

  @override
  bool get hasAnyDraft => _s._hasAnyDraft;
  @override
  bool get isPlaying => _s._playing;
  @override
  int get frameCount => _s.engine.frameCount;
  @override
  bool get canUndo => _s._actionEnabled('Undo');
  @override
  bool get canRedo => _s._actionEnabled('Redo');
  @override
  bool get hasSelection => _s._selectionEdges.isNotEmpty;
  @override
  int get layerCount => _s._layerList().length;
  @override
  int get activeLayer => _s._activeLayerIndex();
  @override
  String get activeTool => _s._tool;
  @override
  bool get brushSizeApplies => _kBrushSizeTools.contains(_s._tool);
  @override
  bool get pointerActive => _s._drawPointer != null || _s._pinching;

  @override
  void selectTool(String dsl) => _s._selectTool(dsl);
  @override
  void toggleOnion() => _s._doToolAction('Onion');
  @override
  void undo() => _s._doToolAction('Undo');
  @override
  void redo() => _s._doToolAction('Redo');
  @override
  void commitDraft() => _s._commitActiveDraft();
  @override
  void cancelDraft() => _s._cancelActiveDraft();
  @override
  void selectAll() => _s._act('SelectAll()');
  @override
  void deselect() => _s._act('SelectNone()');
  @override
  void copySelection() => _s._act('Copy()');
  @override
  void pasteFromKeyboard() {
    // The paste draft needs the CopyPaste tool mounted (its row-1 controls, its canvas drag,
    // and _selectTool's leave-cancel contract), so a global paste switches tool first.
    if (_s._tool != 'CopyPaste') _s._selectTool('CopyPaste');
    _s._act('PasteDraft()');
  }

  @override
  void stepFrame(int delta) => _s._stepFrame(delta);
  @override
  void addFrame() {
    _s._clearLayerGroup();
    _s._act('AddFrame()');
  }

  @override
  void duplicateFrame() {
    if (_s._playing) _s._pause();
    _s._clearLayerGroup(); // a different frame becomes active
    _s._act('DuplicateFrame(${_s.engine.activeFrame})');
  }

  @override
  void deleteFrame() {
    if (_s.engine.frameCount <= 1) return;
    if (_s._playing) _s._pause();
    _s._clearLayerGroup(); // a different frame (with its own layer stack) may become active
    _s._act('RemoveFrame(${_s.engine.activeFrame})');
  }

  @override
  void addLayer() {
    _s._clearLayerGroup(); // focus moves to the new layer; the engine resets its group too
    _s._act('AddLayerAt(${_s._activeLayerIndex() + 1})');
  }

  @override
  void moveLayer(int delta) {
    final from = _s._activeLayerIndex(), to = from + delta;
    if (to < 0 || to >= _s._layerList().length) return;
    _s._reorderLayerTracked(from, to);
  }

  @override
  void togglePlayback() => _s._togglePlay();
  @override
  void pausePlayback() {
    if (_s._playing) _s._pause();
  }

  @override
  void zoomIn() => _s._zoomStep(1.5);
  @override
  void zoomOut() => _s._zoomStep(1 / 1.5);
  @override
  void zoomFit() => _s._fitView();
  @override
  void zoom100() => _s._zoomActualPixels();

  @override
  void swapWithPreviousColor() => _s._setPrimary(_s._previousPrimary);
  @override
  void brushSizeBy(int delta) => _s._brushSizeBy(delta);

  @override
  void save() {
    if (_s._playing) _s._pause();
    _s._save();
  }

  @override
  void openExportMenu() {
    if (_s._playing) _s._pause();
    _s._importExportMenu();
  }

  @override
  void openFrameSheet() => _s._frameMenu(_s.engine.activeFrame); // pauses playback itself
  @override
  void openLayerSheet() => _s._layerOptions(_s._activeLayerIndex()); // pauses playback itself

  // ---- Hold bindings (the dispatcher guarantees begin/end pairing and forced release) ----

  @override
  void setSpacePan(bool held) {
    // Only the flag: an in-flight drag keeps the meaning it began with (`_panDragLast` marks
    // a pan drag until pointer-up), so press/release mid-drag never hijacks a stroke.
    _s._spacePanning = held;
  }

  @override
  void beginHoldPick() {
    // The dispatcher already guards drafts and active drags; re-check the tool here.
    if (_s._tool == 'Eyedropper') return;
    _s._holdPickPrevTool = _s._tool;
    _s._selectTool('Eyedropper');
  }

  @override
  void endHoldPick() {
    final prev = _s._holdPickPrevTool;
    _s._holdPickPrevTool = null;
    if (!_s.mounted) return; // forced release during editor teardown: nothing to restore
    // Restore only if the spring is still in effect — a tap on another tool wins.
    if (prev != null && _s._tool == 'Eyedropper') _s._selectTool(prev);
  }
}

// New thin shell methods the keyboard needed but no button had reified yet. Each mirrors its
// on-screen closure exactly; the closures should migrate to these over time rather than fork.
extension _EditorKeyboardOps on _EditorPageState {
  // The play/pause toggle (the row-1 button's closure, editor_page.controls.dart).
  void _togglePlay() {
    if (engine.frameCount <= 1) return;
    _playing ? _pause() : _play();
  }

  // Brush size for the tools that stamp a footprint (same clamp as the row-1 slider).
  void _brushSizeBy(int delta) {
    if (!_kBrushSizeTools.contains(_tool)) return;
    final v = (_brushSize + delta).clamp(1, 32);
    if (v == _brushSize) return;
    setState(() => _brushSize = v);
    _send('SetBrushSize($_brushSize)');
  }

  // Keyboard zoom steps around the canvas-center focal point (the pinch math with the box
  // center as the fixed point). Falls back to a bare zoom change before the first layout.
  void _zoomTo(double target) {
    final z = target.clamp(_kMinZoom, _kMaxZoom).toDouble();
    final box = _lastCanvasBox;
    if (box == null) {
      setState(() => _zoom = z);
      return;
    }
    final (s0, off0) = _view(box);
    final center = Offset(box.width / 2, box.height / 2);
    final focal = (center - off0) / s0; // canvas point currently at the box center
    final s1 = _fitScale(box) * z;
    setState(() {
      _zoom = z;
      _pan = (center - focal * s1) - _centeredOffset(box, s1);
    });
  }

  void _zoomStep(double factor) => _zoomTo(_zoom * factor);

  // Hold-Space pan: shift the view by a screen-pixel delta (the canvas pan drag's engine-free
  // twin of the pinch's derived pan).
  void _panBy(Offset screenDelta) => setState(() => _pan += screenDelta);

  // "Actual pixels": one canvas pixel per logical screen pixel (zoom is fit-relative).
  void _zoomActualPixels() {
    final box = _lastCanvasBox;
    if (box == null) return;
    _zoomTo(1 / _fitScale(box));
  }
}
