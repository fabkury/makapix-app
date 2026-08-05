// Layer blend-mode metadata for the shell: engine tokens (the DSL/probe strings, wire order),
// picker grouping, display names, and the two-letter tile badges. Pure Dart — no engine, no
// Flutter — so tests cover it without the native binary.

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

/// Picker sections, the family grouping art apps use.
const List<(String, List<String>)> kBlendGroups = [
  ('Normal', ['Normal']),
  ('Darken', ['Multiply', 'Darken', 'Subtract']),
  ('Lighten', ['Screen', 'Lighten', 'Addition']),
  ('Contrast', ['Overlay', 'HardLight']),
  ('Compare', ['Difference', 'Exclusion']),
];

/// UI display name for an engine token.
String blendDisplayName(String token) => token == 'HardLight' ? 'Hard Light' : token;

/// Two-letter tile badge for a non-Normal mode; '' for Normal (no badge).
String blendBadge(String token) => switch (token) {
      'Multiply' => 'Mu',
      'Screen' => 'Sc',
      'Overlay' => 'Ov',
      'Darken' => 'Da',
      'Lighten' => 'Li',
      'Addition' => 'Ad',
      'Subtract' => 'Su',
      'Difference' => 'Di',
      'Exclusion' => 'Ex',
      'HardLight' => 'HL',
      _ => '',
    };
