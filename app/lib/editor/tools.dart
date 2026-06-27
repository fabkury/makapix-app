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
  ToolDef('PrecisionPencil', Icons.gps_fixed, 'Precision'),
  ToolDef('Brush', Icons.brush, 'Brush'),
  ToolDef('Airbrush', Icons.blur_on, 'Airbrush'),
  ToolDef('Eraser', Icons.auto_fix_normal, 'Eraser'),
  ToolDef('Bucket', Icons.format_color_fill, 'Fill'),
  ToolDef('Gradient', Icons.gradient, 'Gradient'),
  ToolDef('Line', Icons.show_chart, 'Line'),
  ToolDef('Rectangle', Icons.crop_square, 'Rect'),
  ToolDef('Ellipse', Icons.circle_outlined, 'Ellipse'),
  ToolDef('Dodge', Icons.light_mode, 'Dodge'),
  ToolDef('Burn', Icons.dark_mode, 'Burn'),
  ToolDef('Eyedropper', Icons.colorize, 'Pick'),
  ToolDef('Move', Icons.open_with, 'Move'),
  ToolDef('MoveLayer', Icons.control_camera, 'Move Lyr'),
  ToolDef('SelectRect', Icons.highlight_alt, 'Sel Rect'),
  ToolDef('SelectEllipse', Icons.lens_blur, 'Sel Oval'),
  ToolDef('SelectFree', Icons.gesture, 'Lasso'),
  ToolDef('SelectByColor', Icons.colorize_outlined, 'Sel Color'),
  ToolDef('HsvShift', Icons.palette, 'HSV'),
  // Transform actions: UI-only groups (no engine draw tool). Selecting one reveals its
  // action button(s) in row-1; the canvas is inert while one is selected.
  ToolDef('Flip', Icons.flip, 'Flip'),
  ToolDef('Rotate', Icons.rotate_90_degrees_cw, 'Rotate'),
  ToolDef('Invert', Icons.invert_colors, 'Invert'),
  ToolDef('Resize', Icons.aspect_ratio, 'Resize'),
];

// Succinct, teach-as-you-go help shown in the gesture-safe band at the bottom.
const toolTips = <String, String>{
  'Pencil': 'Drag to draw hard pixels in the primary colour.',
  'PrecisionPencil':
      'Drag to move the ✛ reticle off your finger; arrows nudge 1px. Tap DRAW for a dot, or turn PEN on and drag to draw a line.',
  'Brush': 'Drag to paint, blending onto existing pixels.',
  'Airbrush': 'Drag to aim the ◎ reticle off your finger; tap SPRAY for one burst. Set size & intensity.',
  'Eraser': 'Drag to erase pixels to transparent.',
  'Bucket': 'Tap an area to flood-fill. Threshold = colour tolerance.',
  'Gradient': 'Drag start→end to fill a gradient. Pick 2–3 colours, Linear/Radial.',
  'Line': 'Drag from one point to another to draw a straight line.',
  'Rectangle': 'Drag corner-to-corner. Toggle Fill / Outline.',
  'Ellipse': 'Drag to bound an ellipse. Toggle Fill / Outline.',
  'Dodge': 'Drag over pixels to lighten them. Set intensity.',
  'Burn': 'Drag over pixels to darken them. Set intensity.',
  'Eyedropper': 'Tap a pixel to pick its colour as primary.',
  'Move': 'Select first, then drag the selected pixels to move them.',
  'MoveLayer': 'Drag the canvas to move the active layer (or the move-group); arrows nudge 1px. Group layers via a layer\'s long-press menu.',
  'SelectRect': 'Drag to select a rectangle. Use Add/Subtract/Intersect modes.',
  'SelectEllipse': 'Drag to select an ellipse. Combine with Add/Subtract modes.',
  'SelectCircle': 'Drag from centre outward to select a circle.',
  'SelectPoly': 'Trace an outline; it closes into a selection on release.',
  'SelectFree': 'Lasso: trace around pixels to select them.',
  'SelectByColor': 'Tap to select similar-colour pixels. Threshold = tolerance.',
  'HsvShift': 'Shift Hue/Sat/Value of the selection. Set H/S/V, then Apply.',
  'Flip': 'Mirror the image — tap Flip H or Flip V.',
  'Rotate': 'Rotate the canvas 90° CW, 90° CCW, or 180°.',
  'Invert': 'Invert the colours of the image (or selection).',
  'Resize': 'Change the canvas dimensions.',
};
