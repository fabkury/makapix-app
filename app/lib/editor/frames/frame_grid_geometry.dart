// The contact sheet's geometry (ADR 0031): where every tile sits for a given width and column
// count, and the inverse — which tile a pointer is over — for the long-press sweep, the
// desktop rubber-band, and the visible-range thumbnail revalidation. Pure (painting only), so
// the sweep math is unit-tested without a widget tree.

import 'dart:math' as math;

import 'package:flutter/painting.dart';

const int kFramesMinColumns = 3;
const int kFramesMaxColumns = 8;
const int kFramesDefaultColumns = 4;

class FrameGridGeometry {
  FrameGridGeometry({
    required this.gridWidth,
    required int columns,
    required double thumbAspect,
    required this.labelBand,
    this.padding = const EdgeInsets.all(8),
    this.spacing = 4,
  })  : columns = columns.clamp(1, 64),
        thumbAspect = thumbAspect.isFinite && thumbAspect > 0 ? thumbAspect.clamp(1 / 3, 3.0) : 1.0;

  final double gridWidth;
  final int columns;

  /// Artwork width / height, clamped to 1/3 … 3 so a ribbon-shaped canvas keeps usable tiles.
  final double thumbAspect;

  /// The label strip under the thumbnail (number + duration badge).
  final double labelBand;
  final EdgeInsets padding;
  final double spacing;

  double get cellWidth => math.max(1.0, (gridWidth - padding.horizontal - spacing * (columns - 1)) / columns);
  double get cellHeight => cellWidth / thumbAspect + labelBand;
  double get rowExtent => cellHeight + spacing;

  int rowCount(int count) => count <= 0 ? 0 : (count + columns - 1) ~/ columns;

  double contentHeight(int count) {
    final rows = rowCount(count);
    return padding.vertical + (rows == 0 ? 0 : rows * cellHeight + (rows - 1) * spacing);
  }

  /// The tile's rectangle in CONTENT coordinates (scroll offset 0 at the top).
  Rect rectOf(int index) {
    final col = index % columns;
    final row = index ~/ columns;
    return Rect.fromLTWH(
      padding.left + col * (cellWidth + spacing),
      padding.top + row * rowExtent,
      cellWidth,
      cellHeight,
    );
  }

  /// The tile under a viewport-local point, or `null` over padding, a gap, or past the end.
  int? indexAt(Offset viewportLocal, double scrollOffset, int count) {
    final x = viewportLocal.dx - padding.left;
    final y = viewportLocal.dy + scrollOffset - padding.top;
    if (x < 0 || y < 0) return null;
    final col = (x / (cellWidth + spacing)).floor();
    final row = (y / rowExtent).floor();
    if (col >= columns) return null;
    if (x - col * (cellWidth + spacing) > cellWidth) return null;
    if (y - row * rowExtent > cellHeight) return null;
    final i = row * columns + col;
    return i < count ? i : null;
  }

  /// Every tile whose rectangle intersects [content] (content coordinates).
  Set<int> indicesInRect(Rect content, int count) {
    final out = <int>{};
    if (count <= 0 || content.isEmpty && content.width == 0 && content.height == 0) return out;
    final r = Rect.fromLTRB(
      math.min(content.left, content.right),
      math.min(content.top, content.bottom),
      math.max(content.left, content.right),
      math.max(content.top, content.bottom),
    );
    final firstRow = math.max(0, ((r.top - padding.top) / rowExtent).floor());
    final lastRow = math.min(rowCount(count) - 1, ((r.bottom - padding.top) / rowExtent).floor());
    for (var row = firstRow; row <= lastRow; row++) {
      for (var col = 0; col < columns; col++) {
        final i = row * columns + col;
        if (i >= count) break;
        if (rectOf(i).overlaps(r)) out.add(i);
      }
    }
    return out;
  }

  /// The inclusive index range of the tiles a viewport shows; `(0, -1)` when nothing does.
  (int first, int last) visibleRange(double scrollOffset, double viewportHeight, int count) {
    if (count <= 0 || viewportHeight <= 0) return (0, -1);
    final top = scrollOffset - padding.top;
    final bottom = scrollOffset + viewportHeight - padding.top;
    final firstRow = math.max(0, (top / rowExtent).floor());
    final lastRow = math.min(rowCount(count) - 1, (bottom / rowExtent).floor());
    if (lastRow < firstRow) return (0, -1);
    return (firstRow * columns, math.min(count - 1, lastRow * columns + columns - 1));
  }

  /// A pinch's column step: spreading (ratio > 1.25) shows fewer, bigger tiles; squeezing
  /// (ratio < 0.8) shows more. Clamped to the page's range.
  static int columnsForPinch(int columns, double ratio) {
    var next = columns;
    if (ratio > 1.25) next = columns - 1;
    if (ratio < 0.8) next = columns + 1;
    return next.clamp(kFramesMinColumns, kFramesMaxColumns);
  }
}
