import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/dialogs/crop_dialog.dart';
import 'package:makapix_club/editor/dialogs/raster_preview.dart';

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

  group('CropView (zoom + pan)', () {
    CropView view() => CropView(srcW: 100, srcH: 50)..setView(const Size(432, 232)); // fit = 4 px/px

    test('fit: 1 = fit-to-screen, centered, pan pinned to zero', () {
      final v = view();
      expect(v.fitScale, 4);
      expect(v.scale, 4);
      expect(v.origin, const Offset(16, 16));
      expect(v.isFit, isTrue);
      v.panBy(const Offset(50, 50));
      expect(v.pan, Offset.zero, reason: 'no panning at fit');
    });

    test('maxZoom puts 32 screen px on one source px; zoom never drops below fit', () {
      final v = view();
      expect(v.maxZoom, 8);
      v.zoomAt(const Offset(100, 100), 100);
      expect(v.zoom, 8);
      expect(v.scale, 32);
      v.zoomAt(const Offset(100, 100), 0.1);
      expect(v.zoom, 1);
    });

    test('zoomAt keeps the source point under the pointer fixed', () {
      final v = view();
      const p = Offset(116, 66); // source (25, 12.5) at fit
      final sx = (p.dx - v.origin.dx) / v.scale, sy = (p.dy - v.origin.dy) / v.scale;
      v.zoomAt(p, 3);
      expect(((p.dx - v.origin.dx) / v.scale - sx).abs(), lessThan(1e-9));
      expect(((p.dy - v.origin.dy) / v.scale - sy).abs(), lessThan(1e-9));
      expect(v.srcX(p.dx), 25);
    });

    test('pan is clamped so the image keeps CropView.keep px inside the viewport', () {
      final v = view();
      v.zoomAt(const Offset(216, 116), 4); // 1600×800 image in a 432×232 viewport
      v.panBy(const Offset(-99999, -99999));
      expect(v.origin.dx, CropView.keep - 100 * v.scale);
      expect(v.origin.dy, CropView.keep - 50 * v.scale);
      v.panBy(const Offset(99999, 99999));
      expect(v.origin.dx, 432 - CropView.keep);
      expect(v.origin.dy, 232 - CropView.keep);
    });

    test('double-tap toggles fit ↔ 4× about the tapped point; fit() resets everything', () {
      final v = view();
      v.toggleDoubleTap(const Offset(50, 40));
      expect(v.zoom, 4);
      expect(v.srcX(50), 9); // (50-16)/4 = 8.5 → rounds to 9; the same source column stays under the finger
      v.toggleDoubleTap(const Offset(300, 100));
      expect(v.isFit, isTrue);
      v.zoomAt(const Offset(10, 10), 2);
      v.panBy(const Offset(30, 0));
      v.fit();
      expect((v.zoom, v.pan), (1.0, Offset.zero));
    });

    test('a viewport change re-clamps the pan instead of stranding the image', () {
      final v = view();
      v.zoomAt(const Offset(216, 116), 4);
      v.panBy(const Offset(99999, 0));
      v.setView(const Size(232, 232));
      expect(v.origin.dx, lessThanOrEqualTo(232 - CropView.keep));
    });
  });

  group('import size class (streamlined dialog)', () {
    test('exact / small / large', () {
      expect(importSizeClass(32, 32, 32, 32), ImportSizeClass.exact);
      expect(importSizeClass(20, 32, 32, 32), ImportSizeClass.small);
      expect(importSizeClass(1, 1, 32, 32), ImportSizeClass.small);
      expect(importSizeClass(33, 10, 32, 32), ImportSizeClass.large, reason: 'wider in one dimension');
      expect(importSizeClass(10, 40, 32, 32), ImportSizeClass.large);
      expect(importSizeClass(300, 300, 32, 32), ImportSizeClass.large);
    });

    test('small source: 1:1 centered = whole-source crop; scale-up = Fit', () {
      final asIs = smallSourceImportArgs(scaleUp: false, srcW: 20, srcH: 16);
      expect(asIs.mode, 2);
      expect(asIs.crop, const Rect.fromLTWH(0, 0, 20, 16));
      final up = smallSourceImportArgs(scaleUp: true, srcW: 20, srcH: 16);
      expect((up.mode, up.crop), (0, null));
    });
  });

  testWidgets('CropPage pumps and disposes cleanly (no tick-after-dispose)', (tester) async {
    // Real image decoding (`instantiateImageCodec`/`toImage`) needs the real event loop, so the
    // whole flow runs inside `runAsync` — the fake test clock never resolves dart:ui codec futures.
    await tester.runAsync(() async {
      final bytes = await _solidPng(8, 8);
      final preview = RasterPreview(bytes, srcW: 8, srcH: 8);
      await tester.pumpWidget(MaterialApp(
        home: CropPage(preview: preview, srcW: 8, srcH: 8, canvasW: 4, canvasH: 4),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50)); // let the decode resolve
      await tester.pump();
      expect(preview.loaded, isTrue);
      // Replace the route → CropPage disposes. Must not throw (ticker gone, preview still owned
      // by the flow); then the flow disposes the preview.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      preview.dispose();
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
