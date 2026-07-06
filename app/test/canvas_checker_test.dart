// The transparency checker is drawn by CanvasPainter in SCREEN space at a fixed cell size —
// it must NOT scale with the zoom (that contrast is what distinguishes painted grey checkers
// from true transparency). These tests rasterize the painter and inspect actual pixels.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/widgets/painters.dart';
import 'package:makapix_club/engine_ffi.dart';

const light = Color(0xFFC8C8C8);
const dark = Color(0xFFA0A0A0);

/// A w×h ui.Image that is fully transparent except an opaque red rect (if given).
ui.Image sourceImage(int w, int h, {Rect? red}) {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  if (red != null) canvas.drawRect(red, Paint()..color = const Color(0xFFFF0000)..isAntiAlias = false);
  return rec.endRecording().toImageSync(w, h);
}

/// Rasterize CanvasPainter over a surface and return the pixel bytes (straight RGBA).
Future<ByteData> rasterize(ui.Image src, double scale, Offset off, int outW, int outH) async {
  final rec = ui.PictureRecorder();
  CanvasPainter(src, scale, off).paint(Canvas(rec), Size(outW.toDouble(), outH.toDouble()));
  final img = await rec.endRecording().toImage(outW, outH);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  img.dispose();
  return bytes!;
}

Color pixel(ByteData b, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return Color.fromARGB(
      b.getUint8(i + 3), b.getUint8(i), b.getUint8(i + 1), b.getUint8(i + 2));
}

void main() {
  const cell = CanvasPainter.checkerCell; // 8 screen px

  test('checker cell size is the same at different zoom levels', () async {
    final src = sourceImage(4, 4); // fully transparent canvas
    for (final scale in [10.0, 20.0]) {
      final bytes = await rasterize(src, scale, Offset.zero, 40, 40);
      // Tile layout anchored at the origin: light cell at (0,0), dark to its right and below.
      expect(pixel(bytes, 40, cell ~/ 2, cell ~/ 2), light, reason: 'scale $scale');
      expect(pixel(bytes, 40, cell ~/ 2 + cell.toInt(), cell ~/ 2), dark, reason: 'scale $scale');
      expect(pixel(bytes, 40, cell ~/ 2, cell ~/ 2 + cell.toInt()), dark, reason: 'scale $scale');
      // One cell in from the corner diagonally: light again — the period is 2 cells in SCREEN
      // px at BOTH scales. A checker baked into the canvas image would have doubled here.
      expect(pixel(bytes, 40, cell ~/ 2 + 2 * cell.toInt(), cell ~/ 2), light, reason: 'scale $scale');
    }
  });

  test('checker stays within the image bounds', () async {
    final src = sourceImage(2, 2);
    // 2×2 canvas at 10× sits at (5,5)-(25,25); outside must stay untouched (transparent).
    final bytes = await rasterize(src, 10, const Offset(5, 5), 40, 40);
    expect(pixel(bytes, 40, 2, 2).a, 0.0);
    expect(pixel(bytes, 40, 30, 30).a, 0.0);
    expect(pixel(bytes, 40, 10, 10).a, 1.0); // inside: checker
  });

  test('opaque artwork pixels cover the checker', () async {
    final src = sourceImage(4, 4, red: const Rect.fromLTWH(0, 0, 1, 1));
    final bytes = await rasterize(src, 10, Offset.zero, 40, 40);
    expect(pixel(bytes, 40, 5, 5), const Color(0xFFFF0000)); // inside the red canvas pixel
    expect(pixel(bytes, 40, 15, 5).a, 1.0); // transparent neighbour shows opaque checker
    expect(pixel(bytes, 40, 15, 5), isNot(const Color(0xFFFF0000)));
  });

  Future<ByteData> decodeStraightReadback(Uint8List rgba) async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, 1, 1, ui.PixelFormat.rgba8888, c.complete);
    final img = await c.future;
    final out = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
    img.dispose();
    return out;
  }

  test('CANARY: the raw rgba8888 decode treats bytes as premultiplied', () async {
    // This is WHY premultiplyRgbaInPlace exists: straight (100, 0, 0, 128) misread as
    // premultiplied reads back as ~(199, 0, 0, 128). If Flutter ever changes these semantics,
    // this fails and the premultiply step must be removed with it.
    final out = await decodeStraightReadback(Uint8List.fromList([100, 0, 0, 128]));
    expect(out.getUint8(0), closeTo(199, 3));
    expect(out.getUint8(3), 128);
  });

  test('engine straight-alpha bytes survive decode after premultiplyRgbaInPlace', () async {
    // The engine emits STRAIGHT RGBA (buffer.to_rgba_bytes). With the checker no longer baked
    // in, the display buffer carries real transparency for the first time, so this conversion
    // is load-bearing: translucent pixels (alpha paint, onion skin, drafts) would otherwise
    // render too bright.
    final bytes = Uint8List.fromList([100, 0, 0, 128]);
    premultiplyRgbaInPlace(bytes);
    final out = await decodeStraightReadback(bytes);
    expect(out.getUint8(0), closeTo(100, 3)); // red survives (± premul/unpremul rounding)
    expect(out.getUint8(3), 128);

    final edge = Uint8List.fromList([10, 20, 30, 0, 1, 2, 3, 255]);
    premultiplyRgbaInPlace(edge);
    expect(edge, [0, 0, 0, 0, 1, 2, 3, 255]); // a=0 zeroes out; a=255 untouched
  });

  test('checker pattern is fixed to the viewport (stays still under pan and zoom)', () async {
    final src = sourceImage(4, 4);
    // The same screen point shows the same checker colour while the artwork pans/zooms under
    // it — a pattern anchored to the image origin would dart around during a pinch.
    final a = await rasterize(src, 10, Offset.zero, 40, 40);
    final b = await rasterize(src, 13, const Offset(3, 7), 40, 40);
    for (final p in const [(12, 12), (20, 20), (28, 28)]) {
      // points inside the image rect in BOTH renders
      expect(pixel(b, 40, p.$1, p.$2), pixel(a, 40, p.$1, p.$2));
    }
  });
}
