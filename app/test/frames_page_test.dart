// The Frames page (frames/frames_page.dart) over a scripted host: selection gestures, the
// action bar, the batch verbs it sends, refusals, the post-batch selection, the keyboard, and
// the sheets. No engine — thumbnails are synthetic bytes.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/frames/frame_model.dart';
import 'package:makapix_club/editor/frames/frame_tile.dart';
import 'package:makapix_club/editor/frames/frames_more_sheet.dart';
import 'package:makapix_club/editor/tap_again.dart';

import 'frames_test_support.dart';

Finder tile(int number) => find.ancestor(of: find.text('$number'), matching: find.byType(FrameTile));

void main() {
  group('dslForOp', () {
    const idx = [0, 1, 2, 5];
    test('renders every op', () {
      expect(dslForOp(const RepeatAfterOp(), idx), 'RepeatFramesAfter(0-2 5)');
      expect(dslForOp(const InsertBlankOp(before: true), idx), 'InsertBlankFrames(0-2 5, before)');
      expect(dslForOp(const InsertBlankOp(before: false), idx), 'InsertBlankFrames(0-2 5, after)');
      expect(dslForOp(const ReverseOp(), idx), 'ReverseFrames(0-2 5)');
      expect(dslForOp(const ShiftByOp(), idx, delta: -2), 'ShiftFrames(0-2 5, -2)');
      expect(dslForOp(const ScaleOp(500), idx), 'ScaleFrameDurations(0-2 5, 500)');
      expect(dslForOp(const ScaleOp(null), idx, permille: 1500), 'ScaleFrameDurations(0-2 5, 1500)');
      expect(dslForOp(const FlipOp(horizontal: true), idx), 'FlipFramesH(0-2 5)');
      expect(dslForOp(const FlipOp(horizontal: false), idx), 'FlipFramesV(0-2 5)');
      expect(dslForOp(const RotateOp(3), idx), 'RotateFrames(0-2 5, 3)');
      expect(dslForOp(const InvertOp(), idx), 'InvertFrames(0-2 5)');
      expect(dslForOp(const CopyLayerOp(), idx), 'CopyLayerToFrames(0-2 5)');
      expect(dslForOp(const RemoveLayerNamedOp(), idx, layerName: 'Sky, dawn'), 'RemoveLayersNamed(0-2 5, Sky, dawn)');
      expect(dslForOp(const SetLayersVisibleOp(visible: false), idx, layerName: 'A;B\n'), 'SetLayersVisibleNamed(0-2 5, 0, A B)');
      expect(dslForOp(const SetLayersLockedOp(locked: true), idx, layerName: 'A'), 'SetLayersLockedNamed(0-2 5, 1, A)');
    });
    test('content and name classification', () {
      expect(opChangesContent(const FlipOp(horizontal: true)), isTrue);
      expect(opChangesContent(const ReverseOp()), isFalse);
      expect(opNeedsLayerName(const RemoveLayerNamedOp()), isTrue);
      expect(opNeedsLayerName(const CopyLayerOp()), isFalse);
    });
  });

  group('FramesPage', () {
    testWidgets('renders tiles with numbers, durations, and the active marker; tap toggles and enables the bar',
        (tester) async {
      final host = FakeFramesHost(fakeFrames(6), active: 2);
      await pumpFramesPage(tester, host);
      expect(find.text('Frames · 6'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('100 ms'), findsNWidgets(6));
      final activeTile = tester.widget<FrameTile>(tile(3));
      expect(activeTile.active, isTrue);
      expect(tester.widget<FrameTile>(tile(1)).active, isFalse);
      expect(find.text('Tap to select · hold to sweep · double-tap to go to'), findsOneWidget);

      await tester.tap(tile(2));
      await tester.pump();
      expect(tester.widget<FrameTile>(tile(2)).selected, isTrue);
      expect(find.text('1 selected · 2'), findsOneWidget);
      await tester.tap(tile(4));
      await tester.pump();
      expect(find.text('2 selected · 2, 4'), findsOneWidget);
      await tester.tap(tile(2));
      await tester.pump();
      expect(tester.widget<FrameTile>(tile(2)).selected, isFalse);
      expect(find.text('1 selected · 4'), findsOneWidget);
    });

    testWidgets('a second tap on the same tile inside the double-tap window pops with the index', (tester) async {
      final host = FakeFramesHost(fakeFrames(4));
      final popped = await pumpFramesPage(tester, host);
      await tester.tap(tile(3));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(tile(3));
      await tester.pumpAndSettle();
      expect(popped, [2]);
    });

    testWidgets('long-press then drag sweeps a range', (tester) async {
      final host = FakeFramesHost(fakeFrames(8));
      await pumpFramesPage(tester, host);
      final g = await tester.startGesture(tester.getCenter(tile(2)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.moveTo(tester.getCenter(tile(7)));
      await tester.pump();
      await g.up();
      await tester.pump();
      for (final n in [2, 3, 4, 5, 6, 7]) {
        expect(tester.widget<FrameTile>(tile(n)).selected, isTrue, reason: 'tile $n joins the sweep');
      }
      expect(tester.widget<FrameTile>(tile(1)).selected, isFalse);
      expect(tester.widget<FrameTile>(tile(8)).selected, isFalse);
    });

    testWidgets('Delete arms, then confirms with one RemoveFrames verb; disabled when everything is selected',
        (tester) async {
      final host = FakeFramesHost(fakeFrames(4));
      host.onRun = (dsl) {
        if (dsl.startsWith('RemoveFrames')) host.frames = [host.frames[0], host.frames[3]];
        return null;
      };
      await pumpFramesPage(tester, host);
      await tester.tap(tile(2));
      await tester.tap(tile(3));
      await tester.pump();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(find.text('Tap again'), findsOneWidget);
      expect(host.scripts, isEmpty);
      await tester.tap(find.text('Tap again'));
      await tester.pump();
      expect(host.scripts, ['RemoveFrames(1-2)']);
      expect(find.text('Frames · 2'), findsOneWidget);
      expect(find.text('Tap to select · hold to sweep · double-tap to go to'), findsOneWidget, reason: 'deleted members drop out');

      await tester.tap(tile(1));
      await tester.tap(tile(2));
      await tester.pump();
      final btn = tester.widget<TapAgainDeleteButton>(find.byType(TapAgainDeleteButton));
      expect(btn.onConfirmed, isNull, reason: 'cannot delete every frame');
    });

    testWidgets('a refused batch shows the reason and keeps the selection', (tester) async {
      final host = FakeFramesHost(fakeFrames(5));
      await pumpFramesPage(tester, host);
      await tester.tap(tile(1));
      await tester.pump();
      host.refusal = 'DuplicateFrames: 1000 + 40 frames would exceed the 1024-frame cap';
      await tester.tap(find.text('Duplicate'));
      await tester.pump();
      expect(find.textContaining('exceed the 1024-frame cap'), findsOneWidget);
      expect(tester.widget<FrameTile>(tile(1)).selected, isTrue);
    });

    testWidgets('Duplicate selects the copies', (tester) async {
      final host = FakeFramesHost(fakeFrames(4));
      host.onRun = (dsl) {
        if (dsl == 'DuplicateFrames(0 2)') {
          final f = host.frames;
          host.frames = [f[0], const FrameInfo(id: 900), f[1], f[2], const FrameInfo(id: 901), f[3]];
        }
        return null;
      };
      await pumpFramesPage(tester, host);
      await tester.tap(tile(1));
      await tester.tap(tile(3));
      await tester.pump();
      await tester.tap(find.text('Duplicate'));
      await tester.pump();
      expect(host.scripts, ['DuplicateFrames(0 2)']);
      expect(find.text('Frames · 6'), findsOneWidget);
      expect(tester.widget<FrameTile>(tile(2)).selected, isTrue, reason: 'the copy of frame 1');
      expect(tester.widget<FrameTile>(tile(5)).selected, isTrue, reason: 'the copy of frame 3');
      expect(tester.widget<FrameTile>(tile(1)).selected, isFalse);
      expect(find.text('2 selected · 2, 5'), findsOneWidget);
    });

    testWidgets('nudge sends a clamped ShiftFrames and disables at the edge', (tester) async {
      final host = FakeFramesHost(fakeFrames(4));
      await pumpFramesPage(tester, host);
      await tester.tap(tile(1));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Shift left'));
      await tester.pump();
      expect(host.scripts, isEmpty, reason: 'frame 1 cannot move left');
      await tester.tap(find.bySemanticsLabel('Shift right'));
      await tester.pump();
      expect(host.scripts, ['ShiftFrames(0, 1)']);
    });

    testWidgets('keyboard: Ctrl+A, arrows, Enter with one selected, Esc clears then pops', (tester) async {
      final host = FakeFramesHost(fakeFrames(3));
      final popped = await pumpFramesPage(tester, host);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.text('3 selected · 1–3'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(host.scripts, isEmpty, reason: 'everything selected: no room');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Tap to select · hold to sweep · double-tap to go to'), findsOneWidget);
      await tester.tap(tile(2));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(host.scripts, ['ShiftFrames(1, -1)']);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(popped, [1]);
    });

    testWidgets('Esc on an empty selection pops without a target', (tester) async {
      final host = FakeFramesHost(fakeFrames(2));
      final popped = await pumpFramesPage(tester, host);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(popped, [null]);
    });

    testWidgets('Delete key arms the same button and a second press confirms', (tester) async {
      final host = FakeFramesHost(fakeFrames(3));
      await pumpFramesPage(tester, host);
      await tester.tap(tile(2));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(find.text('Tap again'), findsOneWidget);
      expect(find.textContaining('Press Delete again'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(host.scripts, ['RemoveFrames(1)']);
    });

    testWidgets('undo/redo buttons follow the host and re-sync', (tester) async {
      final host = FakeFramesHost(fakeFrames(3));
      await pumpFramesPage(tester, host);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo)).onPressed, isNull);
      host.canUndoV = true;
      await tester.tap(tile(1));
      await tester.pump();
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(host.undos, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(host.undos, 2);
    });

    testWidgets('More → Flip H sends the verb and regenerates the selected thumbnails', (tester) async {
      final host = FakeFramesHost(fakeFrames(3));
      await pumpFramesPage(tester, host);
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });
      final before = host.thumbRequests;
      expect(before, greaterThan(0));
      await tester.tap(tile(1));
      await tester.tap(tile(2));
      await tester.pump();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected frames'), findsOneWidget);
      await tester.ensureVisible(find.text('Flip H'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flip H'));
      await tester.pumpAndSettle();
      expect(host.scripts, ['FlipFramesH(0-1)']);
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });
      expect(host.thumbRequests, greaterThan(before), reason: 'the flipped frames re-thumbnail');
    });

    testWidgets('More shows the memory note above 64 MiB and the rotate note on a non-square canvas', (tester) async {
      final host = FakeFramesHost(
        [for (var i = 0; i < 2; i++) FrameInfo(id: 100 + i, layers: const [LayerInfo(name: 'L', presentTiles: 20000)])],
        canvas: (w: 64, h: 32),
      );
      await pumpFramesPage(tester, host);
      await tester.tap(tile(1));
      await tester.tap(tile(2));
      await tester.pump();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Undo will hold about 156 MB'), findsOneWidget);
      expect(find.textContaining('Not square'), findsOneWidget);
    });

    testWidgets('layer-name ops go through the picker with hit counts', (tester) async {
      final host = FakeFramesHost([
        ...fakeFrames(2, layerNames: const ['Layer 1', 'Shading']),
        ...fakeFrames(1).map((f) => FrameInfo(id: 300, layers: f.layers)),
      ]);
      await pumpFramesPage(tester, host);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hide layer named…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide layer named…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 of 3 selected frames have a layer named "Shading"'), findsOneWidget);
      expect(find.textContaining('3 of 3 selected frames have a layer named "Layer 1"'), findsOneWidget);
      await tester.tap(find.text('Shading'));
      await tester.pumpAndSettle();
      expect(host.scripts, ['SetLayersVisibleNamed(0-2, 0, Shading)']);
    });

    testWidgets('Duration applies to the set and reports pinned frames', (tester) async {
      final host = FakeFramesHost(fakeFrames(3));
      await pumpFramesPage(tester, host);
      await tester.tap(tile(1));
      await tester.tap(tile(3));
      await tester.pump();
      await tester.tap(find.text('Duration'));
      await tester.pumpAndSettle();
      expect(find.text('2 frames — duration'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '10');
      await tester.pump();
      await tester.tap(find.text('Apply to 2 frames'));
      await tester.pumpAndSettle();
      expect(host.scripts, ['SetFrameDurations(0 2, 16.60)']);
      expect(find.text('2 frames pinned at 16.7 ms'), findsOneWidget);
    });

    testWidgets('Select frames… and Every Nth… set the selection from the dialogs', (tester) async {
      final host = FakeFramesHost(fakeFrames(10));
      await pumpFramesPage(tester, host);
      await tester.tap(find.byTooltip('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select frames…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2-4, 9');
      await tester.pump();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('4 selected · 2–4, 9'), findsOneWidget);

      await tester.tap(find.byTooltip('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every Nth frame…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Whole roll'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Select'));
      await tester.pumpAndSettle();
      expect(find.text('5 selected · 1, 3, 5, 7, 9'), findsOneWidget);
    });

    testWidgets('right-click opens the tile menu; Frame options re-syncs after the sheet', (tester) async {
      final host = FakeFramesHost(fakeFrames(3));
      await pumpFramesPage(tester, host);
      await tester.tap(tile(2), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Go to frame 2'), findsOneWidget);
      await tester.tap(find.text('Frame options…'));
      await tester.pumpAndSettle();
      expect(host.sheetsOpened, [1]);
    });

    testWidgets('the tile overflow opens the menu and Go to pops', (tester) async {
      final host = FakeFramesHost(fakeFrames(3));
      final popped = await pumpFramesPage(tester, host);
      final overflow = find.descendant(of: tile(3), matching: find.byIcon(Icons.more_vert));
      await tester.tap(overflow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to frame 3'));
      await tester.pumpAndSettle();
      expect(popped, [2]);
    });
  });
}
