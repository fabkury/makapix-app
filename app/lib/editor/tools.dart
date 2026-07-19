// Editor tool catalogue: the row-3 tool grid's DSL/icon/label definitions and the
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
  ToolDef('Gradient', Icons.gradient, 'Gradient'),
  ToolDef.custom('Line', MpxIcons.line, 'Line'),
  ToolDef('Shape', Icons.category_outlined, 'Shape'),
  ToolDef('Ruler', Icons.straighten, 'Ruler'),
  ToolDef('Dodge', Icons.light_mode, 'Dodge'),
  ToolDef('Burn', Icons.dark_mode, 'Burn'),
  ToolDef.custom('Eyedropper', MpxIcons.pick, 'Pick'),
  ToolDef('Move', Icons.open_with, 'Move'),
  ToolDef('CopyPaste', Icons.content_copy, 'Copy'),
  // Select Shape concentrates Rectangle/Ellipse selection into one tool with a row-1 toggle (like the
  // Shape tool groups Ellipse/Triangle/Rectangle); it drafts the selection before committing it.
  ToolDef.custom('SelectShape', MpxIcons.select, 'Select'),
  ToolDef.custom('SelectFree', MpxIcons.lasso, 'Lasso'),
  ToolDef.custom('SelectByColor', MpxIcons.selColor, 'Sel Color'),
  ToolDef.custom('SelectLayer', MpxIcons.selLyr, 'Sel Lyr'),
  ToolDef('HsvShift', Icons.palette, 'HSV'),
  ToolDef('BrightnessContrast', Icons.brightness_6, 'Bright'),
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

/// Rebuild the full tool order after a reorder done in *visible* space (the grid with [hidden]
/// filtered out, as in the 3-row toolbar where Play is pinned): [hidden] is reinserted at its
/// index in [previousFull], clamped, so toggling the toolbar mode never churns the saved order.
/// If [hidden] wasn't in [previousFull], [visible] is returned as-is (the 2-row path).
/// Row-3 grid shape for [n] tiles. Tiles always flow row-major (left→right, top→bottom).
/// Portrait (`vertical: false`): the grid scrolls horizontally in `bands` rows (2, or 3 in
/// three-band mode) of up to `perBand` tiles each. Landscape (`vertical: true`): the transpose —
/// `perBand` tiles per row (2/3), `bands` rows scrolling vertically. Pure math, unit-tested.
({int bands, int perBand}) toolGridShape({required int n, required bool threeBands, required bool vertical}) {
  final k = threeBands ? 3 : 2;
  if (vertical) return (bands: (n + k - 1) ~/ k, perBand: k);
  return (bands: k, perBand: (n + k - 1) ~/ k);
}

List<String> restoreHiddenTool(List<String> visible, List<String> previousFull, String hidden) {
  final at = previousFull.indexOf(hidden);
  if (at < 0) return visible;
  final out = List<String>.of(visible)..remove(hidden);
  out.insert(at.clamp(0, out.length), hidden);
  return out;
}

// Succinct, teach-as-you-go help shown in the gesture-safe band at the bottom. Keep each to two
// short lines: brief, professional, the core of the tool (not its nuances), no em dashes.
const toolTips = <String, String>{
  'Pencil': 'Drag to draw hard pixels in the primary colour.',
  'Brush': 'Drag to paint, blending onto existing pixels.',
  'Airbrush': 'Drag to spray the primary colour. Set size and intensity.',
  'Eraser': 'Drag to erase pixels to transparent.',
  'Bucket': 'Tap an area to flood-fill. Threshold sets colour tolerance.',
  'Gradient': 'Drag to set a gradient, then Commit to fill.',
  'Line': 'Drag to set a line, then Commit to draw.',
  'Shape': 'Drag to set a shape (Ellipse / Triangle / Rectangle toggle), then Commit to draw.',
  'Ruler': 'Drag to measure a line. Angle mode shows the angle at the shared point.',
  'Dodge': 'Drag to lighten pixels. Set intensity.',
  'Burn': 'Drag to darken pixels. Set intensity.',
  'Eyedropper': 'Tap a pixel to pick its colour as primary.',
  'Move': 'Drag to move the selected pixels, or the whole layer if nothing is selected.',
  'CopyPaste': 'Clipboard for the selection: Copy, Cut, Paste, Clear. Paste drops a movable draft you position, then Commit.',
  'SelectShape': 'Drag to draft a rectangular or elliptical selection. Drag the reticles to adjust, then Commit.',
  'SelectCircle': 'Drag from the centre to select a circle.',
  'SelectPoly': 'Trace an outline to select an area.',
  'SelectFree': 'Lasso freely around pixels to select them.',
  'SelectByColor': 'Tap to select similar colours. Threshold sets tolerance.',
  'SelectLayer': 'Turn the layer\'s opaque pixels into a selection. Tap a mode to apply.',
  'HsvShift': 'Shift hue, saturation and value, then Commit.',
  'BrightnessContrast': 'Adjust brightness and contrast, then Commit.',
  'Flip': 'Mirror the layer horizontally or vertically. Acts on the selection if any.',
  'Rotate': 'Rotate the layer or the whole frame 90°, 180°, or by a free Angle. cleanEdge keeps slanted edges clean. Acts on the selection if any. (Whole canvas: ☰ menu.)',
  'Resize': 'Scale the layer or frame: ½×, 2×, or drag a free Scale. cleanEdge keeps upscaled edges clean. Acts on the selection if any.',
  'Invert': 'Invert the image colours.',
  'PlayPause': 'Play or pause the animation. Step to the previous or next frame, or jump to one.',
};
