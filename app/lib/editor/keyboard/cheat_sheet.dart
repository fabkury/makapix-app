// The keyboard discoverability surface (DESIGN.md §2.5): ONE registry-driven widget rendered
// two ways — the hold-Primary overlay (the in-app replacement for the iPadOS hold-⌘ HUD, which
// Flutter apps never appear in) and the ☰ → Keyboard page. Pure presentation over the registry
// and Binding table; engine-free.
import 'package:flutter/material.dart';

import 'commands.dart';
import 'default_bindings.dart';

const _categoryOrder = [
  'Tools', 'Edit', 'Draft', 'Playback', 'Frames', 'Layers', 'View', 'Color', 'File', 'Panels',
];

/// The fixed gesture grammar rows: held keys are not (in v1) Bindings the table lists, and
/// Shift-constrain never will be — they get their own section.
List<(String, String)> heldKeyRows() => [
      ('Pan canvas', 'hold Space'),
      ('Pick color', 'hold S'),
      ('Constrain drags', 'hold ⇧ Shift'),
    ];

class KeyboardCheatSheet extends StatelessWidget {
  const KeyboardCheatSheet({super.key, required this.commands, required this.bindings});

  final List<CommandDef> commands;
  final BindingTable bindings;

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, List<CommandDef>>{};
    for (final c in commands) {
      if ((bindings[c.id] ?? const []).isNotEmpty) (byCategory[c.category] ??= []).add(c);
    }
    // Card width sized for the longest chord row even under the test fonts' wide metrics.
    Widget section(String title, List<(String, String)> rows) => SizedBox(
          width: 290,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            for (final (label, keys) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(children: [
                  Expanded(
                      child: Text(label,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text(keys,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
                ]),
              ),
          ]),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 24,
        runSpacing: 4,
        children: [
          for (final cat in _categoryOrder)
            if (byCategory.containsKey(cat))
              section(cat, [
                for (final c in byCategory[cat]!)
                  (c.label, bindings[c.id]!.map((ch) => ch.display()).join(' · ')),
              ]),
          section('Held keys', heldKeyRows()),
        ],
      ),
    );
  }
}

/// The ☰ → Keyboard page: the same sheet under an app bar (read-only in v1; phase 6.B grows
/// the rebinding controls here).
class KeyboardCheatSheetPage extends StatelessWidget {
  const KeyboardCheatSheetPage({super.key, required this.commands, required this.bindings});

  final List<CommandDef> commands;
  final BindingTable bindings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15171A),
      appBar: AppBar(title: const Text('Keyboard')),
      body: KeyboardCheatSheet(commands: commands, bindings: bindings),
    );
  }
}

/// The hold-Primary overlay chrome around the sheet (shown by the dispatcher while the
/// Primary modifier is held alone; ignores pointers — it is a transient reference card).
class KeyboardOverlay extends StatelessWidget {
  const KeyboardOverlay({super.key, required this.commands, required this.bindings});

  final List<CommandDef> commands;
  final BindingTable bindings;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        alignment: Alignment.center,
        color: const Color(0xC0000000),
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 560),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF0181A1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: KeyboardCheatSheet(commands: commands, bindings: bindings),
          ),
        ),
      ),
    );
  }
}
