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

  // ---- color / brush ----
  void swapWithPreviousColor();
  void brushSizeBy(int delta);

  // ---- file / panels ----
  void save();
  void openExportMenu();
  void openFrameSheet();
  void openLayerSheet();
}
