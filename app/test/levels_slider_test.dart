// LevelsSlider drag behavior — pumped standalone, no engine binary.
//
// Most tests use gearRatio 1 so drag offsets translate directly into thumb travel; the
// gearing test compares 1x against the geared default explicitly. Drags start on a thumb
// (inside its +-16 grab band) unless the test is about the inert gradient.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/levels_math.dart';
import 'package:makapix_club/editor/widgets/painters.dart';

void main() {
  // A stateful host so onChanged feeds back into the widget like the editor page does.
  Widget host(ValueNotifier<(int, int, int)> v, {double gearRatio = 1, VoidCallback? onEnd}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<(int, int, int)>(
              valueListenable: v,
              builder: (_, t, _) => LevelsSlider(
                low: t.$1,
                gammaTh: t.$2,
                high: t.$3,
                gearRatio: gearRatio,
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

  testWidgets('gearing divides pointer travel (house 6x default)', (tester) async {
    final direct = ValueNotifier((0, 1000, 255));
    await tester.pumpWidget(host(direct, gearRatio: 1));
    await tester.dragFrom(Offset(xOf(tester, 0), yOf(tester)), const Offset(120, 0));
    await tester.pump();
    final ungeared = direct.value.$1;

    final geared = ValueNotifier((0, 1000, 255));
    await tester.pumpWidget(host(geared, gearRatio: 6));
    await tester.dragFrom(Offset(xOf(tester, 0), yOf(tester)), const Offset(120, 0));
    await tester.pump();
    expect(geared.value.$1, greaterThan(0));
    expect(geared.value.$1, lessThan(ungeared ~/ 3),
        reason: 'the same travel moves the geared thumb ~6x less');
  });

  testWidgets('a pan starting on the bare gradient does nothing', (tester) async {
    final v = ValueNotifier((0, 1000, 255));
    var ends = 0;
    await tester.pumpWidget(host(v, onEnd: () => ends++));
    // Value 64 sits mid-gradient: ~56px from the low thumb, ~56px from the mid thumb —
    // outside every +-16 grab band.
    await tester.dragFrom(Offset(xOf(tester, 64), yOf(tester)), const Offset(60, 0));
    await tester.pump();
    expect(v.value, (0, 1000, 255));
    expect(ends, 0);
  });

  testWidgets('a plain tap never jumps a thumb, a drag end reports once', (tester) async {
    final v = ValueNotifier((0, 1000, 255));
    var ends = 0;
    await tester.pumpWidget(host(v, onEnd: () => ends++));
    await tester.tapAt(Offset(xOf(tester, 0), yOf(tester))); // directly ON the low thumb
    await tester.pump();
    expect(v.value, (0, 1000, 255));
    expect(ends, 0);
    await tester.dragFrom(Offset(xOf(tester, 0), yOf(tester)), const Offset(40, 0));
    await tester.pump();
    expect(ends, 1);
  });

  testWidgets('a thumb drag beats an overflowing horizontal scroll row (the row-1 arena)',
      (tester) async {
    // Regression: with pan callbacks the scrollable's horizontal-drag recognizer (smaller
    // slop) always won the gesture arena once row-1 overflowed — thumbs went dead and drags
    // scrolled the row. The slider must use a horizontal-drag recognizer so the innermost
    // one wins. Reproduce row-1: a horizontally scrolling row wider than the screen.
    final v = ValueNotifier((0, 1000, 255));
    final scroll = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 48,
          child: SingleChildScrollView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ValueListenableBuilder<(int, int, int)>(
                valueListenable: v,
                builder: (_, t, _) => LevelsSlider(
                  low: t.$1,
                  gammaTh: t.$2,
                  high: t.$3,
                  gearRatio: 1,
                  onChanged: (lo, g, hi) => v.value = (lo, g, hi),
                ),
              ),
              const SizedBox(width: 2000), // force overflow so the scrollable arms
            ]),
          ),
        ),
      ),
    ));
    expect(scroll.position.maxScrollExtent, greaterThan(0), reason: 'the row must overflow');
    await tester.dragFrom(Offset(xOf(tester, 0), yOf(tester)), const Offset(60, 0));
    await tester.pump();
    expect(v.value.$1, greaterThan(0), reason: 'the thumb moved');
    expect(scroll.offset, 0, reason: 'the row did not scroll');
  });
}
