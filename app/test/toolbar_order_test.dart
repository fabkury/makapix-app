// The row-3 order's visible/full-space mapping. restoreHiddenTool(s): rebuilding the full tool
// order after a reorder done in visible space — the 3-row toolbar keeps the pinned tile out of the
// grid (it's pinned beside Undo/Redo) and, since ADR 0018, so are the user-hidden tools; every such
// tool must keep its place in the persisted order so toggling the mode / re-pinning / unhiding never
// churns it. Plus the hidden-set reconciliation and floor (visibleToolOrder, reconcileHiddenTools,
// canHideAnotherTool). Pure functions: no engine, no widgets.
import 'dart:math';

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

  group('restoreHiddenTools (a set of excluded tools, ADR 0018)', () {
    test('reinserts several hidden tools at their former indices after a visible-space reorder', () {
      final previous = ['A', 'h1', 'B', 'h2', 'C'];
      // Visible reorder (h1/h2 absent): C dragged to the front.
      final visible = ['C', 'A', 'B'];
      expect(restoreHiddenTools(visible, previous, {'h1', 'h2'}), ['C', 'h1', 'A', 'h2', 'B']);
    });

    test('hidden tools at both ends keep their ends', () {
      final previous = ['h0', 'A', 'B', 'C', 'h4'];
      final visible = ['B', 'C', 'A'];
      expect(restoreHiddenTools(visible, previous, {'h0', 'h4'}), ['h0', 'B', 'C', 'A', 'h4']);
    });

    test('adjacent hidden tools stay adjacent and in order', () {
      final previous = ['A', 'h1', 'h2', 'h3', 'B'];
      final visible = ['B', 'A'];
      expect(restoreHiddenTools(visible, previous, {'h1', 'h2', 'h3'}), ['B', 'h1', 'h2', 'h3', 'A']);
    });

    test('the pinned tool and the hidden set are one exclusion set', () {
      final full = tools.map((t) => t.dsl).toList();
      final excluded = {'PlayPause', 'Onion', 'Levels'};
      final visible = visibleToolOrder(full, {'Onion', 'Levels'}, pinned: 'PlayPause');
      expect(visible, isNot(contains('PlayPause')));
      expect(visible.length, full.length - 3);
      expect(restoreHiddenTools(visible, full, excluded), full);
    });

    test('excluded tools missing from the previous order are ignored; none present → same list', () {
      final previous = ['A', 'B', 'h1'];
      final visible = ['B', 'A'];
      expect(restoreHiddenTools(visible, previous, {'h1', 'ghost'}), ['B', 'A', 'h1']);
      expect(restoreHiddenTools(visible, previous, {'ghost'}), same(visible));
    });

    test('property: remove-then-restore round-trips and a visible reorder never moves a hidden slot', () {
      final rng = Random(20260901);
      final full = tools.map((t) => t.dsl).toList();
      for (var trial = 0; trial < 400; trial++) {
        final order = List<String>.of(full)..shuffle(rng);
        final hidden = {for (final d in order) if (rng.nextInt(3) == 0) d};
        if (hidden.length >= order.length) continue;
        final visible = visibleToolOrder(order, hidden);
        // 1. Exact round-trip.
        expect(restoreHiddenTools(visible, order, hidden), order, reason: 'round-trip $order / $hidden');
        // 2. Any visible-space permutation restores every hidden tool to its former index and
        //    keeps the visible tools in their new relative order; nothing duplicated or lost.
        final reordered = List<String>.of(visible)..shuffle(rng);
        final restored = restoreHiddenTools(reordered, order, hidden);
        expect(restored.length, order.length);
        expect(restored.toSet(), order.toSet());
        for (final h in hidden) {
          expect(restored.indexOf(h), order.indexOf(h), reason: 'hidden $h moved');
        }
        expect(restored.where((d) => !hidden.contains(d)).toList(), reordered);
      }
    });
  });

  group('reconcileHiddenTools / canHideAnotherTool', () {
    final catalog = ['A', 'B', 'C', 'D'];

    test('null (never saved) → nothing hidden', () {
      expect(reconcileHiddenTools(null, catalog), isEmpty);
    });

    test('unknown dsl names are dropped, duplicates collapse, order is irrelevant', () {
      expect(reconcileHiddenTools(['C', 'Zed', 'A', 'C'], catalog), {'A', 'C'});
    });

    test('a set that would leave nothing visible is discarded (floor = 1 visible)', () {
      expect(reconcileHiddenTools(['A', 'B', 'C', 'D'], catalog), isEmpty);
      expect(reconcileHiddenTools(['A', 'B', 'C', 'D', 'Zed'], catalog), isEmpty);
      // Catalog drift: a removed tool was the only visible one → the survivors cover the catalog.
      expect(reconcileHiddenTools(['A', 'B', 'C', 'D'], ['A', 'B', 'C', 'D', 'E']), {'A', 'B', 'C', 'D'});
    });

    test('canHideAnotherTool stops exactly at the last visible tool', () {
      expect(canHideAnotherTool({}, catalog), isTrue);
      expect(canHideAnotherTool({'A', 'B'}, catalog), isTrue);
      expect(canHideAnotherTool({'A', 'B', 'C'}, catalog), isFalse);
    });

    test('a hidden set accepted by reconcile always leaves at least one tool visible', () {
      final full = tools.map((t) => t.dsl).toList();
      final hidden = reconcileHiddenTools(full.sublist(1), full);
      expect(visibleToolOrder(full, hidden), [full.first]);
      expect(canHideAnotherTool(hidden, full), isFalse);
    });
  });

  group('toolGridShape', () {
    test('portrait: fixed band count, tiles split across bands', () {
      expect(toolGridShape(n: 14, threeBands: false, vertical: false), (bands: 2, perBand: 7));
      expect(toolGridShape(n: 14, threeBands: true, vertical: false), (bands: 3, perBand: 5));
      expect(toolGridShape(n: 15, threeBands: false, vertical: false), (bands: 2, perBand: 8));
    });

    test('landscape: the transpose — fixed tiles per row, rows grow with n', () {
      expect(toolGridShape(n: 14, threeBands: false, vertical: true), (bands: 7, perBand: 2));
      expect(toolGridShape(n: 14, threeBands: true, vertical: true), (bands: 5, perBand: 3));
      expect(toolGridShape(n: 15, threeBands: true, vertical: true), (bands: 5, perBand: 3));
    });

    test('every tile fits and no band is empty, for all n and both orientations', () {
      for (var n = 1; n <= 40; n++) {
        for (final three in [false, true]) {
          for (final vertical in [false, true]) {
            final s = toolGridShape(n: n, threeBands: three, vertical: vertical);
            expect(s.bands * s.perBand, greaterThanOrEqualTo(n),
                reason: 'capacity for n=$n three=$three vertical=$vertical');
            // Landscape derives its row count from n, so no row may be empty. (Portrait keeps a
            // FIXED band count — 2/3 rows even for tiny n — matching the real toolbar.)
            if (vertical) {
              expect((s.bands - 1) * s.perBand, lessThan(n),
                  reason: 'no empty row for n=$n three=$three vertical=$vertical');
            }
          }
        }
      }
    });
  });
}
