// The Layers page (layers/layers_page.dart) over a scripted host: rows top-first with
// bottom-first numbers, selection gestures (tap, sideways-slide sweep, long-press menu), the
// action bar, the batch verbs it sends, refusals and pre-checks on the status line, the
// post-batch selection, the keyboard, and the pops. No engine — thumbnails are synthetic bytes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/layers/layer_model.dart';
import 'package:makapix_club/editor/layers/layer_row.dart';
import 'package:makapix_club/editor/tap_again.dart';

import 'layers_test_support.dart';

/// The row of the layer numbered [number] (1 = bottom).
Finder row(int number) => find.ancestor(of: find.text('$number'), matching: find.byType(LayerRowTile));

LayerRowTile tileOf(WidgetTester t, int number) => t.widget<LayerRowTile>(row(number));

void main() {
  group('LayersPage', () {
    testWidgets('renders the stack top first with bottom-first numbers and the active marker; tap toggles', (tester) async {
      final host = FakeLayersHost(fakeLayers(4), active: 2);
      await pumpLayersPage(tester, host);
      expect(find.text('Layers · 4'), findsOneWidget);
      // Top of the stack first: layer 4 sits above layer 1 on screen.
      expect(tester.getTopLeft(row(4)).dy, lessThan(tester.getTopLeft(row(1)).dy));
      expect(tileOf(tester, 3).active, isTrue);
      expect(tileOf(tester, 1).active, isFalse);
      expect(find.text('Tap or slide to select · hold for options · double-tap to make active'), findsOneWidget);

      await tester.tap(row(2));
      await tester.pump();
      expect(tileOf(tester, 2).selected, isTrue);
      expect(find.text('1 selected · 2'), findsOneWidget);
      await tester.tap(row(4));
      await tester.pump();
      expect(find.text('2 selected · 2, 4'), findsOneWidget);
      await tester.tap(row(2));
      await tester.pump();
      expect(tileOf(tester, 2).selected, isFalse);
    });

    testWidgets('a second tap on the same row inside the double-tap window pops with Make active', (tester) async {
      final host = FakeLayersHost(fakeLayers(4));
      final popped = await pumpLayersPage(tester, host);
      await tester.tap(row(3));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(row(3));
      await tester.pumpAndSettle();
      expect(popped.single?.activateIndex, 2);
    });

    testWidgets('a sideways slide sweeps the rows it crosses', (tester) async {
      final host = FakeLayersHost(fakeLayers(6));
      await pumpLayersPage(tester, host);
      final g = await tester.startGesture(tester.getCenter(row(5)));
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      await g.moveTo(tester.getCenter(row(2)));
      await tester.pump();
      await g.up();
      await tester.pump();
      for (final n in [2, 3, 4, 5]) {
        expect(tileOf(tester, n).selected, isTrue, reason: 'layer $n joins the sweep');
      }
      expect(tileOf(tester, 1).selected, isFalse);
      expect(tileOf(tester, 6).selected, isFalse);
      expect(find.text('4 selected · 2–5'), findsOneWidget);
    });

    testWidgets('Delete arms then sends RemoveLayers; every layer selected is allowed and reported', (tester) async {
      final host = FakeLayersHost(fakeLayers(3));
      host.onRun = (dsl) {
        if (dsl.startsWith('RemoveLayers')) host.layers = [const LayerRow(id: 900, name: 'Layer 1')];
        return null;
      };
      await pumpLayersPage(tester, host);
      await tester.tap(row(1));
      await tester.tap(row(2));
      await tester.tap(row(3));
      await tester.pump();
      await tester.tap(find.byType(TapAgainDeleteButton));
      await tester.pump();
      expect(host.scripts, isEmpty, reason: 'the first tap only arms');
      await tester.tap(find.byType(TapAgainDeleteButton));
      await tester.pump();
      expect(host.scripts, ['RemoveLayers(0-2)']);
      expect(find.text('Every layer removed — one blank layer took their place'), findsOneWidget);
      expect(find.text('Layers · 1'), findsOneWidget);
    });

    testWidgets('Merge pre-checks a gap on the status line, then sends MergeLayers and selects the survivor', (tester) async {
      final host = FakeLayersHost(fakeLayers(5));
      await pumpLayersPage(tester, host);
      await tester.tap(row(1));
      await tester.tap(row(3));
      await tester.pump();
      await tester.tap(find.text('Merge'));
      await tester.pump();
      expect(host.scripts, isEmpty);
      expect(find.textContaining('contiguous run'), findsOneWidget);

      host.onRun = (dsl) {
        if (dsl.startsWith('MergeLayers')) host.layers = [fakeLayers(5)[0], fakeLayers(5)[3], fakeLayers(5)[4]];
        return null;
      };
      await tester.tap(row(2)); // 1-3: one run
      await tester.pump();
      await tester.tap(find.text('Merge'));
      await tester.pump();
      expect(host.scripts, ['MergeLayers(0-2)']);
      expect(find.text('Merged 3 layers into L1'), findsOneWidget);
      expect(find.text('Layers · 3'), findsOneWidget);
      expect(tileOf(tester, 1).selected, isTrue, reason: 'the survivor is the selection');
    });

    testWidgets('Merge over a locked member is refused before the tap reaches the engine', (tester) async {
      final host = FakeLayersHost([
        ...fakeLayers(5).sublist(0, 2),
        const LayerRow(id: 502, name: 'L3', locked: true, presentTiles: 1),
        ...fakeLayers(5).sublist(3),
      ]);
      await pumpLayersPage(tester, host);
      await tester.tap(row(1));
      await tester.tap(row(2));
      await tester.tap(row(3));
      await tester.pump();
      await tester.tap(find.text('Merge'));
      await tester.pump();
      expect(host.scripts, isEmpty);
      expect(find.text('1 selected layer is locked — unlock it first'), findsOneWidget);
    });

    testWidgets('a refusal from the engine leaves the selection alone and shows the reason', (tester) async {
      final host = FakeLayersHost(fakeLayers(4));
      await pumpLayersPage(tester, host);
      await tester.tap(row(2));
      await tester.pump();
      host.refusal = 'ShiftLayers: layer 9 is out of range (the frame has 4 layers)';
      await tester.tap(find.bySemanticsLabel('Shift up'));
      await tester.pump();
      expect(host.scripts, ['ShiftLayers(1, 1)']);
      expect(find.text('ShiftLayers: layer 9 is out of range (the frame has 4 layers)'), findsOneWidget);
      expect(tileOf(tester, 2).selected, isTrue);
    });

    testWidgets('Shift up/down send clamped rigid shifts and disable at the edges', (tester) async {
      final host = FakeLayersHost(fakeLayers(3));
      await pumpLayersPage(tester, host);
      await tester.tap(row(3));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Shift up'));
      await tester.pump();
      expect(host.scripts, isEmpty, reason: 'the top layer cannot move up');
      await tester.tap(find.bySemanticsLabel('Shift down'));
      await tester.pump();
      expect(host.scripts, ['ShiftLayers(2, -1)']);
    });

    testWidgets('the More sheet sends Duplicate and selects the copies; Show/Hide are property batches', (tester) async {
      final host = FakeLayersHost(fakeLayers(3));
      host.onRun = (dsl) {
        if (dsl.startsWith('DuplicateLayers')) {
          host.layers = [
            const LayerRow(id: 500, name: 'L1', presentTiles: 1),
            const LayerRow(id: 600, name: 'L1 copy', presentTiles: 1),
            const LayerRow(id: 501, name: 'L2', presentTiles: 1),
            const LayerRow(id: 502, name: 'L3', presentTiles: 1),
            const LayerRow(id: 601, name: 'L3 copy', presentTiles: 1),
          ];
        }
        return null;
      };
      await pumpLayersPage(tester, host);
      await tester.tap(row(1));
      await tester.tap(row(3));
      await tester.pump();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(host.scripts, ['DuplicateLayers(0 2)']);
      expect(find.text('2 selected · 2, 5'), findsOneWidget, reason: 'the copies are the selection');

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(host.scripts.last, 'SetLayersVisible(1 4, 0)');
    });

    testWidgets('a locked member disables the Content chips and the note says so', (tester) async {
      final host = FakeLayersHost([
        const LayerRow(id: 1, name: 'a', presentTiles: 1),
        const LayerRow(id: 2, name: 'b', locked: true, presentTiles: 1),
      ]);
      await pumpLayersPage(tester, host);
      await tester.tap(row(1));
      await tester.tap(row(2));
      await tester.pump();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected layer is locked — these refuse'), findsOneWidget);
      final chip = tester.widget<ActionChip>(find.widgetWithText(ActionChip, 'Flip H'));
      expect(chip.onPressed, isNull);
    });

    testWidgets('Use as Move group pops with the selection', (tester) async {
      final host = FakeLayersHost(fakeLayers(4));
      final popped = await pumpLayersPage(tester, host);
      await tester.tap(row(2));
      await tester.tap(row(4));
      await tester.pump();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use as Move group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use as Move group'));
      await tester.pumpAndSettle();
      expect(popped.single?.moveGroup, [1, 3]);
    });

    testWidgets('the row menu offers Make active, Select to here, and Layer options', (tester) async {
      final host = FakeLayersHost(fakeLayers(5));
      final popped = await pumpLayersPage(tester, host);
      await tester.tap(row(1));
      await tester.pump();
      await tester.longPress(row(4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select to here'));
      await tester.pumpAndSettle();
      expect(find.text('4 selected · 1–4'), findsOneWidget);

      await tester.longPress(row(5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Layer options…'));
      await tester.pumpAndSettle();
      expect(host.sheetsOpened, [4]);

      await tester.longPress(row(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make active'));
      await tester.pumpAndSettle();
      expect(popped.single?.activateIndex, 1);
    });

    testWidgets('Select by… replaces the selection, or adds to it when the switch is on', (tester) async {
      final host = FakeLayersHost([
        const LayerRow(id: 1, name: 'a', presentTiles: 0),
        const LayerRow(id: 2, name: 'b', visible: false, presentTiles: 1),
        const LayerRow(id: 3, name: 'c', presentTiles: 0),
      ]);
      await pumpLayersPage(tester, host);
      await tester.tap(row(2));
      await tester.pump();
      await tester.tap(find.byTooltip('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select by…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty · 2'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected · 1, 3'), findsOneWidget, reason: 'replaces by default');

      await tester.tap(find.byTooltip('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select by…'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('A selector adds its layers to what is selected'), findsOneWidget);
      await tester.ensureVisible(find.text('Hidden · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hidden · 1'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected · 1–3'), findsOneWidget, reason: 'adds when the switch is on');
    });

    testWidgets('keyboard: Ctrl+A, arrows shift, Esc clears then pops, Enter makes active', (tester) async {
      final host = FakeLayersHost(fakeLayers(3));
      final popped = await pumpLayersPage(tester, host);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.text('3 selected · 1–3'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(host.scripts, isEmpty, reason: 'the whole stack has no room');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Tap or slide to select · hold for options · double-tap to make active'), findsOneWidget);
      await tester.tap(row(2));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(host.scripts, ['ShiftLayers(1, -1)']);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(popped.single?.activateIndex, 1);
    });

    testWidgets('undo re-validates visible thumbnails and clears the status', (tester) async {
      final host = FakeLayersHost(fakeLayers(3))..canUndoV = true;
      await pumpLayersPage(tester, host);
      // Thumbnails decode asynchronously (a few per frame): let the queue drain for real.
      Future<void> drain() => tester.runAsync(() async {
            for (var i = 0; i < 20; i++) {
              await tester.pump();
              await Future<void>.delayed(const Duration(milliseconds: 30));
            }
            await tester.pump();
          });
      await drain();
      final before = host.thumbRequests;
      expect(before, 3);
      host.hashes[1] = 99; // layer 2 changed under the page
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(host.undos, 1);
      await drain();
      expect(host.thumbRequests, before + 1, reason: 'only the stale thumb regenerates');
    });
  });
}
