import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/replay/action_runner.dart';

/// A fake engine `run`: rejects exact lines in [bad] with the engine's real error shape
/// (`line N: unknown action '…' [line]`), executing (recording) every line before the failure —
/// mirroring `Session::run_script`, which runs statements up to the first bad parse.
class _FakeEngine {
  _FakeEngine(this.bad);
  final Set<String> bad;
  final List<String> executed = [];
  final List<String> scripts = [];

  String? run(String script) {
    scripts.add(script);
    final lines = script.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (bad.contains(lines[i])) {
        return "line ${i + 1}: unknown action '${lines[i]}' [${lines[i]}]";
      }
      executed.add(lines[i]);
    }
    return null;
  }
}

void main() {
  test('clean batch runs once, skips nothing', () {
    final e = _FakeEngine({});
    final skipped = runActionsSkippingBad(e.run, ['A()', 'B()', 'C()'], 0, 3);
    expect(skipped, 0);
    expect(e.executed, ['A()', 'B()', 'C()']);
    expect(e.scripts.length, 1);
  });

  test('an unknown verb drops only its own line and resumes after it', () {
    final e = _FakeEngine({'SetAA(true)'});
    final actions = ['A()', 'B()', 'SetAA(true)', 'C()', 'D()'];
    final messages = <String>[];
    final skipped = runActionsSkippingBad(e.run, actions, 0, 5, onSkip: messages.add);
    expect(skipped, 1);
    // Everything except the offender executed, in order, exactly once (never re-applied).
    expect(e.executed, ['A()', 'B()', 'C()', 'D()']);
    expect(messages.single, contains('skipping action 2'));
  });

  test('multiple bad lines each cost exactly one line', () {
    final e = _FakeEngine({'X()', 'Y()'});
    final actions = ['A()', 'X()', 'B()', 'Y()', 'C()'];
    final skipped = runActionsSkippingBad(e.run, actions, 0, 5);
    expect(skipped, 2);
    expect(e.executed, ['A()', 'B()', 'C()']);
  });

  test('a bad first line of the batch is skipped', () {
    final e = _FakeEngine({'X()'});
    final skipped = runActionsSkippingBad(e.run, ['X()', 'A()'], 0, 2);
    expect(skipped, 1);
    expect(e.executed, ['A()']);
  });

  test('a bad last line ends the batch cleanly', () {
    final e = _FakeEngine({'X()'});
    final skipped = runActionsSkippingBad(e.run, ['A()', 'X()'], 0, 2);
    expect(skipped, 1);
    expect(e.executed, ['A()']);
  });

  test('the [from, to) window is respected', () {
    final e = _FakeEngine({'X()'});
    final actions = ['OUT()', 'A()', 'X()', 'B()', 'OUT()'];
    final skipped = runActionsSkippingBad(e.run, actions, 1, 4);
    expect(skipped, 1);
    expect(e.executed, ['A()', 'B()']);
  });

  test('an error without a line number abandons the batch remainder (pre-fix behavior)', () {
    var calls = 0;
    String? run(String script) {
      calls++;
      return 'something went wrong';
    }

    final messages = <String>[];
    final skipped = runActionsSkippingBad(run, ['A()', 'B()'], 0, 2, onSkip: messages.add);
    expect(skipped, 0);
    expect(calls, 1, reason: 'no retry loop on an unmappable error');
    expect(messages.single, contains('unrecoverable'));
  });

  test('an out-of-range line number abandons the batch instead of looping', () {
    String? run(String script) => 'line 99: bogus [bogus]';
    final skipped = runActionsSkippingBad(run, ['A()', 'B()'], 0, 2);
    expect(skipped, 0);
  });
}
