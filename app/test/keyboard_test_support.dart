// Shared fake for the keyboard suites: EditorAccess with settable modality state and a call
// log — the FakePaletteHost/FakeReplayHost pattern, keeping the whole keyboard layer testable
// without the engine binary.
import 'package:makapix_club/editor/keyboard/editor_access.dart';

class FakeEditorAccess implements EditorAccess {
  final List<String> calls = [];

  bool hasAnyDraftV = false;
  bool isPlayingV = false;
  int frameCountV = 1;
  bool canUndoV = false;
  bool canRedoV = false;
  bool hasSelectionV = false;
  int layerCountV = 1;
  int activeLayerV = 0;
  String activeToolV = 'Pencil';
  bool brushSizeAppliesV = true;
  bool interactionActiveV = false;
  int finishCount = 0;
  int cancelCount = 0;

  @override
  bool get hasAnyDraft => hasAnyDraftV;
  @override
  bool get isPlaying => isPlayingV;
  @override
  int get frameCount => frameCountV;
  @override
  bool get canUndo => canUndoV;
  @override
  bool get canRedo => canRedoV;
  @override
  bool get hasSelection => hasSelectionV;
  @override
  int get layerCount => layerCountV;
  @override
  int get activeLayer => activeLayerV;
  @override
  String get activeTool => activeToolV;
  @override
  bool get brushSizeApplies => brushSizeAppliesV;
  @override
  bool get interactionActive => interactionActiveV;
  @override
  void finishInteraction() => finishCount++;
  @override
  void cancelInteraction() => cancelCount++;

  @override
  void selectTool(String dsl) => calls.add('selectTool:$dsl');
  @override
  void toggleOnion() => calls.add('toggleOnion');
  @override
  void undo() => calls.add('undo');
  @override
  void redo() => calls.add('redo');
  @override
  void commitDraft() => calls.add('commitDraft');
  @override
  void cancelDraft() => calls.add('cancelDraft');
  @override
  void selectAll() => calls.add('selectAll');
  @override
  void deselect() => calls.add('deselect');
  @override
  void copySelection() => calls.add('copySelection');
  @override
  void pasteFromKeyboard() => calls.add('pasteFromKeyboard');
  @override
  void stepFrame(int delta) => calls.add('stepFrame:$delta');
  @override
  void addFrame() => calls.add('addFrame');
  @override
  void duplicateFrame() => calls.add('duplicateFrame');
  @override
  void deleteFrame() => calls.add('deleteFrame');
  @override
  void addLayer() => calls.add('addLayer');
  @override
  void moveLayer(int delta) => calls.add('moveLayer:$delta');
  @override
  void togglePlayback() => calls.add('togglePlayback');
  @override
  void pausePlayback() => calls.add('pausePlayback');
  @override
  void zoomIn() => calls.add('zoomIn');
  @override
  void zoomOut() => calls.add('zoomOut');
  @override
  void zoomFit() => calls.add('zoomFit');
  @override
  void zoom100() => calls.add('zoom100');
  @override
  void cycleSymmetry() => calls.add('cycleSymmetry');
  @override
  void swapWithPreviousColor() => calls.add('swapWithPreviousColor');
  @override
  void brushSizeBy(int delta) => calls.add('brushSizeBy:$delta');
  @override
  void save() => calls.add('save');
  @override
  void openExportMenu() => calls.add('openExportMenu');
  @override
  void openFrameSheet() => calls.add('openFrameSheet');
  @override
  void openLayerSheet() => calls.add('openLayerSheet');
  @override
  void setSpacePan(bool held) => calls.add('setSpacePan:$held');
  @override
  void beginHoldPick() => calls.add('beginHoldPick');
  @override
  void endHoldPick() => calls.add('endHoldPick');
  @override
  void setConstrain(bool held) => calls.add('setConstrain:$held');
  @override
  void openKeyboardHelp() => calls.add('openKeyboardHelp');
}
