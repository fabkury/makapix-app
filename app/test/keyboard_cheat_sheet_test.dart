// The registry-driven cheat sheet (keyboard/cheat_sheet.dart): every populated category
// renders, held keys get their fixed section, and chords display with the platform's
// modifier vocabulary (Ctrl on the test platform).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/keyboard/cheat_sheet.dart';
import 'package:makapix_club/editor/keyboard/commands.dart';
import 'package:makapix_club/editor/keyboard/default_bindings.dart';

void main() {
  testWidgets('the page renders every category, the held keys, and real chords', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: KeyboardCheatSheetPage(commands: buildCommands(), bindings: defaultBindings()),
    ));
    for (final cat in [
      'Tools', 'Edit', 'Draft', 'Playback', 'Frames', 'Layers', 'View', 'Color', 'File', 'Panels',
    ]) {
      expect(find.text(cat), findsOneWidget, reason: cat);
    }
    expect(find.text('Held keys'), findsOneWidget);
    expect(find.text('Pan canvas'), findsOneWidget);
    expect(find.text('Constrain drags'), findsOneWidget);
    // Chords render in the platform vocabulary (Primary = Ctrl under flutter_test).
    expect(find.text('Ctrl+Z'), findsOneWidget); // Undo
    expect(find.text('Ctrl+Shift+Z · Ctrl+Y'), findsOneWidget); // Redo + alias
    expect(find.text('Shift+/'), findsOneWidget); // the ? help chord
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('an unbound command earns no row', (tester) async {
    final bindings = defaultBindings()..['sheet.layers'] = const [];
    await tester.pumpWidget(MaterialApp(
      home: KeyboardCheatSheetPage(commands: buildCommands(), bindings: bindings),
    ));
    expect(find.text('Layer options'), findsNothing);
  });
}
