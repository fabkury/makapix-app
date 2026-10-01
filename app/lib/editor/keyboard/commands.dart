// The keyboard Command catalog (CONTEXT.md "Command"; DESIGN.md §3): pure data over the
// EditorAccess host. Ids are a persistent contract (ADR 0009) — the 6.B bindings file keys user
// customizations by them, so renaming/splitting an id requires a store migration, never a silent
// drop. Registry ORDER is meaningful: when one Chord binds several Commands (Enter = commit or
// play), the dispatcher invokes the first whose `enabled` is true.
import 'package:makapix_club/l10n/l10n.dart';

import 'editor_access.dart';
import '../tools.dart';

/// The cheat sheet's sections, in the order it lists them.
enum CommandCategory {
  tools,
  edit,
  draft,
  playback,
  frames,
  layers,
  view,
  color,
  file,
  panels;

  String label(AppLocalizations l) => switch (this) {
        CommandCategory.tools => l.kbCatTools,
        CommandCategory.edit => l.kbCatEdit,
        CommandCategory.draft => l.kbCatDraft,
        CommandCategory.playback => l.kbCatPlayback,
        CommandCategory.frames => l.kbCatFrames,
        CommandCategory.layers => l.sectionLayers,
        CommandCategory.view => l.menuView,
        CommandCategory.color => l.kbCatColor,
        CommandCategory.file => l.menuFile,
        CommandCategory.panels => l.kbCatPanels,
      };
}

class CommandDef {
  final String id;

  /// The name of the Command in a given language (the cheat sheet asks per build, so a
  /// language change shows at once).
  final String Function(AppLocalizations l) labelOf;
  final CommandCategory category;
  /// Whether holding the key auto-repeats the Command (frame stepping, sizing, zooming).
  final bool repeats;
  final bool Function(EditorAccess a) enabled;
  final void Function(EditorAccess a) invoke;

  /// The name in the current language.
  String get label => labelOf(appL10n);

  const CommandDef({
    required this.id,
    required String Function(AppLocalizations l) label,
    required this.category,
    this.repeats = false,
    required this.enabled,
    required this.invoke,
  }) : labelOf = label;
}

bool _always(EditorAccess a) => true;

