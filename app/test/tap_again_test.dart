// Second-tap confirmation (ADR 0022): the arm state machine and the sheet's delete button. Runs
// under flutter_test's fake clock (tester.pump advances the arm's Timer) — no engine, no network.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/tap_again.dart';

void main() {
  group('TapAgainArm', () {
    testWidgets('first tap arms, second tap within the window confirms', (tester) async {
      final changes = <bool>[];
      final arm = TapAgainArm(onChanged: () => changes.add(true));
      expect(arm.tap(3), isFalse);
      expect(arm.armed, isTrue);
      expect(arm.armedKey, 3);
      await tester.pump(const Duration(seconds: 2));
      expect(arm.tap(3), isTrue, reason: 'confirm inside the window');
      expect(arm.armed, isFalse);
      expect(changes.length, 2, reason: 'arm + confirm each notify');
      arm.dispose();
    });

    testWidgets('the window expires silently and the next tap only re-arms', (tester) async {
      final arm = TapAgainArm();
      arm.tap('frame');
      await tester.pump(kTapAgainWindow);
      expect(arm.armed, isFalse, reason: 'expired');
      expect(arm.tap('frame'), isFalse, reason: 'a fresh first tap, not a confirm');
      arm.dispose();
    });

    testWidgets('a different key re-arms instead of confirming', (tester) async {
      final arm = TapAgainArm();
      arm.tap(1);
      expect(arm.tap(2), isFalse, reason: 'retargeted: must not delete frame 2 on one tap');
      expect(arm.armedKey, 2);
      expect(arm.tap(2), isTrue);
      arm.dispose();
    });

    testWidgets('disarm resets; re-tapping after disarm is a first tap', (tester) async {
      var notified = 0;
      final arm = TapAgainArm(onChanged: () => notified++);
      arm.tap(0);
      arm.disarm();
      expect(arm.armed, isFalse);
      expect(notified, 2);
      arm.disarm(); // no-op when idle
      expect(notified, 2);
      expect(arm.tap(0), isFalse);
      arm.dispose();
    });

    testWidgets('the window restarts on a re-arm', (tester) async {
      final arm = TapAgainArm();
      arm.tap('a');
      await tester.pump(const Duration(seconds: 2));
      arm.tap('b'); // re-arm for a new target restarts the clock
      await tester.pump(const Duration(seconds: 2));
      expect(arm.armed, isTrue, reason: 'only 2 s into the new window');
      await tester.pump(const Duration(seconds: 1));
      expect(arm.armed, isFalse);
      arm.dispose();
    });
  });

  group('TapAgainDeleteButton', () {
    Future<void> pumpButton(WidgetTester tester, {required VoidCallback? onConfirmed, Object? armKey}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TapAgainDeleteButton(label: 'Delete frame', onConfirmed: onConfirmed, armKey: armKey),
        ),
      ));
    }

    testWidgets('one tap relabels, the second within 3 s confirms exactly once', (tester) async {
      var fired = 0;
      await pumpButton(tester, onConfirmed: () => fired++, armKey: 0);
      expect(find.text('Delete frame'), findsOneWidget);
      await tester.tap(find.text('Delete frame'));
      await tester.pump();
      expect(find.text(TapAgainDeleteButton.armedLabel), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget, reason: 'armed look is the filled red button');
      expect(fired, 0);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text(TapAgainDeleteButton.armedLabel));
      await tester.pump();
      expect(fired, 1);
      expect(find.text('Delete frame'), findsOneWidget, reason: 'back to resting after the confirm');
    });

    testWidgets('an unanswered arm reverts after 3 s without firing', (tester) async {
      var fired = 0;
      await pumpButton(tester, onConfirmed: () => fired++, armKey: 0);
      await tester.tap(find.text('Delete frame'));
      await tester.pump();
      expect(find.text(TapAgainDeleteButton.armedLabel), findsOneWidget);
      await tester.pump(kTapAgainWindow);
      expect(find.text('Delete frame'), findsOneWidget);
      expect(fired, 0);
    });

    testWidgets('a changed armKey (retarget or other sheet action) disarms', (tester) async {
      var fired = 0;
      await pumpButton(tester, onConfirmed: () => fired++, armKey: (2, 10));
      await tester.tap(find.text('Delete frame'));
      await tester.pump();
      expect(find.text(TapAgainDeleteButton.armedLabel), findsOneWidget);
      await pumpButton(tester, onConfirmed: () => fired++, armKey: (2, 11)); // engine traffic bumped
      expect(find.text('Delete frame'), findsOneWidget);
      await tester.tap(find.text('Delete frame'));
      await tester.pump();
      expect(fired, 0, reason: 'that tap only re-armed');
    });

    testWidgets('a disabled button neither arms nor fires', (tester) async {
      await pumpButton(tester, onConfirmed: null, armKey: 0);
      await tester.tap(find.text('Delete frame'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Delete frame'), findsOneWidget);
      expect(find.text(TapAgainDeleteButton.armedLabel), findsNothing);
    });

    testWidgets('unmounting while armed cancels the timer cleanly', (tester) async {
      await pumpButton(tester, onConfirmed: () {}, armKey: 0);
      await tester.tap(find.text('Delete frame'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(kTapAgainWindow); // no pending-timer or setState-after-dispose failure
    });
  });
}
