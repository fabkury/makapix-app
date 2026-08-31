import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/dialogs/color_picker_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // The drag/tap tests read their results from the H/S/V text fields, which are only
  // visible in HSV mode — seed the stored mode accordingly. (The chip tests override
  // this per-test.)
  setUp(() {
    SharedPreferences.setMockInitialValues({kColorPickerModePref: 'hsv'});
  });

  // The picker sizes itself from MediaQuery, so every test pins the surface to make the
  // geometry deterministic. 430×932 portrait leaves 302px inside the dialog paddings, so
  // the square caps at its 246px maximum — the same 26×246 ramp the original fixed-width
  // dialog had, keeping the numeric expectations below valid.
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host());
    await tester.pump(); // flush the stored-mode load
  }

  testWidgets('hue ramp tracks a full vertical drag under iOS bouncing physics', (tester) async {
    await pumpAt(tester, const Size(430, 932));
    final ramp = find.byKey(const Key('pickerHueRamp'));
    expect(ramp, findsOneWidget);
    // Ramp is 26×246 at this surface. Drag from its center (y=123 → hue 180°, cyan)
    // down 120 px (y=243 → hue 243/246·360 ≈ 356°). The BROKEN version kept cyan: the
    // down landed but the scrollable stole the updates.
    await tester.drag(ramp, const Offset(0, 120), warnIfMissed: false);
    await tester.pump();
    expect(find.text('00FFFF'), findsNothing, reason: 'drag updates must not be stolen');
    expect(find.text('356'), findsOneWidget, reason: 'H field shows the fully-tracked hue');
  });

  testWidgets('SV square tracks a diagonal drag under iOS bouncing physics', (tester) async {
    await pumpAt(tester, const Size(430, 932));
    final sq = find.byKey(const Key('pickerSvSquare'));
    expect(sq, findsOneWidget);
    // From the center (S=50, V=50) drag toward the top-right corner: S rises, V rises.
    await tester.drag(sq, const Offset(100, -100), warnIfMissed: false);
    await tester.pump();
    // S = (123+100)/246 ≈ 91%, V = 1 − (123−100)/246 ≈ 91% — both fields track.
    expect(find.text('91'), findsNWidgets(2), reason: 'S and V both follow the diagonal');
  });

  testWidgets('a plain tap still sets the hue immediately (the down handler)', (tester) async {
    await pumpAt(tester, const Size(430, 932));
    await tester.tapAt(tester.getCenter(find.byKey(const Key('pickerHueRamp'))));
    await tester.pump();
    expect(find.text('180'), findsOneWidget, reason: 'tap at ramp center = 180°');
  });

  testWidgets('the whole ramp is tappable at iPhone 12 portrait width', (tester) async {
    // Regression: with the fixed 280px content, a 390px-wide screen left the picker row
    // horizontally overflowed — painted but NOT hit-testable — so taps anywhere but the
    // ramp's left sliver did nothing on iOS. The row must now fit entirely on screen.
    await pumpAt(tester, const Size(390, 844));
    final rect = tester.getRect(find.byKey(const Key('pickerHueRamp')));
    expect(rect.width, 26, reason: 'the ramp keeps its full width');
    expect(rect.right, lessThan(390), reason: 'the ramp sits entirely on screen');
    await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
    await tester.pump();
    expect(find.text('180'), findsOneWidget, reason: 'a tap at the ramp right edge lands');
  });

  testWidgets('the markers keep their slack inside the scroll clip', (tester) async {
    // Both painters draw their markers slightly past the paint bounds, and the
    // scrollable clips its content once it overflows (keyboard up, tight screens).
    // The picker area must keep slack on the clipped sides so a marker sitting at an
    // extreme never loses an edge.
    await pumpAt(tester, const Size(390, 844));
    final scroll = tester.getRect(find.byType(SingleChildScrollView));
    final ramp = tester.getRect(find.byKey(const Key('pickerHueRamp')));
    final square = tester.getRect(find.byKey(const Key('pickerSvSquare')));
    // 9 = _kMarkerSlack (the SV ring: r=7 plus half its 3px stroke, rounded up).
    expect(ramp.right, lessThanOrEqualTo(scroll.right - 9));
    expect(square.left, greaterThanOrEqualTo(scroll.left + 9));
    expect(square.top, greaterThanOrEqualTo(scroll.top + 9));
  });

  group('landscape (iPhone 12: 844×390)', () {
    testWidgets('two panes: picker left, fields and buttons right, no overflow', (tester) async {
      await pumpAt(tester, const Size(844, 390));
      expect(tester.takeException(), isNull, reason: 'everything fits on screen');
      expect(find.byKey(const Key('pickerSvSquare')), findsOneWidget);
      expect(find.byKey(const Key('pickerHueRamp')), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      final square = tester.getRect(find.byKey(const Key('pickerSvSquare')));
      final hexMark = tester.getRect(find.text('#'));
      expect(hexMark.left, greaterThan(square.right),
          reason: 'the fields sit in a pane right of the picker');
      final ok = tester.getRect(find.text('OK'));
      expect(ok.bottom, greaterThan(hexMark.bottom),
          reason: 'the buttons sit at the bottom of the right pane');
    });

    testWidgets('hue drag tracks in landscape (square at its full 246)', (tester) async {
      await pumpAt(tester, const Size(844, 390));
      // availH = 390 − 48 − 28 = 314 → the square caps at 246, so the portrait drag
      // arithmetic (243/246·360 ≈ 356°) transfers verbatim.
      await tester.drag(find.byKey(const Key('pickerHueRamp')), const Offset(0, 120),
          warnIfMissed: false);
      await tester.pump();
      expect(find.text('356'), findsOneWidget, reason: 'H field shows the fully-tracked hue');
    });

    testWidgets('OK pops the picked color, Cancel pops null', (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Color? picked = const Color(0x12345678);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  picked = await showDialog<Color>(
                    context: context,
                    builder: (_) =>
                        const ColorPickerDialog(initial: Color(0xFF00FF00)),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(picked, const Color(0xFF00FF00));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(picked, isNull);
    });
  });

  group('RGB/HSV mode chips', () {
    testWidgets('defaults to RGB; the HSV chip swaps the fields and stores the mode', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await pumpAt(tester, const Size(430, 932));
      // RGB mode: the R/G/B trio shows, H/S/V does not; hex + alpha always present.
      expect(find.text('R'), findsOneWidget);
      expect(find.text('H'), findsNothing);
      expect(find.text('#'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      await tester.tap(find.text('HSV'));
      await tester.pump();
      expect(find.text('H'), findsOneWidget);
      expect(find.text('R'), findsNothing);
      expect(find.text('#'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kColorPickerModePref), 'hsv',
          reason: 'the chosen mode persists');
    });

    testWidgets('reopens in the stored mode', (tester) async {
      SharedPreferences.setMockInitialValues({kColorPickerModePref: 'hsv'});
      await pumpAt(tester, const Size(430, 932));
      expect(find.text('H'), findsOneWidget);
      expect(find.text('R'), findsNothing);
    });

    testWidgets('the chips keep breathing room above the fields', (tester) async {
      await pumpAt(tester, const Size(430, 932)); // HSV mode from setUp
      final chipBottom = tester.getRect(find.byType(ChoiceChip).first).bottom;
      final hField = find.ancestor(
        of: find.text('H'),
        matching: find.byType(TextField),
      );
      expect(tester.getRect(hField).top, greaterThanOrEqualTo(chipBottom + 8));
    });
  });

  group('keyboard dismissal (iOS)', () {
    testWidgets('numeric fields carry a keyboard with a Done key', (tester) async {
      await pumpAt(tester, const Size(430, 932)); // host theme is iOS
      final hField = find.ancestor(
        of: find.text('H'),
        matching: find.byType(TextField),
      );
      final tf = tester.widget<TextField>(hField);
      // The bare iOS number pad has no return key; signed:true selects the
      // numbers-and-punctuation keyboard, which does.
      expect(
        tf.keyboardType,
        const TextInputType.numberWithOptions(signed: true),
      );
      expect(tf.textInputAction, TextInputAction.done);
    });

    testWidgets('tapping outside a field dismisses the keyboard', (tester) async {
      await pumpAt(tester, const Size(430, 932));
      final hField = find.ancestor(
        of: find.text('H'),
        matching: find.byType(TextField),
      );
      await tester.tap(hField);
      await tester.pump();
      final editable = tester.widget<EditableText>(
        find.descendant(of: hField, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.tap(find.text('Pick color')); // the title: not interactive
      await tester.pump();
      expect(editable.focusNode.hasFocus, isFalse);
    });

    testWidgets('tapping the picker area dismisses the keyboard', (tester) async {
      await pumpAt(tester, const Size(430, 932));
      final hField = find.ancestor(
        of: find.text('H'),
        matching: find.byType(TextField),
      );
      await tester.tap(hField);
      await tester.pump();
      final editable = tester.widget<EditableText>(
        find.descendant(of: hField, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('pickerSvSquare'))),
      );
      await tester.pump();
      expect(editable.focusNode.hasFocus, isFalse);
    });
  });

  // The sources strip is the editor's primary-to-target contract: every color target opens this
  // dialog, and the dialog always offers the primary / previous primary / palette as one-tap
  // sources. A source tap sets the WORKING color and keeps the dialog open; OK commits it.
  group('sources strip', () {
    const primary = Color(0xFF123456), prev = Color(0xFF654321);
    const palette = [Color(0xFF00FF00), Color(0x80FF00FF)];
    final primaryKey = find.byKey(const Key('pickerSourcePrimary'));
    final prevKey = find.byKey(const Key('pickerSourcePrevious'));
    final paletteKey = find.byKey(const Key('pickerSourcePalette'));

    // Opens the dialog through showDialog so OK's pop value is observable.
    Future<Color? Function()> open(
      WidgetTester tester, {
      Size size = const Size(430, 932),
      Color? primary,
      Color? previous,
      List<Color> palette = const [],
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Color? picked;
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              picked = await showDialog<Color>(
                context: ctx,
                builder: (_) => ColorPickerDialog(
                  initial: const Color(0xFFFF0000),
                  primary: primary,
                  previous: previous,
                  palette: palette,
                ),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () {
        expect(closed, isTrue, reason: 'the dialog must have popped');
        return picked;
      };
    }

    testWidgets('absent when the caller passes no sources', (tester) async {
      await pumpAt(tester, const Size(430, 932));
      expect(primaryKey, findsNothing);
      expect(prevKey, findsNothing);
      expect(paletteKey, findsNothing);
    });

    testWidgets('tapping Primary adopts it, stays open, and OK returns it exactly',
        (tester) async {
      final result = await open(tester, primary: primary, previous: prev, palette: palette);
      expect(primaryKey, findsOneWidget);
      expect(find.text('FF0000'), findsOneWidget, reason: 'opens on the initial color');
      await tester.tap(primaryKey);
      await tester.pump();
      expect(find.text('123456'), findsOneWidget, reason: 'the hex field jumps to the primary');
      expect(find.text('OK'), findsOneWidget, reason: 'a source tap does not close the dialog');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result(), primary, reason: 'the round trip through HSV is exact');
    });

    testWidgets('Prev and palette swatches adopt too, alpha included', (tester) async {
      final result = await open(tester, primary: primary, previous: prev, palette: palette);
      await tester.tap(prevKey);
      await tester.pump();
      expect(find.text('654321'), findsOneWidget);
      // The palette lane: its second swatch is translucent, and the alpha comes along.
      final swatches = find.descendant(of: paletteKey, matching: find.byType(GestureDetector));
      expect(swatches, findsNWidgets(2));
      await tester.tap(swatches.at(1));
      await tester.pump();
      expect(find.text('FF00FF80'), findsOneWidget, reason: 'hex shows RRGGBBAA for alpha < 255');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result(), palette[1]);
    });

    testWidgets('picking for the primary itself withholds the Primary source only',
        (tester) async {
      await open(tester, previous: prev, palette: palette);
      expect(primaryKey, findsNothing);
      expect(prevKey, findsOneWidget);
      expect(paletteKey, findsOneWidget);
    });

    testWidgets('the strip is present in landscape as well', (tester) async {
      await open(tester, size: const Size(844, 390), primary: primary, previous: prev, palette: palette);
      expect(tester.takeException(), isNull);
      expect(primaryKey, findsOneWidget);
      await tester.tap(primaryKey);
      await tester.pump();
      expect(find.text('123456'), findsOneWidget);
    });
  });
}
