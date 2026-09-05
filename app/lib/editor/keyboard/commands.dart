// The keyboard Command catalog (CONTEXT.md "Command"; DESIGN.md §3): pure data over the
// EditorAccess host. Ids are a persistent contract (ADR 0009) — the 6.B bindings file keys user
// customizations by them, so renaming/splitting an id requires a store migration, never a silent
// drop. Registry ORDER is meaningful: when one Chord binds several Commands (Enter = commit or
// play), the dispatcher invokes the first whose `enabled` is true.
import 'editor_access.dart';
import '../tools.dart';

class CommandDef {
  final String id;
  final String label;
  final String category; // Tools · Edit · Draft · Frames · Layers · View · Playback · Color · File · Panels
  /// Whether holding the key auto-repeats the Command (frame stepping, sizing, zooming).
  final bool repeats;
  final bool Function(EditorAccess a) enabled;
  final void Function(EditorAccess a) invoke;

  const CommandDef({
    required this.id,
    required this.label,
    required this.category,
    this.repeats = false,
    required this.enabled,
    required this.invoke,
  });
}

bool _always(EditorAccess a) => true;

/// tools.dart dsl → command id. Every ToolDef must appear here (unit-tested), so a new tool
/// fails the suite until it declares its Command.
const toolCommandIds = <String, String>{
  'Pencil': 'tool.pencil',
  'Brush': 'tool.brush',
  'Airbrush': 'tool.airbrush',
  'Eraser': 'tool.eraser',
  'Bucket': 'tool.fill',
  'Gradient': 'tool.gradient',
  'Line': 'tool.line',
  'Shape': 'tool.shape',
  'Ruler': 'tool.ruler',
  'Dodge': 'tool.dodge',
  'Burn': 'tool.burn',
  'Eyedropper': 'tool.pick',
  'Move': 'tool.move',
  'CopyPaste': 'tool.copyPaste',
  'SelectShape': 'tool.select',
  'SelectByColor': 'tool.selectColor',
  'SelectLayer': 'tool.selectLayer',
  'HsvShift': 'tool.hsv',
  'BrightnessContrast': 'tool.brightness',
  'Levels': 'tool.levels',
  'Flip': 'tool.flip',
  'Rotate': 'tool.rotate',
  'Resize': 'tool.resize',
  'Invert': 'tool.invert',
  'PlayPause': 'tool.play',
  'Onion': 'tool.onion',
};

/// The Commands whose Bindings may be remapped but never removed (design decision #7).
const coreCommandIds = {'draft.commit', 'draft.cancel', 'edit.undo', 'edit.redo'};

