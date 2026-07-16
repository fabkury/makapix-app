import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/ui/widgets/super_post_grid_layout.dart';

// Geometry used throughout: w=100, h=124 (infoBar 24), spacing 4 both axes.
// strideX = strideY - 24 = 104, strideY = 128.
SuperPostGridLayout layout({required int cols, required int superIndex}) => SuperPostGridLayout(
      crossAxisCount: cols,
      childCrossAxisExtent: 100,
      childMainAxisExtent: 124,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      superIndex: superIndex,
      reverseCrossAxis: false,
    );

const double sx = 104, sy = 128; // strides

void main() {
  test('k=0, C=4: block at top-left, children flow around it', () {
    final l = layout(cols: 4, superIndex: 0);
    final block = l.getGeometryForChildIndex(0);
    expect(block.scrollOffset, 0);
    expect(block.crossAxisOffset, 0);
    expect(block.crossAxisExtent, 204); // 2*100 + 4
    expect(block.mainAxisExtent, 252); // 2*124 + 4

    // Child 1 -> cell 2 (right of the block, row 0).
    expect(l.cellForChild(1), 2);
    final c1 = l.getGeometryForChildIndex(1);
    expect(c1.scrollOffset, 0);
    expect(c1.crossAxisOffset, 2 * sx);
    // Child 2 -> cell 3; child 3 skips the block's second row -> cell 6.
    expect(l.cellForChild(2), 3);
    expect(l.cellForChild(3), 6);
    final c3 = l.getGeometryForChildIndex(3);
    expect(c3.scrollOffset, sy);
    expect(c3.crossAxisOffset, 2 * sx);
    // Child 5 -> first cell of row 2.
    expect(l.cellForChild(5), 8);
  });

  test('k on last column (C=4, k=3): block shifts to next row, cell 3 dense-filled', () {
    final l = layout(cols: 4, superIndex: 3);
    final block = l.getGeometryForChildIndex(3);
    expect(block.scrollOffset, sy); // anchor cell 4 = row 1 col 0
    expect(block.crossAxisOffset, 0);
    // Child 4 fills the vacated cell 3 (row 0, last column).
    expect(l.cellForChild(4), 3);
    // Block cells are {4,5,8,9}; the free cells after 3 are 6,7 then 10,11.
    expect(l.cellForChild(5), 6);
    expect(l.cellForChild(6), 7);
    expect(l.cellForChild(7), 10);
  });

  test('C=2: block spans full width', () {
    final l = layout(cols: 2, superIndex: 1);
    // Natural col of 1 is the last column -> anchor cell 2 (row 1 col 0).
    final block = l.getGeometryForChildIndex(1);
    expect(block.scrollOffset, sy);
    expect(block.crossAxisOffset, 0);
    expect(block.crossAxisExtent, 204);
    // Child 2 fills the vacated cell 1; child 3 skips the block -> cell 6.
    expect(l.cellForChild(2), 1);
    expect(l.cellForChild(3), 6);
    expect(l.cellForChild(4), 7);
  });

  test('C=8, k mid-row: neighbors flow through both block rows', () {
    final l = layout(cols: 8, superIndex: 11); // row 1, col 3
    final block = l.getGeometryForChildIndex(11);
    expect(block.scrollOffset, sy);
    expect(block.crossAxisOffset, 3 * sx);
    // Block cells {11,12,19,20}. Child 12 -> 13 ... child 17 -> 18, child 18 -> 21.
    expect(l.cellForChild(12), 13);
    expect(l.cellForChild(17), 18);
    expect(l.cellForChild(18), 21);
  });

  test('trailing super + loading cell: spinner dense-fills the vacated cell', () {
    // 8 items, k=7 (row 1 col 3 of C=4: not last column) — use k on last column:
    final l = layout(cols: 4, superIndex: 7); // col 3 -> anchor 8
    // With a loading cell there are 9 children; child 8 (the spinner) fills cell 7.
    expect(l.cellForChild(8), 7);
    // Block occupies rows 2-3; max scroll must cover 4 rows.
    expect(l.computeMaxScrollOffset(9), 4 * sy - 4);
  });

  test('trailing super atEnd: hole above the block is accepted, extent still covers block', () {
    final l = layout(cols: 4, superIndex: 7);
    // 8 items, no spinner: cell 7 stays empty; block bottom row is row 3.
    expect(l.computeMaxScrollOffset(8), 4 * sy - 4);
  });

  test('single super child', () {
    final l = layout(cols: 4, superIndex: 0);
    expect(l.computeMaxScrollOffset(1), 2 * sy - 4);
  });

  test('min child index includes the super child in its second row', () {
    final l = layout(cols: 4, superIndex: 0);
    // Offset inside row 1 (the block's second row): child 0 is still visible.
    expect(l.getMinChildIndexForScrollOffset(sy + 10), lessThanOrEqualTo(0));
    // Offset in row 2: block has ended; children of row 2 start at index 5.
    expect(l.getMinChildIndexForScrollOffset(2 * sy + 10), lessThanOrEqualTo(5));
    expect(l.getMinChildIndexForScrollOffset(2 * sy + 10), greaterThan(0));
  });

  test('reverseCrossAxis mirrors using each child\'s own extent', () {
    final l = SuperPostGridLayout(
      crossAxisCount: 4,
      childCrossAxisExtent: 100,
      childMainAxisExtent: 124,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      superIndex: 0,
      reverseCrossAxis: true,
    );
    const total = 4 * sx - 4; // 412
    final block = l.getGeometryForChildIndex(0);
    expect(block.crossAxisOffset, total - 204); // col 0, width 204
    final c1 = l.getGeometryForChildIndex(1); // cell 2
    expect(c1.crossAxisOffset, total - 2 * sx - 100);
  });

  group('property sweep', () {
    test('no overlap, dense fill, bracketing, max scroll', () {
      for (var cols = 2; cols <= 8; cols++) {
        for (var n = 1; n <= 40; n++) {
          for (var k = 0; k < n; k++) {
            final l = layout(cols: cols, superIndex: k);
            final ctx = 'cols=$cols n=$n k=$k';

            // Collect occupied cells: every non-super child's cell + the block's 4.
            final cells = <int>{};
            for (var q = 0; q < (n + 2) * cols * 2; q++) {
              if (l.isBlockCell(q)) cells.add(q);
            }
            expect(cells.length, 4, reason: 'block cells $ctx');
            for (var i = 0; i < n; i++) {
              if (i == k) continue;
              final q = l.cellForChild(i);
              expect(l.isBlockCell(q), isFalse, reason: 'child $i in block $ctx');
              expect(cells.add(q), isTrue, reason: 'child $i overlaps $ctx');
            }

            // Dense fill: the occupied non-block cells are the first n-1 non-block
            // cells in reading order (no empty non-block cell precedes an occupied one).
            final occupiedNonBlock = <int>[];
            var q = 0;
            var seen = 0;
            while (seen < n - 1) {
              if (!l.isBlockCell(q)) {
                occupiedNonBlock.add(q);
                seen++;
              }
              q++;
            }
            final actual = <int>[
              for (var i = 0; i < n; i++)
                if (i != k) l.cellForChild(i)
            ]..sort();
            expect(actual, occupiedNonBlock, reason: 'dense fill $ctx');

            // Bracketing + max scroll offset.
            final maxScroll = l.computeMaxScrollOffset(n);
            var maxTrailing = 0.0;
            for (var i = 0; i < n; i++) {
              final g = l.getGeometryForChildIndex(i);
              maxTrailing =
                  maxTrailing > g.trailingScrollOffset ? maxTrailing : g.trailingScrollOffset;
              expect(l.getMinChildIndexForScrollOffset(g.scrollOffset), lessThanOrEqualTo(i),
                  reason: 'min at leading, child $i $ctx');
              expect(
                  l.getMaxChildIndexForScrollOffset(g.trailingScrollOffset - 0.01),
                  greaterThanOrEqualTo(i),
                  reason: 'max at trailing, child $i $ctx');
              // A child fully above the window must not be required below it.
              expect(g.scrollOffset, lessThanOrEqualTo(maxScroll), reason: 'leading $i $ctx');
            }
            expect(maxScroll, greaterThanOrEqualTo(maxTrailing), reason: 'max scroll $ctx');
            // Exactness: the extent is the max trailing edge (rows are uniform,
            // and the last occupied row always reaches maxScroll).
            expect(maxScroll, maxTrailing, reason: 'max scroll exact $ctx');
          }
        }
      }
    });
  });

  test('delegate computes tile width from sliver cross extent', () {
    const d = SuperPostGridDelegate(
      crossAxisCount: 4,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      infoBarExtent: 24,
      superIndex: 2,
    );
    final l = d.getLayout(const SliverConstraints(
      axisDirection: AxisDirection.down,
      growthDirection: GrowthDirection.forward,
      userScrollDirection: ScrollDirection.idle,
      scrollOffset: 0,
      precedingScrollExtent: 0,
      overlap: 0,
      remainingPaintExtent: 600,
      crossAxisExtent: 428, // (428 - 3*4) / 4 => tile width 104
      crossAxisDirection: AxisDirection.right,
      viewportMainAxisExtent: 600,
      remainingCacheExtent: 600,
      cacheOrigin: 0,
    )) as SuperPostGridLayout;
    expect(l.childCrossAxisExtent, 104);
    expect(l.childMainAxisExtent, 128);
    expect(l.superIndex, 2);
    expect(l.reverseCrossAxis, isFalse);

    // shouldRelayout on superIndex change.
    const d2 = SuperPostGridDelegate(
      crossAxisCount: 4,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      infoBarExtent: 24,
      superIndex: 3,
    );
    expect(d2.shouldRelayout(d), isTrue);
    expect(d.shouldRelayout(d), isFalse);
  });
}
