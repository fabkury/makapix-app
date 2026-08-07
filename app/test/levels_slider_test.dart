// LevelsSlider drag behavior — pumped standalone, no engine binary.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/levels_math.dart';
import 'package:makapix_club/editor/widgets/painters.dart';

void main() {
  // A stateful host so onChanged feeds back into the widget like the editor page does.
  Widget host(ValueNotifier<(int, int, int)> v, {VoidCallback? onEnd}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<(int, int, int)>(
              valueListenable: v,
              builder: (_, t, _) => LevelsSlider(
                low: t.$1,
                gammaTh: t.$2,
                high: t.$3,
                onChanged: (lo, g, hi) => v.value = (lo, g, hi),
                onChangeEnd: onEnd,
              ),
            ),
          ),
        ),
      );

  // Track-x of a level value in the slider's local space (default 240-wide widget).
  double xOf(WidgetTester tester, int value) {
    final r = tester.getRect(find.byType(LevelsSlider));
    return r.left + LevelsSlider.pad + levelsThumbX(value, r.width - 2 * LevelsSlider.pad);
  }

  double yOf(WidgetTester tester) => tester.getRect(find.byType(LevelsSlider)).center.dy;

  testWidgets('dragging the low thumb raises low and clamps under high', (tester) async {
    final v = ValueNotifier((0, 1000, 255));
    await tester.pumpWidget(host(v));
    await tester.dragFrom(Offset(xOf(tester, 0), yOf(tester)), const Offset(60, 0));
    await tester.pump();
    expect(v.value.$1, greaterThan(0));
    expect(v.value.$1, lessThan(v.value.$3));
    expect(v.value.$2, 1000, reason: 'low drag preserves gamma');
    expect(v.value.$3, 255);
    // And a huge drag can never push low past high-1.
    await tester.dragFrom(Offset(xOf(tester, v.value.$1), yOf(tester)), const Offset(500, 0));
    await tester.pump();
    expect(v.value.$1, v.value.$3 - 1);
  });

  testWidgets('dragging the high thumb lowers high and clamps above low', (tester) async {
    final v = ValueNotifier((0, 1000, 255));
    await tester.pumpWidget(host(v));
    await tester.dragFrom(Offset(xOf(tester, 255), yOf(tester)), const Offset(-60, 0));
    await tester.pump();
    expect(v.value.$3, lessThan(255));
    expect(v.value.$3, greaterThan(v.value.$1));
    expect(v.value.$1, 0);
    await tester.dragFrom(Offset(xOf(tester, v.value.$3), yOf(tester)), const Offset(-500, 0));
    await tester.pump();
    expect(v.value.$3, v.value.$1 + 1);
  });

  testWidgets('dragging the mid thumb changes gamma in the GIMP direction', (tester) async {
    final v = ValueNotifier((0, 1000, 255));
    await tester.pumpWidget(host(v));
    // Mid sits at the span center for gamma 1; toward low -> gamma above 1 (brighten).
    await tester.dragFrom(Offset(xOf(tester, 128), yOf(tester)), const Offset(-50, 0));
    await tester.pump();
    expect(v.value.$2, greaterThan(1000));
    expect(v.value.$1, 0);
    expect(v.value.$3, 255);
    // And back past center -> below 1 (darken).
    final midX = xOf(tester, 0) +
        (xOf(tester, 255) - xOf(tester, 0)) * levelsMidFromGamma(v.value.$2 / 1000);
    await tester.dragFrom(Offset(midX, yOf(tester)), const Offset(120, 0));
    await tester.pump();
    expect(v.value.$2, lessThan(1000));
  });

  testWidgets('a plain tap never jumps a thumb, a drag end reports once', (tester) async {
    final v = ValueNotifier((0, 1000, 255));
    var ends = 0;
    await tester.pumpWidget(host(v, onEnd: () => ends++));
    await tester.tapAt(Offset(xOf(tester, 64), yOf(tester)));
    await tester.pump();
    expect(v.value, (0, 1000, 255));
    await tester.dragFrom(Offset(xOf(tester, 0), yOf(tester)), const Offset(40, 0));
    await tester.pump();
    expect(ends, 1);
  });
}
