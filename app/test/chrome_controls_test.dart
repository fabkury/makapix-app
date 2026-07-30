// The lifted shared chrome (lib/ui/chrome_controls.dart + chrome_sheets.dart): the geared
// slider's gearing math, the tap-to-type label dialog, toggle dispatch, and the sheet
// scaffold. These guard the P0 lift (2026-07-30) — the editor's behavior sentinels are its
// own tests; this file pins the extracted pieces directly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/ui/chrome_controls.dart';
import 'package:makapix_club/ui/chrome_sheets.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('GearedSlider divides pointer travel by the gear ratio', (tester) async {
    double value = 50;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (_, setState) => SizedBox(
        width: 120,
        child: GearedSlider(
            value: value, min: 0, max: 100, onChanged: (v) => setState(() => value = v)),
      ),
    )));

    // Track width = 120 - 48 (Material thumb-overlay insets). A 72 px drag ungeared would
    // traverse the full range; geared it moves range · 72 / ratio / 72 = 100 / 6 ≈ 16.67.
    await tester.drag(find.byType(GearedSlider), const Offset(72, 0));
    await tester.pump();
    expect(value, closeTo(50 + 100 / kSliderGearRatio, 0.5));
  });

  testWidgets('labeledSlider label opens the type-a-value dialog and clamps', (tester) async {
    double value = 10;
    await tester.pumpWidget(host(Builder(builder: (ctx) {
      final children = <Widget>[];
      labeledSlider(ctx, children, 'Size', value, 1, 64, (v) => value = v);
      expect(children, hasLength(2)); // label + slider
      return Row(mainAxisSize: MainAxisSize.min, children: children);
    })));
    expect(find.text('Size 10'), findsOneWidget);
    await tester.tap(find.text('Size 10'));
    await tester.pumpAndSettle();
    expect(find.text('Value (1 – 64)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '999');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(value, 64); // clamped to max
  });

  testWidgets('chromeToggle fires the tapped index', (tester) async {
    int? tapped;
    await tester
        .pumpWidget(host(chromeToggle(const ['A', 'B', 'C'], 0, (i) => tapped = i)));
    await tester.tap(find.text('C'));
    expect(tapped, 2);
  });

  testWidgets('sheetScaffold hosts children; stateChip toggles', (tester) async {
    bool on = false;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (_, setState) => sheetScaffold([
        sheetSection('zone'),
        stateChip(
            icon: Icons.visibility,
            label: 'Visible',
            value: on,
            onChanged: (v) => setState(() => on = v)),
        sheetBtnRow([sheetBtn(Icons.copy, 'Copy', () {}), sheetBtn(Icons.add, 'Add', () {})]),
        sheetDelete('Delete', () {}),
      ]),
    )));
    expect(find.text('ZONE'), findsOneWidget); // sheetSection upper-cases
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Visible'));
    await tester.pump();
    expect(on, isTrue);
  });
}
