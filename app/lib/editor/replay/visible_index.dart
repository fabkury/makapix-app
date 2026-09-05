/// The visible-change index — pure, no engine (the Replay tick semantics).
///
/// A replay position p is VISIBLE when the transition from p−1 to p can change what the
/// viewer shows (the composited canvas of the artist's active frame). Draft fiddling,
/// settings churn, cursor moves, selection-mask edits, palette work, and playback-preview
/// ticks are not visible; strokes, commits, applies, undo/redo, structural edits, frame
/// hops (the viewer follows the artist), and chapter-base loads are.
///
/// This is a HEURISTIC verb triage, deliberately biased safe: an unknown or ambiguous verb
/// counts as visible (a rare dead tick is harmless; a skipped real change is not). The
/// empirically dangerous direction — classifying a change-producing verb invisible — is
/// validated against composite hashes in the offline oracle harness.
library;

import 'journal_format.dart';

/// Verbs that can always change the followed composite (or what the viewer points at).
const Set<String> _kAlwaysVisible = {
  // Document / frame structure (the viewer follows the artist's active frame).
  'NewDocument', 'AddFrame', 'AddFrameAt', 'DuplicateFrame', 'RemoveFrame', 'ReorderFrame',
  'SetActiveFrame',
  // Layer structure & properties that composite.
  'RemoveLayer', 'DuplicateLayer', 'DuplicateLayerToFrames', 'MergeDown', 'ReorderLayer',
  'SetLayerOpacity', 'SetLayerVisible', 'SetLayerBlend', 'PreviewLayerBlend',
  'NudgeLayers', 'NudgeMove',
  // Whole-canvas / frame / layer transforms.
  'FlipCanvasH', 'FlipCanvasV', 'FlipFrameH', 'FlipFrameV', 'FlipH', 'FlipV',
  'Invert', 'InvertFrame', 'ResizeCanvas', 'CropToSelection',
  'Rotate', 'RotateFrame', 'RotateLayer', 'ScaleFrame', 'ScaleLayer',
  // Draft commits + adjustment applies (the moment pixels land).
  'ShapeCommit', 'PasteCommit', 'MoveDraftCommit', 'RotateDraftCommit', 'ScaleDraftCommit',
  'ApplyHsvShift', 'ApplyBrightnessContrast', 'ApplyLevels',
  // Clipboard / selected-pixel operations.
  'Cut', 'Paste', 'PasteToFrame', 'FillSelection', 'ClearSelection',
  // History.
  'Undo', 'Redo',
  // Direct painting verbs.
  'FillNoise', 'PlotCursor', 'AirbrushCursor', 'FillCursor',
  // Aborting a stroke restores pre-stroke pixels (visible when anything was painted).
  'CancelStroke',
  // The precision pen stamps its first pixel on pen-down.
  'CursorPenDown',
};

/// Engine tools whose pointer contact paints immediately (down + every move visible).
const Set<String> _kStampTools = {
  'Pencil', 'Brush', 'Airbrush', 'AirbrushSoft', 'AirbrushMist', 'Eraser', 'Bucket', 'Dodge', 'Burn', 'Move',
};

/// Engine tools that rasterize on pointer-UP (the direct-gesture path scripts use).
const Set<String> _kUpTools = {'Line', 'Rectangle', 'Ellipse', 'Triangle', 'Gradient', 'Move'};

String _resolveTool(String name) => switch (name) {
      'PrecisionPencil' => 'Pencil', // the parser's legacy aliases
      'MoveLayer' => 'Move',
      _ => name,
    };

/// Ascending positions in `1..actions.length` whose transition is visible, per the triage
/// above, plus every chapter-boundary position (a base load pops content in). Never empty
/// when the journal has actions: the final position is always included so the slider can
/// reach the finished state even if the tail is settings churn.
List<int> visiblePositions(FlatJournal flat) {
  final out = <int>[];
  var tool = 'Pencil'; // Session::new's default
  var penHeld = false;
  for (var i = 0; i < flat.actions.length; i++) {
    var visible = flat.chapterBaseAt.containsKey(i) && i > 0; // the base-load pop
    for (final raw in flat.actions[i].split(';')) {
      final stmt = raw.trim();
      if (stmt.isEmpty || stmt.startsWith('#') || stmt.startsWith('//')) continue;
      final paren = stmt.indexOf('(');
      final verb = paren <= 0 ? stmt : stmt.substring(0, paren);
      visible = visible || _statementVisible(verb, tool, penHeld);
      // State tracking AFTER classification (the statement acts with the prior state).
      switch (verb) {
        case 'SelectTool':
          final inner = paren <= 0 ? '' : stmt.substring(paren + 1, stmt.lastIndexOf(')'));
          tool = _resolveTool(inner.trim());
        case 'CursorPenDown':
          penHeld = true;
        case 'CursorPenUp':
          penHeld = false;
        case 'NewDocument':
          tool = 'Pencil'; // the whole-session reset restores defaults
          penHeld = false;
      }
    }
    if (visible) out.add(i + 1);
  }
  if (out.isEmpty || out.last != flat.actions.length) {
    if (flat.actions.isNotEmpty) out.add(flat.actions.length);
  }
  return out;
}

