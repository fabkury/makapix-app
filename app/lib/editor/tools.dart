// Editor tool catalog: the row-3 tool grid's DSL/icon/label definitions and the
// teach-as-you-go help text shown in the gesture-safe band. Pure data, no engine coupling.
import 'package:flutter/material.dart';

import 'makapix_icon.dart';

class ToolDef {
  final String dsl;
  final IconData? icon;   // Material glyph (tools without an approved custom icon yet)
  final MpxIcon? custom;  // approved Makapix custom icon (wins over [icon])
  final String label;
  const ToolDef(this.dsl, this.icon, this.label) : custom = null;
  const ToolDef.custom(this.dsl, this.custom, this.label) : icon = null;

  /// The tool's glyph at [size]; custom and Material icons render alike.
  Widget iconWidget({required double size, Color? color}) => custom != null
      ? MakapixIcon(custom!, size: size, color: color)
      : Icon(icon, size: size, color: color);
}

const tools = <ToolDef>[
  ToolDef.custom('Pencil', MpxIcons.pencil, 'Pencil'),
  ToolDef('Brush', Icons.brush, 'Brush'),
  ToolDef.custom('Airbrush', MpxIcons.airbrush, 'Airbrush'),
  ToolDef.custom('Eraser', MpxIcons.eraser, 'Eraser'),
  ToolDef.custom('Bucket', MpxIcons.fill, 'Fill'),
  // Outline (2026-09-04 rider of the Symmetry release): a UI-only action group like the
  // transforms — row-1 holds Side / Corners / Width and an Apply button, the canvas is inert.
  // Stock Material glyph until a generated painter is approved (tools/icons/).
  ToolDef('Outline', Icons.border_outer, 'Outline'),
  ToolDef('Gradient', Icons.gradient, 'Gradient'),
  ToolDef.custom('Line', MpxIcons.line, 'Line'),
  ToolDef('Shape', Icons.category_outlined, 'Shape'),
  ToolDef('Ruler', Icons.straighten, 'Ruler'),
  ToolDef('Dodge', Icons.light_mode, 'Dodge'),
  ToolDef('Burn', Icons.dark_mode, 'Burn'),
  ToolDef.custom('Eyedropper', MpxIcons.pick, 'Pick'),
  ToolDef('Move', Icons.open_with, 'Move'),
  ToolDef('CopyPaste', Icons.content_copy, 'Copy'),
  // Select Shape concentrates Rectangle/Ellipse/Lasso selection into one tool with a row-1 toggle
  // (like the Shape tool groups Ellipse/Triangle/Rectangle). Rect/Oval draft the selection before
  // committing it; Lasso selects freeform immediately on release (the engine's SelectFree tool).
  ToolDef.custom('SelectShape', MpxIcons.select, 'Select'),
  ToolDef.custom('SelectByColor', MpxIcons.selColor, 'Sel Color'),
  ToolDef.custom('SelectLayer', MpxIcons.selLyr, 'Sel Lyr'),
  ToolDef('HsvShift', Icons.palette, 'HSV'),
  ToolDef('BrightnessContrast', Icons.brightness_6, 'Bright'),
  ToolDef('Levels', Icons.tune, 'Levels'),
  // Transform actions: UI-only groups (no engine draw tool). Selecting one reveals its
  // action button(s) in row-1; the canvas is inert while one is selected.
  ToolDef.custom('Flip', MpxIcons.flip, 'Flip'),
  ToolDef('Rotate', Icons.rotate_90_degrees_cw, 'Rotate'),
  ToolDef('Resize', Icons.aspect_ratio, 'Resize'),
  ToolDef('Invert', Icons.invert_colors, 'Invert'),
  // Play: a selectable tool group (like the transform tools above). Selecting it reveals its
  // playback controls in row-1 (play/pause, prev/next frame, go to frame) and leaves the canvas
  // inert. Onion is an action toggle: tapping it lights up onion-skinning immediately.
  // (Undo/Redo are NOT here — they are pinned at the left of row-3, see _buildToolBar.)
  ToolDef('PlayPause', Icons.play_arrow, 'Play'),
  ToolDef.custom('Onion', MpxIcons.onion, 'Onion'),
];

// Undo/Redo are pinned (fixed, non-reorderable) at the left of row-3, so they're kept out of the
// reorderable `tools` list above but still need their icon/label here.
const undoToolDef = ToolDef('Undo', Icons.undo, 'Undo');
const redoToolDef = ToolDef('Redo', Icons.redo, 'Redo');
// The Redo tile's Repeat face (ADR 0017): shown when the redo stack is empty and the engine holds
// a repeatable op. Same dsl ('Redo') so the tile keeps its tap routing; only the face changes.
const repeatToolDef = ToolDef('Redo', Icons.repeat, 'Repeat');

/// Row-3 grid shape for [n] tiles. Tiles always flow row-major (left→right, top→bottom).
/// Portrait (`vertical: false`): the grid scrolls horizontally in `bands` rows (2, or 3 in
/// three-band mode) of up to `perBand` tiles each. Landscape (`vertical: true`): the transpose —
/// `perBand` tiles per row (2/3), `bands` rows scrolling vertically. Pure math, unit-tested.
({int bands, int perBand}) toolGridShape({required int n, required bool threeBands, required bool vertical}) {
  final k = threeBands ? 3 : 2;
  if (vertical) return (bands: (n + k - 1) ~/ k, perBand: k);
  return (bands: k, perBand: (n + k - 1) ~/ k);
}

