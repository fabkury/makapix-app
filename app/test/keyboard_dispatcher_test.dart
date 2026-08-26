// EditorKeyboard dispatcher: chord matching, modality gating, repeat suppression, and the
// Enter/Esc priority pairs — driven entirely through a FakeEditorAccess and simulated key
// events (no engine, per the repo's Dart-test contract).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/keyboard/cheat_sheet.dart';
import 'package:makapix_club/editor/keyboard/commands.dart';
import 'package:makapix_club/editor/keyboard/default_bindings.dart';
import 'package:makapix_club/editor/keyboard/dispatcher.dart';

import 'keyboard_test_support.dart';

Future<FakeEditorAccess> pumpKeyboard(WidgetTester tester,
    {FakeEditorAccess? access, Widget child = const SizedBox.expand()}) async {
  final a = access ?? FakeEditorAccess();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: EditorKeyboard(
        access: a,
        commands: buildCommands(),
        bindings: defaultBindings(),
        child: child,
      ),
    ),
  ));
  await tester.pump();
  return a;
}

Future<void> chord(WidgetTester tester, LogicalKeyboardKey key,
    {List<LogicalKeyboardKey> modifiers = const []}) async {
  for (final m in modifiers) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final m in modifiers.reversed) {
    await tester.sendKeyUpEvent(m);
  }
}

