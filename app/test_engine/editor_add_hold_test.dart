// The + buttons of the frame strip and the layer strip on the REAL editor: a tap adds a blank
// one, a hold opens a sheet with Add and Duplicate. Long-pressing the frame strip's empty area
// opens the same sheet as holding its + button.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

void main() {
  testWidgets('holding + offers Add and Duplicate, for frames and for layers', (tester) async {
    const locale = Locale('en');
    await pumpEditor(tester, locale);
    final l = l10nFor(locale);
    final addFrame = find.byTooltip(l.editorAddFrame);
    final addLayer = find.byTooltip(l.editorAddLayer);
    expect(addFrame, findsOneWidget);
    expect(addLayer, findsOneWidget);

    // Every layer tile of the active frame carries one eye icon; frame tiles carry their number.
    int layers() => find.byIcon(Icons.visibility).evaluate().length;
    bool hasFrame(int n) => find.text('$n').evaluate().isNotEmpty;

    Future<void> hold(Finder button, String row) async {
      await tester.longPress(button);
      await settleReal(tester, rounds: 9);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'holding + opens the sheet');
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(row)));
      await settleReal(tester, rounds: 9);
      expect(find.byType(BottomSheet), findsNothing, reason: 'choosing a row closes the sheet');
    }

    expect(layers(), 1);
    expect(hasFrame(2), isFalse);

    // Layers: a tap adds, and so does the sheet's first row; the second row duplicates.
    await tester.tap(addLayer);
    await settleReal(tester, rounds: 3);
    expect(layers(), 2, reason: 'a tap on the layer + still adds a layer');
    await hold(addLayer, l.editorAddLayer);
    expect(layers(), 3);
    await hold(addLayer, l.editorDuplicateLayer);
    expect(layers(), 4);

    // Frames. Duplicate frame copies the whole frame, its four layers included; Add frame makes
    // a blank one-layer frame — which is how the two rows are told apart here.
    await hold(addFrame, l.cmdDuplicateFrame);
    expect(hasFrame(2), isTrue);
    expect(layers(), 4, reason: 'the copy has the layers of the frame it was made from');
    await hold(addFrame, l.editorAddFrame);
    expect(hasFrame(3), isTrue);
    expect(layers(), 1, reason: 'Add frame makes a blank frame');
    await tester.tap(addFrame);
    await settleReal(tester, rounds: 3);
    expect(hasFrame(4), isTrue, reason: 'a tap on the frame + still adds a frame');

    // The strip's empty area (right of the last frame tile) opens the same sheet.
    final strip = tester.getRect(find.ancestor(of: find.text('1'), matching: find.byType(ListView)).first);
    await tester.longPressAt(strip.centerRight - const Offset(12, 0));
    await settleReal(tester, rounds: 9);
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text(l.editorAddFrame)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text(l.cmdDuplicateFrame)), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await settleReal(tester, rounds: 9);

    await closeEditor(tester);
  });
}
