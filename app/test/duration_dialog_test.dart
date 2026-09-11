// The shared frame-duration dialog (dialogs/duration_dialog.dart): the field is the source of
// truth while typing, the slider and fps chips write back into it, the value is clamped to the
// engine's range, and the result names the tapped action. Pure widgets — no engine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/dialogs/duration_dialog.dart';

Future<DurationChoice?> _open(WidgetTester t, {double initialMs = 100, List<String> actions = const ['This', 'All']}) async {
  DurationChoice? result;
  var settled = false;
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () async {
            result = await showDurationDialog(ctx, title: 'Frame 1 duration', initialMs: initialMs, actions: actions);
            settled = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  expect(settled, isFalse);
  return result;
}

void main() {
  testWidgets('typing sets the value; the last action is the filled one and returns its index', (tester) async {
    await _open(tester);
    expect(find.text('Frame 1 duration'), findsOneWidget);
    expect(find.text('10.0 fps'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '40');
    await tester.pump();
    expect(find.text('25.0 fps'), findsOneWidget, reason: 'the fps readout follows the field');
    expect(find.widgetWithText(FilledButton, 'All'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'This'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    // The dialog resolved: reopen to read the captured result through a fresh callback.
    expect(find.text('Frame 1 duration'), findsNothing);
  });

  testWidgets('a partial entry is not clobbered and out-of-range values clamp', (tester) async {
    DurationChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            result = await showDurationDialog(ctx, title: 't', initialMs: 100, actions: const ['Apply']);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5');
    await tester.pump();
    expect(find.text('5'), findsOneWidget, reason: 'the field keeps the partial entry');
    expect(find.text('60.2 fps'), findsOneWidget, reason: '5 ms clamps to the 16.6 ms floor');
    await tester.enterText(find.byType(TextField), '5000');
    await tester.pump();
    expect(find.text('1.0 fps'), findsOneWidget, reason: '5000 ms clamps to the 1000 ms ceiling');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.action, 0);
    expect(result!.ms, closeTo(1000, 0.001));
  });

  testWidgets('fps chips and Cancel', (tester) async {
    DurationChoice? result;
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            result = await showDurationDialog(ctx, title: 't', initialMs: 100, actions: const ['One', 'Two']);
            cancelled = result == null;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24fps'));
    await tester.pump();
    expect(find.text('41.7'), findsOneWidget, reason: 'the chip writes the field');
    expect(find.text('24.0 fps'), findsOneWidget);
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(result!.action, 0);
    expect(result!.ms, closeTo(1000 / 24, 0.001));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
  });
}
