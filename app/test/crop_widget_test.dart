import 'dart:async';
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

    test('zoom buttons: 1.5x steps about the viewport center, clamped, with the View readout', () {
      final v = view();
      expect(v.label, 'View: fit to screen');
      expect(v.canZoomIn, isTrue);
      v.zoomStep(inward: false); // at fit already: stays at fit
      expect(v.isFit, isTrue);
      v.zoomStep(inward: true);
      expect(v.zoom, closeTo(1.5, 1e-9));
      expect(v.label, 'View: 150%');
      // Stepping about the center keeps the image centered (pan stays zero).
      expect(v.pan, Offset.zero);
      while (v.canZoomIn) {
        v.zoomStep(inward: true);
      }
      expect(v.zoom, closeTo(v.maxZoom, 1e-9));
      v.zoomStep(inward: true); // no-op past the ceiling
      expect(v.zoom, closeTo(v.maxZoom, 1e-9));
      v.zoomStep(inward: false);
      expect(v.zoom, closeTo(v.maxZoom / CropView.stepFactor, 1e-9));
    });

    test('setMargins: a wider horizontal margin shrinks the fit and re-clamps the pan', () {
      final v = view(); // 100x50 in 432x232 at margin 16 → 4 px/px
      expect(v.fitScale, closeTo(4, 1e-9));
      v.setMargins(x: 41, y: 16); // (432 − 82) / 100 = 3.5
      expect(v.fitScale, closeTo(3.5, 1e-9));
      expect(v.origin.dx, closeTo(41, 1e-9)); // centered: the image starts past the margin
      expect(v.pan, Offset.zero); // still at fit
      v.setMargins(x: 41, y: 16); // no-op when equal
      expect(v.fitScale, closeTo(3.5, 1e-9));
      v.setMargins(x: 16, y: 16);
      expect(v.fitScale, closeTo(4, 1e-9));
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

  group('Crop canvas geometry (ADR 0027)', () {
    test('setRect clips to the source and rejects an empty clip; isWhole', () {
      final g = CropGeometry(srcW: 32, srcH: 32, canvasW: 32, canvasH: 32);
      expect(g.isWhole, isTrue); // canvas == source: the default rect is the whole canvas
      expect(g.setRect(-4, -4, 12, 12), isTrue); // a selection reaching into the gutter
      expect((g.x, g.y, g.w, g.h), (0, 0, 8, 8));
      expect(g.isWhole, isFalse);
      expect(g.setRect(40, 40, 4, 4), isFalse); // fully outside: unchanged
      expect((g.x, g.y, g.w, g.h), (0, 0, 8, 8));
      expect(g.setRect(28, 30, 10, 10), isTrue);
      expect((g.x, g.y, g.w, g.h), (28, 30, 4, 2));
    });

    test('setSize keeps the top-left, shifts to stay inside, and releases a violated lock', () {
      final g = CropGeometry(srcW: 64, srcH: 32, canvasW: 64, canvasH: 32);
      g.setRect(50, 20, 4, 4);
      g.setSize(32, 32); // would overflow both edges → shifted, never shrunk
      expect((g.x, g.y, g.w, g.h), (32, 0, 32, 32));
      g.setSize(128, 128); // larger than the source → the whole source
      expect(g.isWhole, isTrue);
      g.toggleAspectLock(); // 2:1
      g.setSize(16, 16); // a square preset on a 2:1 canvas releases the lock
      expect(g.aspectLocked, isFalse);
      expect((g.w, g.h), (16, 16));
    });
  });

  testWidgets('CropPage in canvas mode: composited preview, disabled OK on the whole canvas, Trim', (tester) async {
    await tester.runAsync(() async {
      var composites = 0;
      final preview = CanvasPreview(
        srcW: 8,
        srcH: 8,
        totalFrames: 2,
        durationsUs: const [100000, 200000],
        composite: (f) {
          composites++;
          return _solidImage(8, 8);
        },
      );
      await tester.pumpWidget(MaterialApp(
        home: CropPage(
          mode: CropPageMode.canvas,
          preview: preview,
          srcW: 8,
          srcH: 8,
          canvasW: 8,
          canvasH: 8,
          contentBounds: const Rect.fromLTWH(2, 2, 3, 3),
          sizeNote: (w, h) => Text('note $w×$h'),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      expect(preview.loaded, isTrue);
      expect(preview.animated, isTrue);
      expect(composites, 2);
      expect(preview.durations, const [Duration(milliseconds: 100), Duration(milliseconds: 200)]);
      expect(find.text('Crop canvas'), findsOneWidget);
      expect(find.text('New canvas: 8 × 8 px'), findsOneWidget);
      expect(find.text('note 8×8'), findsOneWidget);
      expect(find.text('Presets'), findsOneWidget);
      final crop = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Crop'));
      expect(crop.onPressed, isNull, reason: 'the whole canvas has nothing to crop');
      await tester.tap(find.byTooltip('Trim to content'));
      await tester.pump();
      expect(find.text('New canvas: 3 × 3 px'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Crop')).onPressed, isNotNull);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      preview.dispose();
    });
    expect(tester.takeException(), isNull);
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

Future<ui.Image> _solidImage(int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(Uint8List.fromList(List.filled(w * h * 4, 255)), w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
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
