// Editor tool catalogue: the row-3 tool grid's DSL/icon/label definitions and the
// teach-as-you-go help text shown in the gesture-safe band. Pure data, no engine coupling.
import 'package:flutter/material.dart';

class ToolDef {
  final String dsl;
  final IconData icon;
  final String label;
  const ToolDef(this.dsl, this.icon, this.label);
}

const tools = <ToolDef>[
  ToolDef('Pencil', Icons.edit, 'Pencil'),
  ToolDef('Brush', Icons.brush, 'Brush'),
  ToolDef('Airbrush', Icons.blur_on, 'Airbrush'),
  ToolDef('Eraser', Icons.auto_fix_normal, 'Eraser'),
  ToolDef('Bucket', Icons.format_color_fill, 'Fill'),
  ToolDef('Gradient', Icons.gradient, 'Gradient'),
  ToolDef('Line', Icons.show_chart, 'Line'),
  ToolDef('Shape', Icons.category_outlined, 'Shape'),
  ToolDef('Ruler', Icons.straighten, 'Ruler'),
  ToolDef('Dodge', Icons.light_mode, 'Dodge'),
  ToolDef('Burn', Icons.dark_mode, 'Burn'),
  ToolDef('Eyedropper', Icons.colorize, 'Pick'),
  ToolDef('Move', Icons.open_with, 'Move'),
  ToolDef('CopyPaste', Icons.content_copy, 'Copy'),
  // Select Shape concentrates Rectangle/Ellipse selection into one tool with a row-1 toggle (like the
  // Shape tool groups Ellipse/Triangle/Rectangle); it drafts the selection before committing it.
  ToolDef('SelectShape', Icons.highlight_alt, 'Select'),
  ToolDef('SelectFree', Icons.gesture, 'Lasso'),
  ToolDef('SelectByColor', Icons.colorize_outlined, 'Sel Color'),
  ToolDef('SelectLayer', Icons.opacity, 'Sel Lyr'),
  ToolDef('HsvShift', Icons.palette, 'HSV'),
  // Transform actions: UI-only groups (no engine draw tool). Selecting one reveals its
  // action button(s) in row-1; the canvas is inert while one is selected.
  ToolDef('Flip', Icons.flip, 'Flip'),
  ToolDef('Rotate', Icons.rotate_90_degrees_cw, 'Rotate'),
  ToolDef('Invert', Icons.invert_colors, 'Invert'),
  // Play: a selectable tool group (like the transform tools above). Selecting it reveals its
  // playback controls in row-1 (play/pause, prev/next frame, go to frame) and leaves the canvas
  // inert. Onion is an action toggle: tapping it lights up onion-skinning immediately.
  // (Undo/Redo are NOT here — they are pinned at the left of row-3, see _buildToolBar.)
  ToolDef('PlayPause', Icons.play_arrow, 'Play'),
  ToolDef('Onion', Icons.layers, 'Onion'),
];

// Undo/Redo are pinned (fixed, non-reorderable) at the left of row-3, so they're kept out of the
// reorderable `tools` list above but still need their icon/label here.
const undoToolDef = ToolDef('Undo', Icons.undo, 'Undo');
const redoToolDef = ToolDef('Redo', Icons.redo, 'Redo');

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
  'Ruler': 'Drag to measure a line. Shows each end and its length in pixels.',
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
  'HsvShift': 'Shift the selection\'s hue, saturation and value, then Apply.',
  'Flip': 'Mirror the layer horizontally or vertically. Acts on the selection if any.',
  'Rotate': 'Rotate the layer 90° or 180°, or by a free Angle. Acts on the selection if any. (Whole canvas: ☰ menu.)',
  'Invert': 'Invert the image colours.',
  'PlayPause': 'Play or pause the animation. Step to the previous or next frame, or jump to one.',
};
