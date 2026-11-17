// Merge visible and Flatten frame (ADR 0038) on the REAL editor: the two buttons in the layer
// sheet and in the frame sheet. The engine's own tests cover what the verbs do to pixels and to
// hidden or locked layers; this checks that the buttons are wired, enabled only when there is
// something to merge, and that the sheets stay open and follow the result.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

void main() {
  testWidgets('Merge visible and Flatten frame, from the layer sheet and the frame sheet',
      (tester) async {
    const locale = Locale('en');
    await pumpEditor(tester, locale);
    final l = l10nFor(locale);
    final addLayer = find.byTooltip(l.editorAddLayer);

    // Layer tiles of the active frame, counted on the strip (no sheet open).
    int layers() => find.byIcon(Icons.visibility).evaluate().length;
    Finder button(String label) => find.widgetWithText(FilledButton, label);
    bool enabled(String label) => tester.widget<FilledButton>(button(label)).onPressed != null;

    Future<void> addLayers(int n) async {
      for (var i = 0; i < n; i++) {
        await tester.tap(addLayer);
        await settleReal(tester, rounds: 3);
      }
    }

    Future<void> press(String label) async {
      await tester.ensureVisible(button(label));
      await tester.pump();
      await tester.tap(button(label));
      await settleReal(tester, rounds: 4);
    }

    Future<void> dismiss() async {
      await tester.tapAt(const Offset(4, 4));
      await settleReal(tester, rounds: 9);
    }

    // The layer sheet: with one layer both buttons are disabled.
    await tester.longPress(find.byIcon(Icons.visibility).first);
    await settleReal(tester, rounds: 9);
    expect(enabled(l.layerMergeVisible), isFalse);
    expect(enabled(l.frameFlatten), isFalse);
    await dismiss();

    // Three layers → Merge visible leaves one; the sheet stays open and the buttons go off.
    await addLayers(2);
    expect(layers(), 3);
    await tester.longPress(find.byIcon(Icons.visibility).first);
    await settleReal(tester, rounds: 9);
    expect(enabled(l.layerMergeVisible), isTrue);
    await press(l.layerMergeVisible);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'the layer sheet stays open');
    expect(enabled(l.layerMergeVisible), isFalse);
    expect(enabled(l.frameFlatten), isFalse);
    await dismiss();
    expect(layers(), 1);

    // Two layers → Flatten frame from the layer sheet.
    await addLayers(1);
    await tester.longPress(find.byIcon(Icons.visibility).first);
    await settleReal(tester, rounds: 9);
    await press(l.frameFlatten);
    await dismiss();
    expect(layers(), 1);

    // The frame sheet has the same two buttons, acting on the frame the sheet shows.
    await addLayers(2);
    await tester.longPress(find.text('1').first);
    await settleReal(tester, rounds: 9);
    expect(enabled(l.layerMergeVisible), isTrue);
    await press(l.frameFlatten);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'the frame sheet stays open');
    expect(enabled(l.frameFlatten), isFalse);
    await dismiss();
    expect(layers(), 1);

    await addLayers(1);
    await tester.longPress(find.text('1').first);
    await settleReal(tester, rounds: 9);
    await press(l.layerMergeVisible);
    await dismiss();
    expect(layers(), 1);

    // One Undo brings the two layers back: each operation is a single undo step.
    await tester.tap(find.byIcon(Icons.undo));
    await settleReal(tester, rounds: 3);
    expect(layers(), 2);

    await closeEditor(tester);
  });
}
