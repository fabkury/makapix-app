// The Patterns page (ADR 0025): Off first, the recents strip (order, hidden when empty), the
// catalog sections, tap-selects-and-pops with the tile, Off pops PatternOff, the selected state,
// and the Gradient's "Dither" variant (three Bayer sizes + Off, popping an int). No engine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/patterns/pattern_tile.dart';
import 'package:makapix_club/editor/patterns/patterns_catalog.dart';
import 'package:makapix_club/editor/patterns/patterns_page.dart';

/// Pushes [page] over a base route and returns a closure yielding what it popped.
Future<Future<T?> Function()> _open<T>(WidgetTester t, Widget page) async {
  T? popped;
  var done = false;
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () async {
            popped = await Navigator.of(ctx).push<T>(MaterialPageRoute(builder: (_) => page));
            done = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return () async {
    expect(done, isTrue, reason: 'the page has popped');
    return popped;
  };
}

Finder _boxWith(PatternTile tile) => find.byWidgetPredicate((w) => w is PatternTileBox && w.tile == tile);

void main() {
  final checker = PatternTile.rows(['#.', '.#'])!;
  final lines = PatternTile.rows(['#', '.'])!;

  testWidgets('Off comes first, tapping it pops PatternOff', (t) async {
    final result = await _open<PatternPick>(t, PatternsPage(primary: Colors.red, toolName: 'Pencil', current: checker, on: true));
    expect(find.text('Patterns'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Recent'), findsNothing, reason: 'no recents → no strip');
    // The first ListTile is Off.
    final firstTile = t.widget<ListTile>(find.byType(ListTile).first);
    expect((firstTile.title as Text).data, 'Off');
    await t.tap(find.text('Off'));
    await t.pumpAndSettle();
    expect(await result(), isA<PatternOff>());
  });

  testWidgets('tapping a catalog tile pops it; the current tile shows selected only while On', (t) async {
    final result = await _open<PatternPick>(t, PatternsPage(primary: Colors.red, toolName: 'Brush', current: checker, on: true));
    final selected = t.widget<PatternTileBox>(_boxWith(checker).first);
    expect(selected.selected, isTrue);
    final other = bayerTile(2, 1); // in the first section, so it is built without scrolling
    expect(t.widget<PatternTileBox>(_boxWith(other).first).selected, isFalse);
    await t.tap(_boxWith(other).first);
    await t.pumpAndSettle();
    final pick = await result();
    expect(pick, isA<PatternChosen>());
    expect((pick as PatternChosen).tile, other);
  });

  testWidgets('with the tool Off nothing is selected even though a current tile exists', (t) async {
    await _open<PatternPick>(t, PatternsPage(primary: Colors.red, toolName: 'Eraser', current: checker, on: false));
    expect(t.widget<PatternTileBox>(_boxWith(checker).first).selected, isFalse);
    expect(find.byIcon(Icons.check), findsOneWidget, reason: 'the Off card carries the check');
  });

  testWidgets('the recents strip lists tiles most-recent-first ahead of the catalog', (t) async {
    final custom = PatternTile.parse('7,3,1')!; // not in the catalog → "Custom" in the tooltip
    await _open<PatternPick>(t, PatternsPage(primary: Colors.red, toolName: 'Bucket', recents: [custom, lines]));
    expect(find.text('Recent'), findsOneWidget);
    final boxes = t.widgetList<PatternTileBox>(find.byType(PatternTileBox)).toList();
    expect(boxes[0].tile, custom);
    expect(boxes[1].tile, lines);
    expect(_boxWith(custom), findsOneWidget, reason: 'a custom tile appears only in the strip');
    expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('Custom')), findsOneWidget);
  });

  testWidgets('every catalog family is a section', (t) async {
    await _open<PatternPick>(t, const PatternsPage(primary: Colors.red, toolName: 'Pencil'));
    for (final f in patternCatalog) {
      await t.scrollUntilVisible(find.text(f.name), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text(f.name), findsOneWidget);
    }
  });

  testWidgets('the Gradient variant offers Off and the three Bayer sizes and pops an int', (t) async {
    final result = await _open<int>(t, const PatternsPage.gradient(primary: Colors.red, dither: 4));
    expect(find.text('Dither'), findsOneWidget);
    expect(find.text('Bayer 2×2'), findsOneWidget);
    expect(find.text('Bayer 4×4'), findsOneWidget);
    expect(find.text('Bayer 8×8'), findsOneWidget);
    expect(t.widget<ListTile>(find.widgetWithText(ListTile, 'Bayer 4×4')).selected, isTrue);
    expect(find.text('Lines'), findsNothing, reason: 'the mask catalog is not offered');
    await t.tap(find.text('Bayer 8×8'));
    await t.pumpAndSettle();
    expect(await result(), 8);
  });

  testWidgets('the Gradient variant: Off pops 0', (t) async {
    final result = await _open<int>(t, const PatternsPage.gradient(primary: Colors.red, dither: 2));
    await t.tap(find.text('Off'));
    await t.pumpAndSettle();
    expect(await result(), 0);
  });

  test('PatternTilePainter repaints only when the tile, color, or scale changes', () {
    final a = PatternTilePainter(tile: checker, color: Colors.red, scale: 4);
    expect(a.shouldRepaint(PatternTilePainter(tile: checker, color: Colors.red, scale: 4)), isFalse);
    expect(a.shouldRepaint(PatternTilePainter(tile: lines, color: Colors.red, scale: 4)), isTrue);
    expect(a.shouldRepaint(PatternTilePainter(tile: checker, color: Colors.blue, scale: 4)), isTrue);
    expect(a.shouldRepaint(PatternTilePainter(tile: checker, color: Colors.red, scale: 2)), isTrue);
  });
}