/// tools.dart dsl → command id. Every ToolDef must appear here (unit-tested), so a new tool
/// fails the suite until it declares its Command.
// l10n-ignore-start: tool ids and command ids
const toolCommandIds = <String, String>{
  'Pencil': 'tool.pencil',
  'Brush': 'tool.brush',
  'Airbrush': 'tool.airbrush',
  'Eraser': 'tool.eraser',
  'Bucket': 'tool.fill',
  'Outline': 'tool.outline',
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
// l10n-ignore-end

/// The full v1 catalog, in dispatch-priority order.
List<CommandDef> buildCommands() {
  return [
    // ---- Draft first: Enter/Esc belong to a pending draft before anything else ----
    CommandDef(
      id: 'draft.commit',
      label: (l) => l.cmdCommitDraft,
      category: CommandCategory.draft,
      enabled: (a) => a.hasAnyDraft,
      invoke: (a) => a.commitDraft(),
    ),
    CommandDef(
      id: 'draft.cancel',
      label: (l) => l.cmdCancelDraft,
      category: CommandCategory.draft,
      enabled: (a) => a.hasAnyDraft,
      invoke: (a) => a.cancelDraft(),
    ),
    // ---- Playback (shares Enter/Esc with the draft pair; loses while a draft is pending) ----
    CommandDef(
      id: 'playback.toggle',
      label: (l) => l.cmdPlayPause,
      category: CommandCategory.playback,
      enabled: (a) => a.frameCount > 1 && !a.hasAnyDraft,
      invoke: (a) => a.togglePlayback(),
    ),
    CommandDef(
      id: 'playback.stop',
      label: (l) => l.cmdStopPlayback,
      category: CommandCategory.playback,
      enabled: (a) => a.isPlaying && !a.hasAnyDraft,
      invoke: (a) => a.pausePlayback(),
    ),
    // ---- Edit ----
    CommandDef(
      id: 'edit.undo',
      label: (l) => l.toolUndo,
      category: CommandCategory.edit,
      repeats: true,
      enabled: (a) => a.canUndo,
      invoke: (a) => a.undo(),
    ),
    CommandDef(
      id: 'edit.redo',
      label: (l) => l.toolRedo,
      category: CommandCategory.edit,
      repeats: true,
      enabled: (a) => a.canRedo,
      invoke: (a) => a.redo(),
    ),
    CommandDef(
      id: 'edit.copy',
      label: (l) => l.cmdCopySelection,
      category: CommandCategory.edit,
      enabled: (a) => a.hasSelection,
      invoke: (a) => a.copySelection(),
    ),
    CommandDef(
      id: 'edit.paste',
      label: (l) => l.optPaste,
      category: CommandCategory.edit,
      enabled: _always,
      invoke: (a) => a.pasteFromKeyboard(),
    ),
    CommandDef(
      id: 'edit.selectAll',
      label: (l) => l.selectAll,
      category: CommandCategory.edit,
      enabled: _always,
      invoke: (a) => a.selectAll(),
    ),
    CommandDef(
      id: 'edit.deselect',
      label: (l) => l.cmdDeselect,
      category: CommandCategory.edit,
      enabled: (a) => a.hasSelection,
      invoke: (a) => a.deselect(),
    ),
    // ---- Tools (one Command per tools.dart entry; Onion is a toggle, the rest select) ----
    for (final t in tools)
      CommandDef(
        id: toolCommandIds[t.dsl]!,
        label: t.name,
        category: CommandCategory.tools,
        enabled: _always,
        invoke: (a) => t.dsl == 'Onion' ? a.toggleOnion() : a.selectTool(t.dsl),
      ),
    // ---- Frames ----
    CommandDef(
      id: 'frame.prev',
      label: (l) => l.optPrevFrame,
      category: CommandCategory.frames,
      repeats: true,
      enabled: (a) => a.frameCount > 1,
      invoke: (a) => a.stepFrame(-1),
    ),
    CommandDef(
      id: 'frame.next',
      label: (l) => l.optNextFrame,
      category: CommandCategory.frames,
      repeats: true,
      enabled: (a) => a.frameCount > 1,
      invoke: (a) => a.stepFrame(1),
    ),
    CommandDef(
      id: 'frame.add',
      label: (l) => l.editorAddFrame,
      category: CommandCategory.frames,
      enabled: _always,
      invoke: (a) => a.addFrame(),
    ),
    CommandDef(
      id: 'frame.duplicate',
      label: (l) => l.cmdDuplicateFrame,
      category: CommandCategory.frames,
      enabled: _always,
      invoke: (a) => a.duplicateFrame(),
    ),
    CommandDef(
      id: 'frame.delete',
      label: (l) => l.frameDelete,
      category: CommandCategory.frames,
      enabled: (a) => a.frameCount > 1,
      invoke: (a) => a.deleteFrame(),
    ),
    // ---- Layers ----
    CommandDef(
      id: 'layer.up',
      label: (l) => l.cmdLayerUp,
      category: CommandCategory.layers,
      enabled: (a) => a.activeLayer + 1 < a.layerCount,
      invoke: (a) => a.moveLayer(1),
    ),
    CommandDef(
      id: 'layer.down',
      label: (l) => l.cmdLayerDown,
      category: CommandCategory.layers,
      enabled: (a) => a.activeLayer > 0,
      invoke: (a) => a.moveLayer(-1),
    ),
    CommandDef(
      id: 'layer.add',
      label: (l) => l.editorAddLayer,
      category: CommandCategory.layers,
      enabled: _always,
      invoke: (a) => a.addLayer(),
    ),
    // ---- View ----
    CommandDef(
      id: 'view.zoomIn',
      label: (l) => l.zoomIn,
      category: CommandCategory.view,
      repeats: true,
      enabled: _always,
      invoke: (a) => a.zoomIn(),
    ),
    CommandDef(
      id: 'view.zoomOut',
      label: (l) => l.zoomOut,
      category: CommandCategory.view,
      repeats: true,
      enabled: _always,
      invoke: (a) => a.zoomOut(),
    ),
    CommandDef(
      id: 'view.zoomFit',
      label: (l) => l.viewFit,
      category: CommandCategory.view,
      enabled: _always,
      invoke: (a) => a.zoomFit(),
    ),
    CommandDef(
      id: 'view.zoom100',
      label: (l) => l.cmdActualPixels,
      category: CommandCategory.view,
      enabled: _always,
      invoke: (a) => a.zoom100(),
    ),
    // ---- Symmetry (ADR 0026): cycles Off → H → V → Both like the row-1 Mirror chip ----
    CommandDef(
      id: 'symmetry.cycle',
      label: (l) => l.cmdMirrorCycle,
      category: CommandCategory.tools,
      enabled: _always,
      invoke: (a) => a.cycleSymmetry(),
    ),
    // ---- Color / brush ----
    CommandDef(
      id: 'color.swap',
      label: (l) => l.cmdSwapColor,
      category: CommandCategory.color,
      enabled: _always,
      invoke: (a) => a.swapWithPreviousColor(),
    ),
    CommandDef(
      id: 'brush.sizeUp',
      label: (l) => l.cmdBrushUp,
      category: CommandCategory.color,
      repeats: true,
      enabled: (a) => a.brushSizeApplies,
      invoke: (a) => a.brushSizeBy(1),
    ),
    CommandDef(
      id: 'brush.sizeDown',
      label: (l) => l.cmdBrushDown,
      category: CommandCategory.color,
      repeats: true,
      enabled: (a) => a.brushSizeApplies,
      invoke: (a) => a.brushSizeBy(-1),
    ),
    // ---- File / panels ----
    CommandDef(
      id: 'doc.save',
      label: (l) => l.commonSave,
      category: CommandCategory.file,
      enabled: _always,
      invoke: (a) => a.save(),
    ),
    CommandDef(
      id: 'doc.export',
      label: (l) => l.menuImportExport,
      category: CommandCategory.file,
      enabled: _always,
      invoke: (a) => a.openExportMenu(),
    ),
    CommandDef(
      id: 'sheet.timeline',
      label: (l) => l.cmdFrameOptions,
      category: CommandCategory.panels,
      enabled: _always,
      invoke: (a) => a.openFrameSheet(),
    ),
    CommandDef(
      id: 'page.frames',
      label: (l) => l.cmdFramesPage,
      category: CommandCategory.panels,
      enabled: _always,
      invoke: (a) => a.openFramesPage(),
    ),
    CommandDef(
      id: 'page.layers',
      label: (l) => l.cmdLayersPage,
      category: CommandCategory.panels,
      enabled: _always,
      invoke: (a) => a.openLayersPage(),
    ),
    CommandDef(
      id: 'sheet.layers',
      label: (l) => l.cmdLayerOptions,
      category: CommandCategory.panels,
      enabled: _always,
      invoke: (a) => a.openLayerSheet(),
    ),
    CommandDef(
      id: 'help.keyboard',
      label: (l) => l.cmdKeyboardShortcuts,
      category: CommandCategory.panels,
      enabled: _always,
      invoke: (a) => a.openKeyboardHelp(),
    ),
  ];
}