/// The row-3 grid's order in *visible* space: [order] minus the user-hidden tools (ADR 0018) and
/// minus [pinned] (the 3-row toolbar's pinned 3rd-slot tool, which shows beside Undo/Redo instead;
/// pass null in 2-row mode). Both exclusions are display-time only — every tool keeps its slot in
/// the full order, so unhiding / unpinning puts it back exactly where it was.
List<String> visibleToolOrder(List<String> order, Set<String> hidden, {String? pinned}) =>
    order.where((d) => !hidden.contains(d) && d != pinned).toList();

/// Rebuild the full tool order after a reorder done in *visible* space (see [visibleToolOrder]):
/// every tool of [excluded] that was in [previousFull] is reinserted at its former index there,
/// in ascending index order (clamped), so a visible-space drag never churns the hidden slots and
/// removing-then-restoring is an exact round-trip. Tools of [excluded] absent from [previousFull]
/// are ignored; if none is present, [visible] is returned as-is.
List<String> restoreHiddenTools(List<String> visible, List<String> previousFull, Set<String> excluded) {
  final slots = [
    for (var i = 0; i < previousFull.length; i++)
      if (excluded.contains(previousFull[i])) (i, previousFull[i]),
  ];
  if (slots.isEmpty) return visible;
  final out = List<String>.of(visible)..removeWhere(excluded.contains);
  for (final (at, d) in slots) {
    out.insert(at.clamp(0, out.length), d);
  }
  return out;
}

/// The one-tool form of [restoreHiddenTools] (the 3-row toolbar's pinned tool before hidden tools
/// existed); kept as the readable name for that case.
List<String> restoreHiddenTool(List<String> visible, List<String> previousFull, String hidden) =>
    restoreHiddenTools(visible, previousFull, {hidden});

/// Reconcile a persisted hidden-tool set against the [catalog] (ADR 0018): unknown dsl names
/// (a tool removed from the catalog) are dropped, tools new to the catalog are visible by
/// construction, and a set that would leave nothing visible is discarded outright — the UI floor
/// is one visible tool, and only catalog drift or a damaged preference can breach it.
Set<String> reconcileHiddenTools(Iterable<String>? saved, List<String> catalog) {
  if (saved == null) return {};
  final out = {for (final d in saved) if (catalog.contains(d)) d};
  return out.length >= catalog.length ? <String>{} : out;
}

/// Whether one more tool may be hidden: the floor keeps at least one catalog tool visible.
bool canHideAnotherTool(Set<String> hidden, List<String> catalog) => hidden.length < catalog.length - 1;

/// The engine ToolKind for a Select-tool mode ('Rectangle' | 'Ellipse' | 'Lasso').
String selectShapeEngineTool(String kind) => switch (kind) {
      'Ellipse' => 'SelectEllipse',
      'Lasso' => 'SelectFree',
      _ => 'SelectRect',
    };

// Succinct, teach-as-you-go help shown in the gesture-safe band at the bottom. Keep each to two
// short lines: brief, professional, the core of the tool (not its nuances), no em dashes. Assume
// fluency with the draft/commit model: tips never teach or remind the user to Commit.
const toolTips = <String, String>{
  'Pencil': 'Drag to draw hard pixels in the primary color.',
  'Brush': 'Drag to paint, blending onto existing pixels.',
  'Airbrush': 'Drag to spray the primary color. Dots, Soft, and Mist lay different paint.',
  'Eraser': 'Drag to erase pixels to transparent.',
  'Bucket': 'Tap an area to flood-fill. Threshold sets color tolerance.',
  'Outline': 'Apply draws a ring around the layer\'s pixels in the primary color. Side, Corners and Width shape it.',
  'Gradient': 'Drag to set the gradient fill.',
  'Line': 'Drag to place a line.',
  'Shape': 'Drag to place a shape (Ellipse / Triangle / Rectangle toggle).',
  'Ruler': 'Drag to measure a line. Angle mode shows the angle at the shared point.',
  'Dodge': 'Drag to lighten pixels. Set intensity.',
  'Burn': 'Drag to darken pixels. Set intensity.',
  'Eyedropper': 'Tap a pixel to pick its color as primary. Drag to keep picking as you move.',
  'Move': 'Drag to move the selected pixels, or the whole layer if nothing is selected. Slow gears the drag for exact placement.',
  'CopyPaste': 'Clipboard for the selection: Copy, Cut, Paste, Clear. Paste drops a movable draft you position.',
  'SelectShape': 'Rect / Oval: drag to draft a selection and adjust the reticles. Lasso: draw freely around pixels.',
  'SelectCircle': 'Drag from the center to select a circle.',
  'SelectPoly': 'Trace an outline to select an area.',
  'SelectByColor': 'Tap to select similar colors. Threshold sets tolerance.',
  'SelectLayer': 'Turn the layer\'s opaque pixels into a selection. Tap a mode to apply.',
  'HsvShift': 'Shift hue, saturation and value.',
  'BrightnessContrast': 'Adjust brightness and contrast.',
  'Levels': 'Drag the black, gamma and white thumbs to remap tones.',
  'Flip': 'Mirror the layer horizontally or vertically. Acts on the selection if any.',
  'Rotate': 'Rotate the layer or frame 90°, 180°, or by a free Angle. (Whole canvas: ☰ menu.)',
  'Resize': 'Scale the layer or frame: ½×, 2×, or drag a free Scale. (Whole canvas: ☰ menu.)',
  'Invert': 'Invert the image colors.',
  'PlayPause': 'Play or pause the animation. Step to the previous or next frame, or jump to one.',
};
