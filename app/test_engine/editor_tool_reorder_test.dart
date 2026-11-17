// Row-3 drag reorder on the REAL editor: a drag must be committed and saved when the finger
// lifts, and a second drag must not undo the first.
//
// Until 2026-11-17 no reorder was ever committed: the tiles were keyed with an identity-compared
// key built from a fresh string on every build, so the dragged tile was remounted the moment the
// drag began and Flutter never delivered its onDragEnd. The moved tile only LOOKED moved (the
// drag preview stayed on screen) until the next drag sent it back — the bug report was "I dragged
// Pick, then on dragging Copy, Pick immediately goes back". Nothing was written to preferences.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makapix_club/editor/tools.dart';
import 'package:makapix_club/editor/widgets/tool_tile.dart';

import 'editor_harness.dart';

Finder _tile(String dsl) => find.byWidgetPredicate((w) => w is ToolTile && w.tool.dsl == dsl);

/// The grid's tools in reading order (rows top to bottom, each left to right), as drawn.
List<String> _gridOrder(WidgetTester tester) {
  final tiles = [
    for (final e in find.byType(ToolTile).evaluate())
      // Undo / Redo are the pinned tiles beside the grid, not part of it.
      if (!const {'Undo', 'Redo'}.contains((e.widget as ToolTile).tool.dsl))
        (
          dsl: (e.widget as ToolTile).tool.dsl,
          at: (e.renderObject! as RenderBox).localToGlobal(Offset.zero),
        ),
  ]..sort((a, b) => a.at.dy != b.at.dy ? a.at.dy.compareTo(b.at.dy) : a.at.dx.compareTo(b.at.dx));
  return [for (final t in tiles) t.dsl];
}

/// Long-press [dsl] and drop it just right of [after]'s midpoint: it lands right after it.
Future<void> _dragAfter(WidgetTester tester, String dsl, String after) async {
  final gesture = await tester.startGesture(tester.getCenter(_tile(dsl)));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  // The feedback is anchored to the tile, so the finger's position is the feedback's midpoint.
  // One move, straight to the spot: the tiles reflow under the finger as soon as it arrives.
  await gesture.moveTo(tester.getCenter(_tile(after)) + const Offset(6, 0));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await settleReal(tester, rounds: 3);
}

void main() {
  testWidgets('row-3 reorder: each drag is committed and saved, and survives the next one',
      (tester) async {
    // Portrait, and wide enough that both grid rows are fully on screen (the grid does not
    // auto-scroll during a drag).
    await pumpEditor(tester, const Locale('en'), size: const Size(1200, 1600));
    final all = [for (final t in tools) t.dsl];
    final visible = visibleToolOrder(all, kDefaultHiddenTools);
    expect(_gridOrder(tester), visible, reason: 'the grid starts in catalog order');

    // What a move does to the visible order, mirrored here.
    List<String> moved(List<String> order, String dsl, String after) {
      final out = [...order]..remove(dsl);
      return out..insert(out.indexOf(after) + 1, dsl);
    }

    // Drag 1: Pick (Eyedropper) to right after Brush.
    await _dragAfter(tester, 'Eyedropper', 'Brush');
    final afterFirst = moved(visible, 'Eyedropper', 'Brush');
    expect(_gridOrder(tester), afterFirst);
    final prefs = await SharedPreferences.getInstance();
    final savedFirst = prefs.getStringList('tool_order_v1');
    expect(savedFirst, isNotNull, reason: 'the first drag was never committed');
    expect(visibleToolOrder(savedFirst!, kDefaultHiddenTools), afterFirst);
    expect(savedFirst.toSet(), all.toSet(), reason: 'hidden tools keep their place in the order');

    // Drag 2: Copy to right after Line. Pick must stay where drag 1 put it.
    await _dragAfter(tester, 'CopyPaste', 'Line');
    final afterSecond = moved(afterFirst, 'CopyPaste', 'Line');
    expect(_gridOrder(tester), afterSecond, reason: 'the second drag undid the first');
    expect(visibleToolOrder(prefs.getStringList('tool_order_v1')!, kDefaultHiddenTools),
        afterSecond);

    // The tool that was dragged is an ordinary tile again: tapping it selects it.
    await tester.tap(_tile('Eyedropper'));
    await settleReal(tester, rounds: 2);
    expect(tester.widget<ToolTile>(_tile('Eyedropper')).selected, isTrue);

    await closeEditor(tester);
  });
}
