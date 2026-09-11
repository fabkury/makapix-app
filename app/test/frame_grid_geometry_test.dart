// The contact sheet's geometry (frames/frame_grid_geometry.dart): cell sizes, the pointer →
// tile inverse the sweep uses, rubber-band hits, the visible range, and the pinch step.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/frames/frame_grid_geometry.dart';

void main() {
  // 400 wide, 4 columns, square art, 20 px label band, 8 px padding, 4 px spacing:
  // cell = (400 - 16 - 12) / 4 = 93 wide, 113 tall; row extent 117.
  final g = FrameGridGeometry(gridWidth: 400, columns: 4, thumbAspect: 1, labelBand: 20);

  test('cell sizes and content height', () {
    expect(g.cellWidth, 93);
    expect(g.cellHeight, 113);
    expect(g.rowExtent, 117);
    expect(g.rowCount(9), 3);
    expect(g.contentHeight(9), 16 + 3 * 113 + 2 * 4);
    expect(g.contentHeight(0), 16);
  });

  test('aspect is clamped and columns bounded', () {
    expect(FrameGridGeometry(gridWidth: 400, columns: 4, thumbAspect: 10, labelBand: 0).thumbAspect, 3);
    expect(FrameGridGeometry(gridWidth: 400, columns: 4, thumbAspect: 0, labelBand: 0).thumbAspect, 1);
    expect(FrameGridGeometry(gridWidth: 400, columns: 0, thumbAspect: 1, labelBand: 0).columns, 1);
  });

  test('rectOf lays tiles out row-major', () {
    expect(g.rectOf(0), const Rect.fromLTWH(8, 8, 93, 113));
    expect(g.rectOf(1), const Rect.fromLTWH(8 + 97, 8, 93, 113));
    expect(g.rectOf(4), const Rect.fromLTWH(8, 8 + 117, 93, 113));
  });

  test('indexAt finds tiles, returns null in padding, gaps, and past the end', () {
    expect(g.indexAt(const Offset(10, 10), 0, 9), 0);
    expect(g.indexAt(const Offset(100, 10), 0, 9), 0, reason: 'column 0 spans x 8..101');
    expect(g.indexAt(const Offset(103, 10), 0, 9), null, reason: 'the 4 px gap between columns');
    expect(g.indexAt(const Offset(110, 10), 0, 9), 1);
    expect(g.indexAt(const Offset(2, 10), 0, 9), null, reason: 'left padding');
    expect(g.indexAt(const Offset(10, 2), 0, 9), null, reason: 'top padding');
    expect(g.indexAt(const Offset(10, 8 + 117 + 5), 0, 9), 4);
    expect(g.indexAt(const Offset(10, 10), 117, 9), 4, reason: 'scrolled one row');
    expect(g.indexAt(const Offset(110, 8 + 2 * 117 + 5), 0, 9), null, reason: 'index 9 is past the end');
    expect(g.indexAt(const Offset(10, 8 + 2 * 117 + 5), 0, 9), 8);
    expect(g.indexAt(const Offset(380, 10), 0, 9), 3, reason: 'column 3 spans x 299..392');
    expect(g.indexAt(const Offset(399, 10), 0, 9), null, reason: 'right padding');
  });

  test('indicesInRect returns every overlapping tile, any drag direction', () {
    final band = Rect.fromPoints(const Offset(50, 50), const Offset(150, 130));
    expect(g.indicesInRect(band, 9), {0, 1, 4, 5});
    final reversed = Rect.fromPoints(const Offset(150, 130), const Offset(50, 50));
    expect(g.indicesInRect(reversed, 9), {0, 1, 4, 5});
    expect(g.indicesInRect(const Rect.fromLTWH(0, 0, 4, 4), 9), isEmpty, reason: 'padding only');
    expect(g.indicesInRect(const Rect.fromLTWH(0, 0, 1000, 1000), 6), {0, 1, 2, 3, 4, 5});
  });

  test('visibleRange covers the rows a viewport touches', () {
    expect(g.visibleRange(0, 200, 20), (0, 7), reason: 'rows 0 and 1');
    expect(g.visibleRange(117, 100, 20), (0, 7), reason: 'row 0 still shows its last 4 px');
    expect(g.visibleRange(125, 100, 20), (4, 7));
    expect(g.visibleRange(0, 1000, 6), (0, 5));
    expect(g.visibleRange(0, 200, 0), (0, -1));
  });

  test('columnsForPinch steps by one within the range', () {
    expect(FrameGridGeometry.columnsForPinch(4, 1.5), 3);
    expect(FrameGridGeometry.columnsForPinch(4, 0.5), 5);
    expect(FrameGridGeometry.columnsForPinch(4, 1.0), 4);
    expect(FrameGridGeometry.columnsForPinch(kFramesMinColumns, 2.0), kFramesMinColumns);
    expect(FrameGridGeometry.columnsForPinch(kFramesMaxColumns, 0.1), kFramesMaxColumns);
  });
}
