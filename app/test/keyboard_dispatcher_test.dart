// EditorKeyboard dispatcher: chord matching, modality gating, repeat suppression, and the
// Enter/Esc priority pairs — driven entirely through a FakeEditorAccess and simulated key
// events (no engine, per the repo's Dart-test contract).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      // Pressing Alt springs the hold-pick around each Alt chord — by design, the chord
      // still fires while the temporary Eyedropper is up.
      'beginHoldPick', 'moveLayer:1', 'endHoldPick',
      'beginHoldPick', 'moveLayer:-1', 'endHoldPick',
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

  testWidgets('hold-Alt springs the Eyedropper and restores on release', (tester) async {
    final a = await pumpKeyboard(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(a.calls, ['beginHoldPick', 'endHoldPick']);
  });

  testWidgets('hold-Alt never fires mid-draft or mid-drag', (tester) async {
    final a = await pumpKeyboard(tester);
    a.hasAnyDraftV = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    a
      ..hasAnyDraftV = false
      ..pointerActiveV = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(a.calls, isEmpty);
  });

  testWidgets('backgrounding force-releases holds; the late keyUp is inert', (tester) async {
    final a = await pumpKeyboard(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    expect(a.calls, ['setSpacePan:true', 'beginHoldPick']);
    a.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(a.calls, ['setSpacePan:false', 'endHoldPick']);
    a.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
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

  testWidgets('holds are gated by a focused text field', (tester) async {
    final a = await pumpKeyboard(tester, child: const Column(children: [TextField()]));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(a.calls, isEmpty);
  });
}
