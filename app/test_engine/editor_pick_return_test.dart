// The Color picker's Return chip on the REAL editor (user request, 2026-11-23): after a pick
// the editor goes back to the last paint tool, so the picked color can be used at once. The
// chip is on by default, lives in the picker's options row, and is remembered.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makapix_club/editor/widgets/tool_tile.dart';

import 'editor_harness.dart';

Finder _tile(String dsl) => find.byWidgetPredicate((w) => w is ToolTile && w.tool.dsl == dsl);
final _chip = find.byKey(const ValueKey('pick-return-chip'));

/// A point well inside the canvas area of the 412 × 915 portrait layout.
const _onCanvas = Offset(206, 300);

Future<void> _select(WidgetTester tester, String dsl) async {
  await tester.ensureVisible(_tile(dsl).first);
  await tester.pump();
  await tester.tap(_tile(dsl).first);
  await settleReal(tester, rounds: 2);
}

bool _selected(WidgetTester tester, String dsl) => tester.widget<ToolTile>(_tile(dsl).first).selected;

void main() {
  testWidgets('a pick returns to the last paint tool, and the chip turns that off', (tester) async {
    await pumpEditor(tester, const Locale('en'));

    // Brush, then the picker. The editor accepts no canvas input until its drawing is restored
    // (ADR 0014), silently, so the first pick is retried until it lands.
    await _select(tester, 'Brush');
    await _select(tester, 'Eyedropper');
    expect(tester.widget<FilterChip>(_chip).selected, isTrue, reason: 'Return is on by default');
    for (var i = 0; i < 40 && !_selected(tester, 'Brush'); i++) {
      await tester.tapAt(_onCanvas);
      await settleReal(tester, rounds: 3);
    }
    expect(_selected(tester, 'Brush'), isTrue, reason: 'the pick did not return to the Brush');

    // A drag keeps sampling; the return waits for the finger to lift.
    await _select(tester, 'Eyedropper');
    final g = await tester.startGesture(_onCanvas);
    await tester.pump(const Duration(milliseconds: 30));
    await g.moveBy(const Offset(30, 20));
    await tester.pump(const Duration(milliseconds: 30));
    expect(_selected(tester, 'Eyedropper'), isTrue, reason: 'returned before the finger lifted');
    await g.up();
    await settleReal(tester, rounds: 2);
    expect(_selected(tester, 'Brush'), isTrue);

    // From a tool that cannot use a color, the pick still returns to the last PAINT tool.
    await _select(tester, 'Eraser');
    await _select(tester, 'Eyedropper');
    await tester.tapAt(_onCanvas);
    await settleReal(tester, rounds: 2);
    expect(_selected(tester, 'Brush'), isTrue, reason: 'the Eraser is not a paint tool');

    // Chip off: the picker stays, and the choice is saved.
    await _select(tester, 'Eyedropper');
    await tester.ensureVisible(_chip);
    await tester.pump();
    await tester.tap(_chip);
    await settleReal(tester, rounds: 2);
    expect(tester.widget<FilterChip>(_chip).selected, isFalse);
    await tester.tapAt(_onCanvas);
    await settleReal(tester, rounds: 2);
    expect(_selected(tester, 'Eyedropper'), isTrue, reason: 'Return is off: the picker stays');
    expect((await SharedPreferences.getInstance()).getBool('editor.pickReturn_v1'), isFalse);

    await closeEditor(tester);
  });

  testWidgets('a saved "off" is restored', (tester) async {
    await pumpEditor(tester, const Locale('en'), prefs: {'editor.pickReturn_v1': false});
    await _select(tester, 'Eyedropper');
    expect(tester.widget<FilterChip>(_chip).selected, isFalse);
    await closeEditor(tester);
  });
}
