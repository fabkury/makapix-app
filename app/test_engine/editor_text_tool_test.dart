// The Text tool on the REAL editor (ADR 0039, ADR 0040; docs/text-tool/DESIGN.md): a tap opens
// a Text Draft, the docked field types into it, and a commit leaves exactly ONE journal line —
// a self-contained `MaskStamp` — no matter how many keystrokes built the text.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/widgets/tool_tile.dart';

import 'editor_harness.dart';

Finder _tile(String dsl) => find.byWidgetPredicate((w) => w is ToolTile && w.tool.dsl == dsl);
final _field = find.byKey(const ValueKey('editor-text-field'));
final _commit = find.byKey(const ValueKey('editor-text-commit'));
final _dot = find.byKey(const ValueKey('text-missing-dot'));
final _wrapChip = find.byKey(const ValueKey('text-wrap-chip'));

/// A point well inside the canvas area of the 412 × 915 portrait layout.
const _onCanvas = Offset(206, 300);

Future<void> _selectTool(WidgetTester tester, String dsl) async {
  await tester.ensureVisible(_tile(dsl).first);
  await tester.pump();
  await tester.tap(_tile(dsl).first);
  await settleReal(tester, rounds: 2);
}

/// Selects the Text tool and waits for the bundled fonts: they load in the background after
/// the editor mounts, and a tap on the canvas opens no Draft before the Font is there.
Future<void> _selectText(WidgetTester tester) async {
  await _selectTool(tester, 'Text');
  final named = find.descendant(
      of: find.byKey(const ValueKey('text-font-button')), matching: find.textContaining(' px'));
  for (var i = 0; i < 50 && named.evaluate().isEmpty; i++) {
    await settleReal(tester, rounds: 1);
  }
  expect(named, findsOneWidget, reason: 'the fonts never loaded');
}

/// The editor accepts no canvas input until its drawing is restored and journaled (ADR 0014),
/// silently — so the first gesture is retried until a Text Draft opens.
Future<void> _openDraft(WidgetTester tester, Future<void> Function() gesture) async {
  for (var i = 0; i < 40 && _field.evaluate().isEmpty; i++) {
    await gesture();
    await settleReal(tester, rounds: 3);
  }
  expect(_field, findsOneWidget, reason: 'no Text Draft opened');
}

List<String> _journalActions(Directory dir) => [
      for (final f in dir.listSync(recursive: true))
        if (f is File && f.path.endsWith('journal.mkpxj'))
          ...f.readAsLinesSync().where((l) => l.startsWith('+')),
    ];

void main() {
  testWidgets('a tap opens a Text Draft, typing previews it, and commit journals one MaskStamp',
      (tester) async {
    final dir = await pumpEditor(tester, const Locale('en'));
    await _selectText(tester);
    expect(_field, findsNothing, reason: 'no Draft until the canvas is touched');
    expect(tester.widget<FilterChip>(_wrapChip).onSelected, isNull, reason: 'Wrap needs a Draft');

    await _openDraft(tester, () => tester.tapAt(_onCanvas));
    expect(tester.widget<FilterChip>(_wrapChip).selected, isFalse, reason: 'a tap starts without a Wrap width');

    // Several edits: every one re-sends the preview mask; none of them may reach the Journal.
    for (final words in ['H', 'Hi', 'Hi!', 'Hi']) {
      await tester.enterText(_field, words);
      await settleReal(tester, rounds: 1);
    }
    expect(_dot, findsNothing);

    // While the Draft is open a tap on the canvas does nothing: the Draft stays, the words stay.
    await tester.tapAt(_onCanvas + const Offset(40, 60));
    await settleReal(tester, rounds: 1);
    expect(_field, findsOneWidget);
    expect(tester.widget<TextField>(_field).controller!.text, 'Hi');

    await tester.tap(_commit);
    await settleReal(tester, rounds: 3);
    expect(_field, findsNothing, reason: 'a commit closes the Draft');

    // The tool remembers the words: the next Draft starts with them, fully selected.
    await tester.tapAt(_onCanvas + const Offset(0, 80));
    await settleReal(tester, rounds: 3);
    final ctrl = tester.widget<TextField>(_field).controller!;
    expect(ctrl.text, 'Hi');
    expect(ctrl.selection, const TextSelection(baseOffset: 0, extentOffset: 2));

    // A character the font cannot draw shows the amber mark on the commit controls.
    await tester.enterText(_field, 'A日');
    await settleReal(tester, rounds: 1);
    expect(_dot, findsWidgets);

    // Leaving the tool kills the Draft (ADR 0011) without committing it.
    await _selectTool(tester, 'Pencil');
    expect(_field, findsNothing);

    await closeEditor(tester);
    final actions = _journalActions(dir);
    final stamps = actions.where((l) => l.contains('MaskStamp(')).toList();
    expect(stamps, hasLength(1), reason: 'one commit, one journal line');
    expect(actions.where((l) => l.contains('MaskDraft')), isEmpty, reason: 'the preview is never journaled');
    expect(actions.where((l) => l.contains('SelectTool(Text)')), isEmpty, reason: 'Text is a shell-only tool id');
  });

  testWidgets('a drag starts a Text Draft with a Wrap width, and the Wrap chip removes and restores it',
      (tester) async {
    await pumpEditor(tester, const Locale('en'));
    await _selectText(tester);
    await _openDraft(tester, () async {
      final g = await tester.startGesture(_onCanvas - const Offset(60, 40));
      await tester.pump(const Duration(milliseconds: 30));
      await g.moveBy(const Offset(70, 30));
      await tester.pump(const Duration(milliseconds: 30));
      await g.moveBy(const Offset(50, 30));
      await tester.pump(const Duration(milliseconds: 30));
      await g.up();
    });
    expect(tester.widget<FilterChip>(_wrapChip).selected, isTrue);

    await tester.ensureVisible(_wrapChip);
    await tester.pump();
    await tester.tap(_wrapChip);
    await settleReal(tester, rounds: 1);
    expect(tester.widget<FilterChip>(_wrapChip).selected, isFalse);
    await tester.tap(_wrapChip);
    await settleReal(tester, rounds: 1);
    expect(tester.widget<FilterChip>(_wrapChip).selected, isTrue);

    // An empty text has nothing to stamp: the commit just closes the Draft.
    await tester.enterText(_field, '');
    await settleReal(tester, rounds: 1);
    await tester.tap(_commit);
    await settleReal(tester, rounds: 2);
    expect(_field, findsNothing);
    await closeEditor(tester);
  });

  testWidgets('the font button opens the picker, and a picked font is remembered', (tester) async {
    await pumpEditor(tester, const Locale('en'));
    await _selectText(tester);
    final button = find.byKey(const ValueKey('text-font-button'));
    expect(find.descendant(of: button, matching: find.textContaining('Everyday Standard')), findsOneWidget);
    await tester.tap(button);
    await settleReal(tester, rounds: 4);
    final row = find.byKey(const ValueKey('font-row-vexed.tiny_talk'));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await settleReal(tester, rounds: 4);
    expect(find.descendant(of: button, matching: find.textContaining('Tiny Talk')), findsOneWidget);
    await closeEditor(tester);
  });
}
