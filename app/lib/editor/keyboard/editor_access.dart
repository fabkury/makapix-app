// EditorAccess: the narrow Host interface keyboard Commands invoke the editor through
// (ADR 0009 — a Command always takes the same shell pathway as its on-screen control, never raw
// DSL). Implemented by an adapter over _EditorPageState (editor_page.keyboard.dart) and by
// FakeEditorAccess in tests — the PaletteHost/ReplayHost pattern, so the whole keyboard layer
// stays testable without the engine binary.
abstract class EditorAccess {
  // ---- modality / enablement queries ----
  bool get hasAnyDraft;
  bool get isPlaying;
  int get frameCount;
  bool get canUndo;
  bool get canRedo;
  bool get hasSelection;
  int get layerCount;
  int get activeLayer;
  String get activeTool; // the shell tool name (tools.dart dsl)
  bool get brushSizeApplies; // the active tool uses the brush-size setting
  /// ADR 0010: ANY Gesture is in flight — canvas drag, pinch, precision pen, trackpad
  /// gesture, or a control drag. A gate that knew only about two of the five just relocated
  /// the drift, so this is the single predicate the whole keyboard layer asks.
  bool get interactionActive;

  /// End an in-flight Gesture as if the artist lifted, then let the Command run (finish-then-do).
  /// Invoked for every Command EXCEPT the cancel pair below — including view Commands, which
  /// never reach the engine and so would otherwise slip past the funnel's own gate [G-06].
  void finishInteraction();

  /// Abort an in-flight Gesture: Esc and Undo/Redo mean "not this". They discard the stroke,
  /// revert a control drag, and consume the keystroke instead of reaching history [G-05].
  void cancelInteraction();

  // ---- Hold bindings (DESIGN.md §2.3): act while the Chord is held, revert on release.
  // The dispatcher owns the key state machine and guarantees begin/end pairing (including
  // forced release on focus loss and app backgrounding); the host owns the effect.
  void setSpacePan(bool held); // hold-Space: canvas drags pan the view while held
  void beginHoldPick(); // hold-S: temporary Eyedropper, remembering the current tool
  void endHoldPick(); // restore the remembered tool (no-op if the user switched meanwhile)
  void setConstrain(bool held); // hold-Shift: directional drags snap/lock (fixed grammar)

  // ---- tool / edit ----
  void selectTool(String dsl); // _selectTool: cancels drafts, pauses playback, etc.
  void toggleOnion();
  void undo();
  void redo();
  void commitDraft();
  void cancelDraft();
  void selectAll();
  void deselect();
  void copySelection();
  void pasteFromKeyboard(); // switches to the CopyPaste tool, then starts the paste draft

  // ---- frames / layers ----
  void stepFrame(int delta);
  void addFrame();
  void duplicateFrame();
  void deleteFrame();
  void addLayer();
  void moveLayer(int delta); // reorder the active layer up (+1) / down (-1) the stack

  // ---- playback / view ----
  void togglePlayback();
  void pausePlayback();
  void zoomIn();
  void zoomOut();
  void zoomFit();
  void zoom100();

  // ---- symmetry (ADR 0026) ----
  void cycleSymmetry(); // Off → H → V → Both → Off; toasts the new mode when no Mirror chip shows

  // ---- color / brush ----
  void swapWithPreviousColor();
  void brushSizeBy(int delta);

  // ---- file / panels ----
  void save();
  void openExportMenu();
  void openFrameSheet();
  void openLayerSheet();
  void openKeyboardHelp(); // the ☰ → Keyboard cheat-sheet page
}
