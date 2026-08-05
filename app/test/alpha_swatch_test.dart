// AlphaSwatch's diagonal dual indicator — used by the row-2 palette swatches, the primary
// swatch, and the picker dialog's title swatch — must split a translucent color along the
// anti-diagonal: top-left triangle forced opaque, bottom-right its real alpha composited
// over the transparency checker. The cut runs corner to corner, so it has to adapt to both
// the tall (portrait) and wide (landscape) primary-swatch shapes; opaque colors must stay a
// plain undivided fill. These tests rasterize the widget and inspect actual pixels.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/widgets/painters.dart';

/// Rasterize an AlphaSwatch at its logical size and return the pixel bytes (straight RGBA).
Future<ByteData> render(WidgetTester tester, Color color, double w, double h) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: AlphaSwatch(color: color, width: w, height: h, diagonal: true),
        ),
      ),
    ),
  );
  // Rasterization and byte readback complete on the real event loop, which the test
  // binding's FakeAsync zone never pumps — without runAsync the awaits here hang forever.
  final bytes = await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage();
    final data = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
    img.dispose();
    return data;
  });
  return bytes!;
}

(int r, int g, int b, int a) px(ByteData bytes, int rowW, int x, int y) {
  final i = (y * rowW + x) * 4;
  return (bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2), bytes.getUint8(i + 3));
}

void main() {
  testWidgets('translucent color splits corner to corner in both orientations', (tester) async {
    // Half-alpha red over either checker gray composites to r≈208-228, g=b≈80-100 — pure red
    // and pure checker both fail these ranges, so the probes can land on either checker cell.
    void expectComposited((int, int, int, int) p, String where) {
      expect(p.$4, 255, reason: '$where: checker backing is opaque');
      expect(p.$1, inInclusiveRange(190, 245), reason: '$where: red over gray');
      expect(p.$2, p.$3, reason: '$where: gray shows equally through g and b');
      expect(p.$2, inInclusiveRange(55, 125), reason: '$where: gray shows through');
    }

    // Portrait primary swatch is 38×60 tall, landscape 60×38 wide.
    for (final (w, h) in [(38, 60), (60, 38)]) {
      final bytes = await render(tester, const Color(0x80FF0000), w.toDouble(), h.toDouble());
      final shape = '$w×$h';
      // The anti-diagonal runs (w,0)→(0,h) and crosses the center; 8 px above it is the
      // opaque top-left triangle, 8 px below the composited bottom-right one. A rectangular
      // split (either axis) or a main-diagonal cut would put at least one probe on the
      // wrong side.
      expect(px(bytes, w, 4, 4), (255, 0, 0, 255), reason: '$shape: top-left corner opaque');
      expect(px(bytes, w, w ~/ 2, h ~/ 2 - 8), (255, 0, 0, 255),
          reason: '$shape: above the anti-diagonal opaque');
      expectComposited(px(bytes, w, w ~/ 2, h ~/ 2 + 8), '$shape: below the anti-diagonal');
      expectComposited(px(bytes, w, w - 5, h - 5), '$shape: bottom-right corner');
    }
  });

  testWidgets('opaque color stays a plain undivided fill', (tester) async {
    const w = 38, h = 60;
    final bytes = await render(tester, const Color(0xFF00FF00), w.toDouble(), h.toDouble());
    for (final (x, y) in [(4, 4), (w ~/ 2, h ~/ 2 - 8), (w ~/ 2, h ~/ 2 + 8), (w - 5, h - 5)]) {
      expect(px(bytes, w, x, y), (0, 255, 0, 255), reason: 'plain fill at ($x,$y)');
    }
  });
}
