// Layer blend-mode metadata for the shell: engine tokens (the DSL/probe strings, wire order)
// and the picker grouping. Pure Dart — no engine, no Flutter — so tests cover it without the
// native binary. What the modes are called on screen is in blend_l10n.dart.
// l10n-ignore-file: engine tokens and group keys, never shown as they are

/// Engine blend tokens in wire order (crates/engine `BlendMode::name()`).
const List<String> kBlendModes = [
  'Normal',
  'Multiply',
  'Screen',
  'Overlay',
  'Darken',
  'Lighten',
  'Addition',
  'Subtract',
  'Difference',
  'Exclusion',
  'HardLight',
];

/// Picker sections, the family grouping art apps use. The first item is a key
/// (`blendGroupName` gives the heading), not text.
const List<(String, List<String>)> kBlendGroups = [
  ('Normal', ['Normal']),
  ('Darken', ['Multiply', 'Darken', 'Subtract']),
  ('Lighten', ['Screen', 'Lighten', 'Addition']),
  ('Contrast', ['Overlay', 'HardLight']),
  ('Compare', ['Difference', 'Exclusion']),
];