void main() {
  // flutter_test runs as TargetPlatform.android → Primary is Ctrl in this whole suite.

  testWidgets('a tool letter selects the tool', (tester) async {
    final a = await pumpKeyboard(tester);
    await chord(tester, LogicalKeyboardKey.keyP);
    expect(a.calls, ['selectTool:Pencil']);
  });

  testWidgets('shifted and primary chords resolve to distinct commands', (tester) async {
    final a = await pumpKeyboard(tester);
    await chord(tester, LogicalKeyboardKey.keyG);
    await chord(tester, LogicalKeyboardKey.keyG, modifiers: [LogicalKeyboardKey.shiftLeft]);
    await chord(tester, LogicalKeyboardKey.keyI, modifiers: [LogicalKeyboardKey.controlLeft]);
    expect(a.calls, [
      'selectTool:Bucket',
      // Holding Shift raises constrain around the shifted chord — and the chord still fires.
      'setConstrain:true', 'selectTool:Gradient', 'setConstrain:false',
      'selectTool:Invert',
    ]);
  });

  testWidgets('undo fires only when available, but the chord is always consumed', (tester) async {
    final a = await pumpKeyboard(tester);
    await chord(tester, LogicalKeyboardKey.keyZ, modifiers: [LogicalKeyboardKey.controlLeft]);
    expect(a.calls, isEmpty); // canUndo false → swallowed, nothing invoked
    a.canUndoV = true;
    await chord(tester, LogicalKeyboardKey.keyZ, modifiers: [LogicalKeyboardKey.controlLeft]);
    expect(a.calls, ['undo']);
  });

  testWidgets('redo answers both Shift+Primary+Z and the Primary+Y alias', (tester) async {
    final a = await pumpKeyboard(tester);
    a.canRedoV = true;
    await chord(tester, LogicalKeyboardKey.keyZ,
        modifiers: [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft]);
    await chord(tester, LogicalKeyboardKey.keyY, modifiers: [LogicalKeyboardKey.controlLeft]);
    expect(a.calls, ['setConstrain:true', 'redo', 'setConstrain:false', 'redo']);
  });

  testWidgets('Enter commits a draft; without one it toggles playback', (tester) async {
    final a = await pumpKeyboard(tester);
    a
      ..hasAnyDraftV = true
      ..frameCountV = 4;
    await chord(tester, LogicalKeyboardKey.enter);
    expect(a.calls, ['commitDraft']);
    a
      ..calls.clear()
      ..hasAnyDraftV = false;
    await chord(tester, LogicalKeyboardKey.enter);
    expect(a.calls, ['togglePlayback']);
  });

  testWidgets('Esc cancels a draft; while playing it stops playback', (tester) async {
    final a = await pumpKeyboard(tester);
    a.hasAnyDraftV = true;
    await chord(tester, LogicalKeyboardKey.escape);
    expect(a.calls, ['cancelDraft']);
    a
      ..calls.clear()
      ..hasAnyDraftV = false
      ..isPlayingV = true;
    await chord(tester, LogicalKeyboardKey.escape);
    expect(a.calls, ['pausePlayback']);
  });

  testWidgets('key repeat is honored only by repeating commands', (tester) async {
    final a = await pumpKeyboard(tester);
    a.frameCountV = 3;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.period);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.period);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.period);
    expect(a.calls, ['stepFrame:1', 'stepFrame:1']); // frame.next repeats
    a.calls.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
    expect(a.calls, ['selectTool:Pencil']); // tool selection fires once
  });

  testWidgets('a focused text field owns the keyboard completely', (tester) async {
    // Focus by tap, as in the real editor (the dispatcher's own node holds autofocus).
    final a = await pumpKeyboard(tester, child: const Column(children: [TextField()]));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await chord(tester, LogicalKeyboardKey.keyP);
    await chord(tester, LogicalKeyboardKey.enter);
    expect(a.calls, isEmpty);
  });

  testWidgets('the non-Primary command modifier disarms chords', (tester) async {
    final a = await pumpKeyboard(tester);
    // Meta is not Primary on Android: Meta+Z must not undo, Meta+P must not select.
    a.canUndoV = true;
    await chord(tester, LogicalKeyboardKey.keyZ, modifiers: [LogicalKeyboardKey.metaLeft]);
    await chord(tester, LogicalKeyboardKey.keyP, modifiers: [LogicalKeyboardKey.metaLeft]);
    expect(a.calls, isEmpty);
  });

  testWidgets('layers, zoom, paste, and brackets route correctly', (tester) async {
    final a = await pumpKeyboard(tester);
    a
      ..layerCountV = 3
      ..activeLayerV = 1;
    await chord(tester, LogicalKeyboardKey.bracketRight, modifiers: [LogicalKeyboardKey.altLeft]);
    await chord(tester, LogicalKeyboardKey.bracketLeft, modifiers: [LogicalKeyboardKey.altLeft]);
    await chord(tester, LogicalKeyboardKey.bracketRight); // brush size, no modifier
    await chord(tester, LogicalKeyboardKey.digit0, modifiers: [LogicalKeyboardKey.controlLeft]);
    await chord(tester, LogicalKeyboardKey.digit1, modifiers: [LogicalKeyboardKey.controlLeft]);
    await chord(tester, LogicalKeyboardKey.keyV, modifiers: [LogicalKeyboardKey.controlLeft]);
    expect(a.calls, [
      // Alt is no longer a Hold binding, so an Alt chord is just a chord: no transient
      // Eyedropper spring around it any more [G-43].
      'moveLayer:1',
      'moveLayer:-1',
      'brushSizeBy:1',
      'zoomFit',
      'zoom100',
      'pasteFromKeyboard',
    ]);
  });

  testWidgets('unbound keys are left alone', (tester) async {
    final a = await pumpKeyboard(tester);
    await chord(tester, LogicalKeyboardKey.keyQ);
    await chord(tester, LogicalKeyboardKey.arrowLeft); // reserved, deliberately unbound
    expect(a.calls, isEmpty);
  });

  // ---- Hold bindings (stage 2) ----

  testWidgets('hold-Space pans: level-triggered, repeat-proof', (tester) async {
    final a = await pumpKeyboard(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(a.calls, ['setSpacePan:true', 'setSpacePan:false']);
  });

  testWidgets('hold-S springs the Eyedropper and restores on release', (tester) async {
    final a = await pumpKeyboard(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    expect(a.calls, ['beginHoldPick', 'endHoldPick']);
  });

  testWidgets('hold-S never fires mid-draft or mid-Gesture', (tester) async {
    final a = await pumpKeyboard(tester);
    a.hasAnyDraftV = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    a
      ..hasAnyDraftV = false
      ..interactionActiveV = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    expect(a.calls, isEmpty);
  });

  // The whole point of leaving Alt: it is an OS chord modifier, so Alt+Tab and every Alt chord
  // used to spring the tool transiently [G-43].
  testWidgets('Alt no longer springs the Eyedropper', (tester) async {
    final a = await pumpKeyboard(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(a.calls, isEmpty);
  });

  // A MODIFIED pick key is a chord, not the hold — Primary+S must still save.
  testWidgets('Primary+S saves instead of springing the pick', (tester) async {
    final a = await pumpKeyboard(tester);
    await chord(tester, LogicalKeyboardKey.keyS, modifiers: [LogicalKeyboardKey.controlLeft]);
    expect(a.calls, ['save']);
  });

  testWidgets('backgrounding force-releases holds; the late keyUp is inert', (tester) async {
    final a = await pumpKeyboard(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    expect(a.calls, ['setSpacePan:true', 'beginHoldPick']);
    a.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(a.calls, ['setSpacePan:false', 'endHoldPick']);
    a.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    expect(a.calls, isEmpty);
  });

  testWidgets('hold-Shift mirrors constrain, level-triggered', (tester) async {
    final a = await pumpKeyboard(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(a.calls, ['setConstrain:true', 'setConstrain:false']);
  });

  testWidgets('backgrounding force-releases constrain too', (tester) async {
    final a = await pumpKeyboard(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftRight);
    a.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(a.calls, ['setConstrain:false']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);
  });

  testWidgets('holding Primary alone raises the cheat-sheet overlay; release hides it',
      (tester) async {
    await pumpKeyboard(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KeyboardOverlay), findsNothing); // not yet — 600 ms threshold
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(KeyboardOverlay), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byType(KeyboardOverlay), findsNothing);
  });

  testWidgets('a chord keeps the overlay away', (tester) async {
    final a = await pumpKeyboard(tester);
    a.canUndoV = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ); // a chord was meant
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(KeyboardOverlay), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(a.calls, ['undo']);
  });

  testWidgets('? routes to the keyboard help page command', (tester) async {
    final a = await pumpKeyboard(tester);
    await chord(tester, LogicalKeyboardKey.slash, modifiers: [LogicalKeyboardKey.shiftLeft]);
    expect(a.calls, ['setConstrain:true', 'openKeyboardHelp', 'setConstrain:false']);
  });

  // ---- ADR 0010: gesture atomicity -------------------------------------------------------

  testWidgets('mid-Gesture, Esc and Undo/Redo CANCEL the gesture and stop there', (tester) async {
    for (final k in [
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.keyZ,
      LogicalKeyboardKey.keyY,
    ]) {
      final a = await pumpKeyboard(tester);
      a.interactionActiveV = true;
      if (k == LogicalKeyboardKey.escape) {
        await chord(tester, k);
      } else {
        await chord(tester, k, modifiers: [LogicalKeyboardKey.controlLeft]);
      }
      expect(a.cancelCount, 1, reason: '\$k must abort the gesture');
      expect(a.finishCount, 0);
      expect(a.calls, isEmpty, reason: 'and must not reach the Command itself');
    }
  });

  testWidgets('mid-Gesture, every other Command FINISHES the gesture first', (tester) async {
    final a = await pumpKeyboard(tester);
    a.interactionActiveV = true;
    await chord(tester, LogicalKeyboardKey.keyE); // a tool mnemonic
    expect(a.finishCount, 1);
    expect(a.cancelCount, 0);
    expect(a.calls, ['selectTool:Eraser']);
  });

  // View Commands never reach the engine, so the _act funnel's own gate cannot see them — the
  // dispatcher has to finish the gesture for them [G-06].
  testWidgets('view Commands finish the gesture too', (tester) async {
    final a = await pumpKeyboard(tester);
    a.interactionActiveV = true;
    await chord(tester, LogicalKeyboardKey.digit0, modifiers: [LogicalKeyboardKey.controlLeft]);
    expect(a.finishCount, 1);
    expect(a.calls, ['zoomFit']);
  });

  testWidgets('with no Gesture in flight nothing is finished or cancelled', (tester) async {
    final a = await pumpKeyboard(tester);
    await chord(tester, LogicalKeyboardKey.keyE);
    expect(a.finishCount, 0);
    expect(a.cancelCount, 0);
    expect(a.calls, ['selectTool:Eraser']);
  });

  // The reference card is not what the artist is asking for mid-stroke [G-12].
  testWidgets('the cheat-sheet overlay does not arm mid-Gesture', (tester) async {
    final a = await pumpKeyboard(tester);
    a.interactionActiveV = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(KeyboardOverlay), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('holds are gated by a focused text field', (tester) async {
    final a = await pumpKeyboard(tester, child: const Column(children: [TextField()]));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(a.calls, isEmpty);
  });
}
