import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/dialogs/crop_dialog.dart';

// Mirror of the engine's fit_no_upscale (crates/engine/src/import.rs) so we can assert resultDims
// against the source of truth.
(int, int) fitNoUpscale(int rw, int rh, int cw, int ch) {
  if (rw <= cw && rh <= ch) return (rw, rh);
  if (rw * ch >= rh * cw) return (cw, (rh * cw ~/ rw).clamp(1, ch));
  return ((rw * ch ~/ rh).clamp(1, cw), ch);
}

void main() {
  group('CropGeometry defaults', () {
    test('canvas-size rect centered on a larger source', () {
      final g = CropGeometry(srcW: 100, srcH: 80, canvasW: 32, canvasH: 32);
      expect((g.w, g.h), (32, 32));
      expect((g.x, g.y), (34, 24)); // (100-32)/2, (80-32)/2
    });

    test('source smaller than canvas → whole source', () {
      final g = CropGeometry(srcW: 20, srcH: 16, canvasW: 32, canvasH: 32);
      expect((g.x, g.y, g.w, g.h), (0, 0, 20, 16));
    });
  });

  group('move + clamp', () {
    test('setOrigin clamps at all four edges', () {
      final g = CropGeometry(srcW: 100, srcH: 100, canvasW: 20, canvasH: 20); // 20x20 rect
      g.setOrigin(-50, -50);
      expect((g.x, g.y), (0, 0));
      g.setOrigin(999, 999);
      expect((g.x, g.y), (80, 80)); // srcW - w
    });
  });

  group('dragCorner', () {
    test('keeps opposite corner fixed and enforces min 1x1', () {
      final g = CropGeometry(srcW: 64, srcH: 64, canvasW: 32, canvasH: 32); // rect (16,16,32,32)
      final fixedBR = (g.x + g.w, g.y + g.h); // (48,48)
      g.dragCorner(CropCorner.topLeft, 20, 24); // drag top-left inward
      expect((g.x + g.w, g.y + g.h), fixedBR); // bottom-right unchanged
      expect(g.x, 20);
      expect(g.y, 24);
      expect(g.w >= 1 && g.h >= 1, true);
    });

    test('clamps to source bounds', () {
      final g = CropGeometry(srcW: 64, srcH: 64, canvasW: 32, canvasH: 32);
      // Drag bottom-right way past the edge — clamps to source.
      g.dragCorner(CropCorner.bottomRight, 999, 999);
      expect(g.x + g.w <= 64, true);
      expect(g.y + g.h <= 64, true);
    });
  });

  group('numeric setField', () {
    test('validates and clamps each field', () {
      final g = CropGeometry(srcW: 50, srcH: 50, canvasW: 10, canvasH: 10); // (20,20,10,10)
      g.setField('w', 999);
      expect(g.x + g.w <= 50, true);
      g.setField('h', 0);
      expect(g.h >= 1, true);
      g.setField('x', -5);
      expect(g.x, 0);
      g.setField('y', 999);
      expect(g.y + g.h <= 50, true);
    });
  });

  group('aspect lock', () {
    test('enabling snaps height to the canvas ratio', () {
      final g = CropGeometry(srcW: 200, srcH: 200, canvasW: 32, canvasH: 16); // ratio 2:1
      g.setField('w', 40);
      g.toggleAspectLock();
      expect(g.aspectLocked, true);
      expect(g.h, 20); // 40 / (32/16) = 20
    });

    test('editing width while locked recomputes height', () {
      final g = CropGeometry(srcW: 200, srcH: 200, canvasW: 32, canvasH: 16)..toggleAspectLock();
      g.setField('w', 60);
      expect(g.h, 30);
    });
  });

  group('resultDims mirrors the engine', () {
    test('equal to canvas → 1:1', () {
      final g = CropGeometry(srcW: 64, srcH: 64, canvasW: 32, canvasH: 32);
      g.setField('w', 32);
      g.setField('h', 32);
      expect(g.resultDims(), fitNoUpscale(32, 32, 32, 32));
      expect(g.resultDims(), (32, 32));
    });

    test('smaller than canvas → 1:1 centered (no upscale)', () {
      final g = CropGeometry(srcW: 64, srcH: 64, canvasW: 32, canvasH: 32);
      g.setField('w', 10);
      g.setField('h', 8);
      expect(g.resultDims(), (10, 8));
    });

    test('larger than canvas → downscaled, aspect preserved', () {
      final g = CropGeometry(srcW: 200, srcH: 200, canvasW: 16, canvasH: 16);
      g.setField('w', 32);
      g.setField('h', 16);
      expect(g.resultDims(), fitNoUpscale(32, 16, 16, 16));
      expect(g.resultDims(), (16, 8));
    });
  });

  testWidgets('CropPage pumps and disposes cleanly (no tick-after-dispose)', (tester) async {
    // Real image decoding (`instantiateImageCodec`/`toImage`) needs the real event loop, so the
    // whole flow runs inside `runAsync` — the fake test clock never resolves dart:ui codec futures.
    await tester.runAsync(() async {
      final bytes = await _solidPng(8, 8);
      await tester.pumpWidget(MaterialApp(
        home: CropPage(bytes: bytes, srcW: 8, srcH: 8, canvasW: 4, canvasH: 4),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50)); // let the decode resolve
      await tester.pump();
      // Replace the route → CropPage disposes. Must not throw (ticker + images disposed).
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
    });
    expect(tester.takeException(), isNull);
  });
}

Future<Uint8List> _solidPng(int w, int h) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF3060C0),
  );
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}