/// The full v1 catalog, in dispatch-priority order.
List<CommandDef> buildCommands() {
  return [
    // ---- Draft first: Enter/Esc belong to a pending draft before anything else ----
    CommandDef(
      id: 'draft.commit',
      label: 'Commit draft',
      category: 'Draft',
      enabled: (a) => a.hasAnyDraft,
      invoke: (a) => a.commitDraft(),
    ),
    CommandDef(
      id: 'draft.cancel',
      label: 'Cancel draft',
      category: 'Draft',
      enabled: (a) => a.hasAnyDraft,
      invoke: (a) => a.cancelDraft(),
    ),
    // ---- Playback (shares Enter/Esc with the draft pair; loses while a draft is pending) ----
    CommandDef(
      id: 'playback.toggle',
      label: 'Play / pause',
      category: 'Playback',
      enabled: (a) => a.frameCount > 1 && !a.hasAnyDraft,
      invoke: (a) => a.togglePlayback(),
    ),
    CommandDef(
      id: 'playback.stop',
      label: 'Stop playback',
      category: 'Playback',
      enabled: (a) => a.isPlaying && !a.hasAnyDraft,
      invoke: (a) => a.pausePlayback(),
    ),
    // ---- Edit ----
    CommandDef(
      id: 'edit.undo',
      label: 'Undo',
      category: 'Edit',
      repeats: true,
      enabled: (a) => a.canUndo,
      invoke: (a) => a.undo(),
    ),
    CommandDef(
      id: 'edit.redo',
      label: 'Redo',
      category: 'Edit',
      repeats: true,
      enabled: (a) => a.canRedo,
      invoke: (a) => a.redo(),
    ),
    CommandDef(
      id: 'edit.copy',
      label: 'Copy selection',
      category: 'Edit',
      enabled: (a) => a.hasSelection,
      invoke: (a) => a.copySelection(),
    ),
    CommandDef(
      id: 'edit.paste',
      label: 'Paste',
      category: 'Edit',
      enabled: _always,
      invoke: (a) => a.pasteFromKeyboard(),
    ),
    CommandDef(
      id: 'edit.selectAll',
      label: 'Select all',
      category: 'Edit',
      enabled: _always,
      invoke: (a) => a.selectAll(),
    ),
    CommandDef(
      id: 'edit.deselect',
      label: 'Deselect',
      category: 'Edit',
      enabled: (a) => a.hasSelection,
      invoke: (a) => a.deselect(),
    ),
    // ---- Tools (one Command per tools.dart entry; Onion is a toggle, the rest select) ----
    for (final t in tools)
      CommandDef(
        id: toolCommandIds[t.dsl]!,
        label: t.label,
        category: 'Tools',
        enabled: _always,
        invoke: (a) => t.dsl == 'Onion' ? a.toggleOnion() : a.selectTool(t.dsl),
      ),
    // ---- Frames ----
    CommandDef(
      id: 'frame.prev',
      label: 'Previous frame',
      category: 'Frames',
      repeats: true,
      enabled: (a) => a.frameCount > 1,
      invoke: (a) => a.stepFrame(-1),
    ),
    CommandDef(
      id: 'frame.next',
      label: 'Next frame',
      category: 'Frames',
      repeats: true,
      enabled: (a) => a.frameCount > 1,
      invoke: (a) => a.stepFrame(1),
    ),
    CommandDef(
      id: 'frame.add',
      label: 'Add frame',
      category: 'Frames',
      enabled: _always,
      invoke: (a) => a.addFrame(),
    ),
    CommandDef(
      id: 'frame.duplicate',
      label: 'Duplicate frame',
      category: 'Frames',
      enabled: _always,
      invoke: (a) => a.duplicateFrame(),
    ),
    CommandDef(
      id: 'frame.delete',
      label: 'Delete frame',
      category: 'Frames',
      enabled: (a) => a.frameCount > 1,
      invoke: (a) => a.deleteFrame(),
    ),
    // ---- Layers ----
    CommandDef(
      id: 'layer.up',
      label: 'Move layer up',
      category: 'Layers',
      enabled: (a) => a.activeLayer + 1 < a.layerCount,
      invoke: (a) => a.moveLayer(1),
    ),
    CommandDef(
      id: 'layer.down',
      label: 'Move layer down',
      category: 'Layers',
      enabled: (a) => a.activeLayer > 0,
      invoke: (a) => a.moveLayer(-1),
    ),
    CommandDef(
      id: 'layer.add',
      label: 'Add layer',
      category: 'Layers',
      enabled: _always,
      invoke: (a) => a.addLayer(),
    ),
    // ---- View ----
    CommandDef(
      id: 'view.zoomIn',
      label: 'Zoom in',
      category: 'View',
      repeats: true,
      enabled: _always,
      invoke: (a) => a.zoomIn(),
    ),
    CommandDef(
      id: 'view.zoomOut',
      label: 'Zoom out',
      category: 'View',
      repeats: true,
      enabled: _always,
      invoke: (a) => a.zoomOut(),
    ),
    CommandDef(
      id: 'view.zoomFit',
      label: 'Fit to screen',
      category: 'View',
      enabled: _always,
      invoke: (a) => a.zoomFit(),
    ),
    CommandDef(
      id: 'view.zoom100',
      label: 'Actual pixels',
      category: 'View',
      enabled: _always,
      invoke: (a) => a.zoom100(),
    ),
    // ---- Symmetry (ADR 0026): cycles Off → H → V → Both like the row-1 Mirror chip ----
    CommandDef(
      id: 'symmetry.cycle',
      label: 'Mirror (cycle Off · H · V · Both)',
      category: 'Tools',
      enabled: _always,
      invoke: (a) => a.cycleSymmetry(),
    ),
    // ---- Color / brush ----
    CommandDef(
      id: 'color.swap',
      label: 'Swap with previous color',
      category: 'Color',
      enabled: _always,
      invoke: (a) => a.swapWithPreviousColor(),
    ),
    CommandDef(
      id: 'brush.sizeUp',
      label: 'Brush size up',
      category: 'Color',
      repeats: true,
      enabled: (a) => a.brushSizeApplies,
      invoke: (a) => a.brushSizeBy(1),
    ),
    CommandDef(
      id: 'brush.sizeDown',
      label: 'Brush size down',
      category: 'Color',
      repeats: true,
      enabled: (a) => a.brushSizeApplies,
      invoke: (a) => a.brushSizeBy(-1),
    ),
    // ---- File / panels ----
    CommandDef(
      id: 'doc.save',
      label: 'Save',
      category: 'File',
      enabled: _always,
      invoke: (a) => a.save(),
    ),
    CommandDef(
      id: 'doc.export',
      label: 'Import & export…',
      category: 'File',
      enabled: _always,
      invoke: (a) => a.openExportMenu(),
    ),
    CommandDef(
      id: 'sheet.timeline',
      label: 'Frame options',
      category: 'Panels',
      enabled: _always,
      invoke: (a) => a.openFrameSheet(),
    ),
    CommandDef(
      id: 'sheet.layers',
      label: 'Layer options',
      category: 'Panels',
      enabled: _always,
      invoke: (a) => a.openLayerSheet(),
    ),
    CommandDef(
      id: 'help.keyboard',
      label: 'Keyboard shortcuts',
      category: 'Panels',
      enabled: _always,
      invoke: (a) => a.openKeyboardHelp(),
    ),
  ];
}
