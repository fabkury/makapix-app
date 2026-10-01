// T4 sweeps: the keyboard shortcuts page, the Replay page, and the two-tap Delete button —
// batches E6 and E7. All on fakes: no engine. (The timelapse dialogs open from inside the
// editor; test_engine/editor_chrome_test.dart walks to them.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/keyboard/cheat_sheet.dart';
import 'package:makapix_club/editor/keyboard/commands.dart';
import 'package:makapix_club/editor/keyboard/default_bindings.dart';
import 'package:makapix_club/editor/replay/journal_format.dart';
import 'package:makapix_club/editor/replay/replay_page.dart';
import 'package:makapix_club/editor/tap_again.dart';
import 'package:makapix_club/l10n/l10n.dart';

import '../replay_page_test.dart' show FakeReplayHost;
import 'sweep.dart';

/// Key legends that are Latin on every keyboard (the Russian, Japanese, and Chinese ones too).
const _keys = ['Ctrl', 'Alt', 'Shift', 'Enter', 'Esc', 'Backspace', 'Delete', 'Tab'];

/// A key shown by its letter: "W" is a key here, not the English label of the canvas width.
final _oneKey = RegExp(r'^[A-Z0-9]$');

/// A drawing title the artist typed.
const _title = 'Sunset';

Future<void> _pauseReplay(WidgetTester tester) async {
  await settleOpen(tester); // the host reports ready a frame or two after the mount
  expect(find.byIcon(Icons.pause), findsOneWidget, reason: 'the replay starts playing');
  await tester.tap(find.byIcon(Icons.pause)); // stop the sweep timer
  await tester.pump();
}

void main() {
  sweepScreen(
    'Keyboard shortcuts',
    build: () => KeyboardCheatSheetPage(commands: buildCommands(), bindings: defaultBindings()),
    allowLatin: _keys,
    allowEnglish: [_oneKey],
  );
  sweepScreen(
    'Keyboard shortcuts, end',
    build: () => KeyboardCheatSheetPage(commands: buildCommands(), bindings: defaultBindings()),
    allowLatin: _keys,
    allowEnglish: [_oneKey],
    act: (tester) async {
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -5000));
    },
  );

  sweepScreen(
    'Replay page',
    build: () => ReplayPage(host: FakeReplayHost(actions: 100), title: _title, onShareTimelapse: () {}),
    allowLatin: const [_title],
    act: _pauseReplay,
    drain: const Duration(seconds: 2),
  );
  sweepScreen(
    'Replay page, older recording',
    build: () => ReplayPage(
        host: FakeReplayHost(actions: 100, epoch: kJournalEpoch - 1), title: _title, onShareTimelapse: () {}),
    allowLatin: const [_title],
    // The title is the artist's words: beside the chip, two lines may not hold all of it.
    allowTruncated: const [_title],
    act: (tester) async {
      await _pauseReplay(tester);
      // The chip's explanation (the one tooltip on the page that opens on a tap).
      await tester.tap(
          find.byWidgetPredicate((w) => w is Tooltip && w.triggerMode == TooltipTriggerMode.tap));
    },
    drain: const Duration(seconds: 3),
  );
  sweepScreen(
    'Replay page, nothing recorded',
    build: () => Builder(
      builder: (context) =>
          ReplayPage(host: FakeReplayHost(failWith: context.l10n.replayNoHistory), title: _title),
    ),
    allowLatin: const [_title],
  );
  sweepScreen(
    'Replay page, a part is missing',
    build: () => Builder(
      builder: (context) =>
          ReplayPage(host: FakeReplayHost(failWith: context.l10n.replayMissingPart), title: _title),
    ),
    allowLatin: const [_title],
  );

  sweepScreen(
    'Two-tap Delete, armed',
    build: () => Builder(
      builder: (context) => Scaffold(
        body: Center(child: TapAgainDeleteButton(label: context.l10n.layerDelete, onConfirmed: () {})),
      ),
    ),
    act: (tester) async {
      await tester.tap(find.byType(TapAgainDeleteButton));
    },
    drain: const Duration(seconds: 5),
  );
}
