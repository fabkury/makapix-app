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
  ToolDef('Rectangle', Icons.crop_square, 'Rect'),
  ToolDef('Ellipse', Icons.circle_outlined, 'Ellipse'),
  ToolDef('Ruler', Icons.straighten, 'Ruler'),
  ToolDef('Dodge', Icons.light_mode, 'Dodge'),
  ToolDef('Burn', Icons.dark_mode, 'Burn'),
  ToolDef('Eyedropper', Icons.colorize, 'Pick'),
  ToolDef('Move', Icons.open_with, 'Move'),
  ToolDef('SelectRect', Icons.highlight_alt, 'Sel Rect'),
  ToolDef('SelectEllipse', Icons.lens_blur, 'Sel Oval'),
  ToolDef('SelectFree', Icons.gesture, 'Lasso'),
  ToolDef('SelectByColor', Icons.colorize_outlined, 'Sel Color'),
  ToolDef('SelectLayer', Icons.opacity, 'Sel Lyr'),
  ToolDef('HsvShift', Icons.palette, 'HSV'),
  // Transform actions: UI-only groups (no engine draw tool). Selecting one reveals its
  // action button(s) in row-1; the canvas is inert while one is selected.
  ToolDef('Flip', Icons.flip, 'Flip'),
  ToolDef('Rotate', Icons.rotate_90_degrees_cw, 'Rotate'),
  ToolDef('Invert', Icons.invert_colors, 'Invert'),
  ToolDef('Resize', Icons.aspect_ratio, 'Resize'),
  // Action tools: tapping performs an action (or toggles) immediately instead of selecting a
  // draw tool. Play/Pause swaps icon+label with playback; Onion lights up while on.
  // (Undo/Redo are NOT here — they are pinned at the left of row-3, see _buildToolBar.)
  ToolDef('PlayPause', Icons.play_arrow, 'Play'),
  ToolDef('Onion', Icons.layers, 'Onion'),
];

// Undo/Redo are pinned (fixed, non-reorderable) at the left of row-3, so they're kept out of the
// reorderable `tools` list above but still need their icon/label here.
const undoToolDef = ToolDef('Undo', Icons.undo, 'Undo');
const redoToolDef = ToolDef('Redo', Icons.redo, 'Redo');

// Succinct, teach-as-you-go help shown in the gesture-safe band at the bottom.
const toolTips = <String, String>{
  'Pencil': 'Drag to draw hard pixels in the primary colour. Turn on Precision to draw off-finger with a reticle.',
  'Brush': 'Drag to paint, blending onto existing pixels. Spacing (% of size) sets how far apart stamps land. Turn on Precision to paint off-finger with a reticle.',
  'Airbrush': 'Drag to spray in the primary colour. Set size, intensity & spacing. Turn on Precision to aim a reticle off-finger; tap SPRAY for one burst, or turn PEN on and drag.',
  'Eraser': 'Drag to erase pixels to transparent. Turn on Precision to erase off-finger with a reticle.',
  'Bucket': 'Tap an area to flood-fill. Threshold = colour tolerance.',
  'Gradient': 'Drag start→end to fill a gradient. Pick 2–3 colours, Linear/Radial.',
  'Line': 'Drag to preview a line, then drag the end handles to fine-tune. Press Commit to draw, Cancel to discard.',
  'Rectangle': 'Drag to preview a rectangle, then drag the corner handles to fine-tune. Toggle Fill / Outline (set Width for outlines). Commit to draw.',
  'Ellipse': 'Drag to preview an ellipse, then drag the handles to fine-tune. Toggle Fill / Outline (set Width for outlines). Commit to draw.',
  'Ruler': 'Drag to measure — shows each end\'s X,Y and the length in pixels. Drag a reticle to fine-tune an end (tapping elsewhere does nothing). Nothing is drawn; it clears when you switch tools.',
  'Dodge': 'Drag over pixels to lighten them. Set intensity.',
  'Burn': 'Drag over pixels to darken them. Set intensity.',
  'Eyedropper': 'Tap a pixel to pick its colour as primary.',
  'Move': 'Drag to move: the selected pixels if there\'s a selection, otherwise the whole layer (or move-group). Arrows nudge 1px. For layer moves: Protect keeps pixels on-canvas, Wrap wraps them around the edges, both off loses off-canvas pixels.',
  'SelectRect': 'Drag to select a rectangle. Use Add/Subtract/Intersect modes.',
  'SelectEllipse': 'Drag to select an ellipse. Combine with Add/Subtract modes.',
  'SelectCircle': 'Drag from centre outward to select a circle.',
  'SelectPoly': 'Trace an outline; it closes into a selection on release.',
  'SelectFree': 'Lasso: trace around pixels to select them.',
  'SelectByColor': 'Tap to select similar-colour pixels. Threshold = tolerance.',
  'SelectLayer': 'Selects the layer\'s opaque pixels (cyan = pixels with alpha > Threshold; 0 = all non-transparent). Tap Replace/Add/Subtract/Intersect to apply; All/None select everything/nothing.',
  'HsvShift': 'Shift Hue/Sat/Value of the selection. Set H/S/V, then Apply.',
  'Flip': 'Mirror the image — tap Flip H or Flip V.',
  'Rotate': 'Rotate the canvas 90° CW, 90° CCW, or 180°.',
  'Invert': 'Invert the colours of the image (or selection).',
  'Resize': 'Change the canvas dimensions.',
};