bool _statementVisible(String verb, String tool, bool penHeld) {
  if (_kAlwaysVisible.contains(verb)) return true;
  switch (verb) {
    case 'PointerDown' || 'PointerMove':
      return _kStampTools.contains(tool);
    case 'PointerUp':
      return _kUpTools.contains(tool);
    case 'Tap':
      return _kStampTools.contains(tool) || _kUpTools.contains(tool);
    case 'Stroke':
      return _kStampTools.contains(tool) || _kUpTools.contains(tool);
    case 'MoveCursor':
      return penHeld; // the precision pen paints while held
  }
  // Known-invisible families: every Set*, SelectTool, selection-mask ops, draft
  // lifecycle non-commits, palette work, Copy, cursor bracketing, clock/playback,
  // ClearHistory, renames/locks/durations. Everything unknown defaults VISIBLE.
  const invisible = {
    'SelectTool', 'SetCursor',
    'SelectAll', 'SelectNone', 'InvertSelection', 'SelectByAlpha',
    'MoveSelection', 'MoveSelectionBegin', 'MoveSelectionCommit',
    'ShapeSet', 'ShapeCancel',
    'PasteDraft', 'PasteMove', 'PasteCancel', 'Copy',
    'MoveDraftBegin', 'MoveDraftMove', 'MoveDraftCancel',
    'RotateDraftBegin', 'RotateDraftBeginFrame', 'RotateDraftSetAngle', 'RotateDraftMove',
    'RotateDraftCancel',
    'ScaleDraftBegin', 'ScaleDraftBeginFrame', 'ScaleDraftSet', 'ScaleDraftMove',
    'ScaleDraftCancel',
    'CursorPenUp', 'CursorStrokeBegin', 'CursorStrokeEnd',
    'EyedropCursor', 'SelectColorCursor',
    'AdvanceClock', 'Play', 'Pause', 'ClearHistory',
    'RenameLayer', 'SetLayerLocked', 'SetActiveLayer', 'SetActiveLayers', 'SetMoveGroup',
    'SetFrameDuration', 'SetAllDurations', 'SetLoopMode',
    'NewPalette', 'DeletePalette', 'DuplicatePalette', 'RenamePalette', 'RenamePaletteAt',
    'MovePalette', 'SetActivePalette', 'AddPaletteColor', 'RemovePaletteColor',
    'EditPaletteColor', 'DuplicatePaletteColor', 'SwapPaletteColors', 'SortPalette',
    'SortPaletteAt', 'ClearPalette', 'ClearPaletteAt', 'NamePaletteColor',
    // The settings family — enumerated (not a Set* catch-all) so a FUTURE visible Set
    // verb still gets the safe default below.
    'SetAA', 'SetAlphaCutoff', 'SetBcScope', 'SetBrightnessContrast', 'SetBrushShape', 'SetBrushSize',
    'SetCleanEdge', 'SetCleanEdgeWidth', 'SetContiguous', 'SetEyedropSource',
    'SetFillAllLayers', 'SetGradientDither', 'SetGradientSmoothstep', 'SetGradientStops', 'SetGradientType',
    'SetHsvScope', 'SetHsvShift', 'SetIntensity', 'SetLevels', 'SetLevelsScope',
    'SetLineWidth', 'SetMemBudget', 'SetOverscanView', 'SetPattern', 'SetPixelPerfect', 'SetPrimaryColor',
    'SetProtectPixels', 'SetScaleCleanEdge', 'SetScaleCleanEdgeWidth', 'SetSecondaryColor',
    'SetSeed', 'SetSelectColorSource', 'SetSelectionMode', 'SetShapeFill', 'SetSymmetry',
    'SetShapeRotation', 'SetSpacing', 'SetThreshold', 'SetTriangleTip', 'SetWrap',
  };
  if (invisible.contains(verb)) return false;
  return true; // unknown → visible: a dead tick beats a skipped change
}
