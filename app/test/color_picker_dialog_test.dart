import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/dialogs/color_picker_dialog.dart';

void main() {
  // Regression (iPhone 12 TestFlight report): the picker's content sits in a
  // SingleChildScrollView, and under iOS BOUNCING scroll physics the scrollable accepts
  // vertical drags even at zero scroll extent — with pan recognizers, every vertical drag
  // on the hue ramp was stolen mid-gesture (the initial down landed, then tracking died).
  // The per-axis recognizers must win the arena and track the WHOLE drag.
  Widget host() => MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS), // bouncing physics = the thief
        home: const Material(child: ColorPickerDialog(initial: Color(0xFFFF0000))),
      );

  testWidgets('hue ramp tracks a full vertical drag under iOS bouncing physics', (tester) async {
    await tester.pumpWidget(host());
    final ramp = find.byKey(const Key('pickerHueRamp'));
    expect(ramp, findsOneWidget);
    // Ramp is 26×246 (sq = 280 − 8 − 26). Drag from its center (y=123 → hue 180°, cyan)
    // down 120 px (y=243 → hue 243/246·360 ≈ 356°). The BROKEN version kept cyan: the
    // down landed but the scrollable stole the updates.
    await tester.drag(ramp, const Offset(0, 120), warnIfMissed: false);
    await tester.pump();
    expect(find.text('00FFFF'), findsNothing, reason: 'drag updates must not be stolen');
    expect(find.text('356'), findsOneWidget, reason: 'H field shows the fully-tracked hue');
  });

  testWidgets('SV square tracks a diagonal drag under iOS bouncing physics', (tester) async {
    await tester.pumpWidget(host());
    final sq = find.byKey(const Key('pickerSvSquare'));
    expect(sq, findsOneWidget);
    // From the center (S=50, V=50) drag toward the top-right corner: S rises, V rises.
    await tester.drag(sq, const Offset(100, -100), warnIfMissed: false);
    await tester.pump();
    // S = (123+100)/246 ≈ 91%, V = 1 − (123−100)/246 ≈ 91% — both fields track.
    expect(find.text('91'), findsNWidgets(2), reason: 'S and V both follow the diagonal');
  });

  testWidgets('a plain tap still sets the hue immediately (the down handler)', (tester) async {
    await tester.pumpWidget(host());
    await tester.tapAt(tester.getCenter(find.byKey(const Key('pickerHueRamp'))));
    await tester.pump();
    expect(find.text('180'), findsOneWidget, reason: 'tap at ramp center = 180°');
  });
}
