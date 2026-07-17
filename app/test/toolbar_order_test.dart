// restoreHiddenTool: rebuilding the full row-3 tool order after a reorder done in visible space
// (the 3-row toolbar hides the configured pinned tile from the grid — it's pinned beside Undo/Redo —
// but that tool must keep its place in the persisted order so toggling the mode / re-pinning never
// churns it). The pinned tool defaults to Play but is user-configurable, so the hidden tool is any tool.
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/tools.dart';

void main() {
  group('restoreHiddenTool', () {
    test('reinserts the hidden tool at its previous index after a visible-space reorder', () {
      final previous = ['Pencil', 'Brush', 'PlayPause', 'Eraser', 'Onion'];
      // Visible reorder (PlayPause absent): Eraser dragged to the front.
      final visible = ['Eraser', 'Pencil', 'Brush', 'Onion'];
      expect(
        restoreHiddenTool(visible, previous, 'PlayPause'),
        ['Eraser', 'Pencil', 'PlayPause', 'Brush', 'Onion'],
      );
    });

    test('clamps when the hidden tool was last', () {
      final previous = ['Pencil', 'Brush', 'PlayPause'];
      final visible = ['Brush', 'Pencil'];
      expect(restoreHiddenTool(visible, previous, 'PlayPause'), ['Brush', 'Pencil', 'PlayPause']);
    });

    test('returns visible unchanged when the hidden tool is not in the previous order', () {
      final previous = ['Pencil', 'Brush'];
      final visible = ['Brush', 'Pencil'];
      expect(restoreHiddenTool(visible, previous, 'PlayPause'), same(visible));
    });

    test('is idempotent when the visible list already contains the hidden tool', () {
      // Defensive: if called with a full (2-row) list it must not duplicate the tool.
      final previous = ['Pencil', 'PlayPause', 'Brush'];
      final visible = ['Brush', 'PlayPause', 'Pencil'];
      expect(restoreHiddenTool(visible, previous, 'PlayPause'), ['Brush', 'PlayPause', 'Pencil']);
    });

    test('every real tool order round-trips: hide Play, reorder nothing, restore', () {
      final full = tools.map((t) => t.dsl).toList();
      final visible = full.where((d) => d != 'PlayPause').toList();
      expect(restoreHiddenTool(visible, full, 'PlayPause'), full);
    });

    // The 3rd pinned slot is configurable, so the hidden tool can be ANY tool — not just Play.
    test('reinserts an arbitrary hidden tool (Pencil) at its previous index', () {
      final previous = ['Pencil', 'Brush', 'PlayPause', 'Eraser', 'Onion'];
      // Pencil is pinned → hidden from the grid; Onion dragged to the front in visible space.
      final visible = ['Onion', 'Brush', 'PlayPause', 'Eraser'];
      expect(
        restoreHiddenTool(visible, previous, 'Pencil'),
        ['Pencil', 'Onion', 'Brush', 'PlayPause', 'Eraser'],
      );
    });

    test('round-trips hiding an arbitrary tool for every real order (Bucket pinned)', () {
      final full = tools.map((t) => t.dsl).toList();
      final visible = full.where((d) => d != 'Bucket').toList();
      expect(restoreHiddenTool(visible, full, 'Bucket'), full);
    });
  });
}
