import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Grid layout identical to a fixed-cross-axis-count grid of uniform cells,
/// except that the child at [superIndex] (the "super post") spans a 2×2 block
/// of cells. Later children dense-fill the remaining cells in reading order,
/// so no hole ever precedes an occupied cell.
///
/// Placement: the block anchors at the super child's natural cell `k`
/// (cell = list index, since children before it are unaffected). When `k`
/// falls on the last column the block cannot fit there, so it moves to the
/// start of the next row and the vacated cell is dense-filled by the next
/// child.
///
/// All the mapping math is pure integer arithmetic over cell indices
/// (reading order, `cell = row * crossAxisCount + column`), which keeps every
/// [SliverGridLayout] query O(1) and unit-testable without widgets.
class SuperPostGridLayout extends SliverGridLayout {
  final int crossAxisCount;
  final double childCrossAxisExtent;
  final double childMainAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final int superIndex;
  final bool reverseCrossAxis;

  const SuperPostGridLayout({
    required this.crossAxisCount,
    required this.childCrossAxisExtent,
    required this.childMainAxisExtent,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.superIndex,
    required this.reverseCrossAxis,
  })  : assert(crossAxisCount >= 2),
        assert(superIndex >= 0);

  double get _strideX => childCrossAxisExtent + crossAxisSpacing;
  double get _strideY => childMainAxisExtent + mainAxisSpacing;

  /// Top-left cell of the 2×2 block.
  int get _blockAnchor =>
      superIndex % crossAxisCount <= crossAxisCount - 2 ? superIndex : superIndex + 1;

  /// The four cells covered by the block, relative to [_blockAnchor].
  bool _isBlockCell(int q) {
    final b = _blockAnchor;
    return q == b || q == b + 1 || q == b + crossAxisCount || q == b + crossAxisCount + 1;
  }

  /// How many of the block's four cells precede cell [q] in reading order.
  int _blockCellsBefore(int q) {
    final b = _blockAnchor;
    if (q <= b) return 0;
    if (q <= b + 1) return 1;
    if (q <= b + crossAxisCount) return 2;
    if (q <= b + crossAxisCount + 1) return 3;
    return 4;
  }

  /// Cell occupied by a non-super child: children other than the super post,
  /// in list order, fill the non-block cells in reading order.
  @visibleForTesting
  int cellForChild(int index) {
    assert(index != superIndex);
    final b = _blockAnchor;
    final p = index < superIndex ? index : index - 1;
    if (p < b) return p;
    // The C-2 non-block cells alongside the block (rest of its first row plus,
    // when the block is not column-aligned left, the start of its second row).
    // Empty branch when crossAxisCount == 2: the block spans the full width.
    if (p - b < crossAxisCount - 2) return p + 2;
    return p + 4;
  }

  /// Inverse of the dense fill: child occupying the [p]-th non-block cell.
  int _childForOrder(int p) => p < superIndex ? p : p + 1;

  double _crossOffset(int column, double ownCrossExtent) {
    final raw = column * _strideX;
    if (!reverseCrossAxis) return raw;
    final total = crossAxisCount * _strideX - crossAxisSpacing;
    return total - raw - ownCrossExtent;
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    if (index == superIndex) {
      final b = _blockAnchor;
      final blockCross = 2 * childCrossAxisExtent + crossAxisSpacing;
      return SliverGridGeometry(
        scrollOffset: (b ~/ crossAxisCount) * _strideY,
        crossAxisOffset: _crossOffset(b % crossAxisCount, blockCross),
        mainAxisExtent: 2 * childMainAxisExtent + mainAxisSpacing,
        crossAxisExtent: blockCross,
      );
    }
    final q = cellForChild(index);
    return SliverGridGeometry(
      scrollOffset: (q ~/ crossAxisCount) * _strideY,
      crossAxisOffset: _crossOffset(q % crossAxisCount, childCrossAxisExtent),
      mainAxisExtent: childMainAxisExtent,
      crossAxisExtent: childCrossAxisExtent,
    );
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    if (_strideY <= 0) return 0;
    final firstRow = scrollOffset ~/ _strideY;
    final q0 = firstRow * crossAxisCount;
    final p0 = q0 - _blockCellsBefore(q0);
    var candidate = _childForOrder(p0);
    // The block spans two rows: offsets landing in its second row must still
    // include the super child.
    if (firstRow <= _blockAnchor ~/ crossAxisCount + 1) {
      candidate = math.min(candidate, superIndex);
    }
    return math.max(0, candidate);
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    if (_strideY <= 0) return 0;
    final rows = (scrollOffset / _strideY).ceil();
    final q1 = crossAxisCount * rows - 1;
    if (q1 < 0) return 0;
    final nonBlock = (q1 + 1) - _blockCellsBefore(q1 + 1);
    var candidate = nonBlock == 0 ? superIndex : _childForOrder(nonBlock - 1);
    if (_blockAnchor ~/ crossAxisCount <= q1 ~/ crossAxisCount) {
      candidate = math.max(candidate, superIndex);
    }
    return math.max(0, candidate);
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    if (childCount <= 0) return 0;
    final blockBottom = _blockAnchor + crossAxisCount + 1;
    var maxCell = blockBottom;
    final lastNonSuper = childCount - 1 == superIndex ? childCount - 2 : childCount - 1;
    if (lastNonSuper >= 0 && lastNonSuper != superIndex) {
      maxCell = math.max(maxCell, cellForChild(lastNonSuper));
    }
    return (maxCell ~/ crossAxisCount + 1) * _strideY - mainAxisSpacing;
  }

  /// Test hook: whether reading-order cell [q] is one of the block's four.
  @visibleForTesting
  bool isBlockCell(int q) => _isBlockCell(q);
}

/// Delegate producing a [SuperPostGridLayout]; drop-in replacement for
/// `SliverGridDelegateWithFixedCrossAxisCount` when a feed has a super post.
class SuperPostGridDelegate extends SliverGridDelegate {
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  /// Height of the info bar below each square artwork; cells are
  /// `tileWidth + infoBarExtent` tall. Below the block's square artwork
  /// (side = its cross extent) this leaves an info area of
  /// `2 * infoBarExtent + mainAxisSpacing - crossAxisSpacing` — with equal
  /// spacings, exactly two bars' worth of height.
  final double infoBarExtent;
  final int superIndex;

  const SuperPostGridDelegate({
    required this.crossAxisCount,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.infoBarExtent,
    required this.superIndex,
  });

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final w =
        (constraints.crossAxisExtent - (crossAxisCount - 1) * crossAxisSpacing) / crossAxisCount;
    return SuperPostGridLayout(
      crossAxisCount: crossAxisCount,
      childCrossAxisExtent: w,
      childMainAxisExtent: w + infoBarExtent,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      superIndex: superIndex,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(SuperPostGridDelegate oldDelegate) =>
      oldDelegate.crossAxisCount != crossAxisCount ||
      oldDelegate.mainAxisSpacing != mainAxisSpacing ||
      oldDelegate.crossAxisSpacing != crossAxisSpacing ||
      oldDelegate.infoBarExtent != infoBarExtent ||
      oldDelegate.superIndex != superIndex;
}
