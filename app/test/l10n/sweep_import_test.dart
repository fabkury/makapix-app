// T4 sweeps: the crop page (import mode and canvas mode) and the place page — batch E3.
//
// Both pages have fixed-height status slots: a one-line gesture hint, a one- or two-line
// result sentence, and one-line placement and memory notes. The panel's height feeds the
// preview's fit scale, so the slots cannot grow; a translation that is longer than its slot
// is cut with an ellipsis. These sweeps fail on that.
//
// The pages decode real images, which needs the real event loop: each test runs inside
// `tester.runAsync` (the fake clock of a widget test never resolves a dart:ui codec future).
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/dialogs/crop_dialog.dart';
import 'package:makapix_club/editor/dialogs/place_dialog.dart';
import 'package:makapix_club/editor/dialogs/raster_preview.dart';

import 'l10n_test_support.dart';

Future<ui.Image> _solidImage(int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      Uint8List.fromList(List.filled(w * h * 4, 255)), w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

Future<Uint8List> _solidPng(int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF3060C0));
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// One page state: [build] makes the page around a preview it also returns, for disposal.
typedef _Case = Future<(Widget, FramePreview)> Function();

void _sweep(String name, _Case build) {
  group('sweep: $name', () {
    for (final locale in allLocales) {
      for (final size in kSweepSizes.entries) {
        testWidgets('$locale @ ${size.key}', (tester) async {
          final problems = <String>[];
          await tester.runAsync(() async {
            final (page, preview) = await build();
            await pumpLocalized(tester, locale, page, size: size.value);
            // The decode: real time, as long as it takes (a dozen 900 x 700 frames is the most).
            for (var i = 0; i < 100 && !preview.loaded; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 30));
            }
            await tester.pump();
            expect(preview.loaded, isTrue);
            if (size.key == 'phone') {
              final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
              await screenshot(tester, '${slug}_${locale.languageCode}', inRunAsync: true);
            }
            final err = tester.takeException();
            if (err != null) problems.add(err.toString().split('\n').first);
            problems.addAll(truncatedTexts(tester).map((t) => 'cut off: $t'));
            final lang = locale.languageCode;
            final left = switch (lang) {
              'ru' || 'ja' || 'zh' => leftoverLatin(tester),
              'en' => const <String>[],
              _ => leftoverEnglish(tester, lang),
            };
            problems.addAll(left.map((t) => 'not translated: "$t"'));
            await tester.pumpWidget(const MaterialApp(home: SizedBox()));
            await tester.pump();
            preview.dispose();
          });
          expect(problems, isEmpty);
        });
      }
    }
  });
}

void main() {
  // An oversize crop region kept 1:1, larger than the off-canvas area: the longest result line.
  _sweep('Crop page, import, oversize source', () async {
    final preview = CanvasPreview(
      srcW: 900,
      srcH: 700,
      totalFrames: 12,
      durationsUs: List.filled(12, 100000),
      composite: (f) => _solidImage(900, 700),
    );
    return (
      CropPage(
        preview: preview,
        srcW: 900,
        srcH: 700,
        canvasW: 64,
        canvasH: 64,
        gutterW: 64,
        gutterH: 64,
        initialRect: const Rect.fromLTWH(0, 0, 900, 700),
        initialNative: true,
      ),
      preview,
    );
  });

  // A region a little larger than the canvas: "the part beyond the canvas is kept off-canvas".
  _sweep('Crop page, import, region kept off-canvas', () async {
    final preview = CanvasPreview(
      srcW: 300,
      srcH: 200,
      totalFrames: 1,
      durationsUs: const [100000],
      composite: (f) => _solidImage(300, 200),
    );
    return (
      CropPage(
        preview: preview,
        srcW: 300,
        srcH: 200,
        canvasW: 64,
        canvasH: 64,
        gutterW: 64,
        gutterH: 64,
        initialRect: const Rect.fromLTWH(0, 0, 120, 100),
        initialNative: true,
      ),
      preview,
    );
  });

  // The same region scaled down to the canvas.
  _sweep('Crop page, import, region scaled to the canvas', () async {
    final preview = CanvasPreview(
      srcW: 300,
      srcH: 200,
      totalFrames: 1,
      durationsUs: const [100000],
      composite: (f) => _solidImage(300, 200),
    );
    return (
      CropPage(
        preview: preview,
        srcW: 300,
        srcH: 200,
        canvasW: 64,
        canvasH: 64,
        gutterW: 64,
        gutterH: 64,
        initialRect: const Rect.fromLTWH(0, 0, 120, 100),
        initialNative: false,
      ),
      preview,
    );
  });

  _sweep('Crop page, canvas', () async {
    final preview = CanvasPreview(
      srcW: 256,
      srcH: 256,
      totalFrames: 2,
      durationsUs: const [100000, 200000],
      composite: (f) => _solidImage(256, 256),
    );
    return (
      CropPage(
        mode: CropPageMode.canvas,
        preview: preview,
        srcW: 256,
        srcH: 256,
        canvasW: 256,
        canvasH: 256,
        contentBounds: const Rect.fromLTWH(20, 20, 100, 90),
        initialRect: const Rect.fromLTWH(10, 10, 100, 90),
      ),
      preview,
    );
  });

  // Hanging past the canvas on two edges and past the storage area on one: both placement
  // lines at once, with a memory budget nearly used up.
  _sweep('Place page, parked and dropped', () async {
    final preview = RasterPreview(await _solidPng(200, 200), srcW: 200, srcH: 200);
    return (
      PlacePage(
        preview: preview,
        srcRect: const Rect.fromLTWH(0, 0, 200, 200),
        canvasW: 64,
        canvasH: 64,
        gutterW: 64,
        gutterH: 64,
        placedW: 200,
        placedH: 200,
        startFrame: 11,
        memBudgetedBytes: 300 * 1024 * 1024,
        memHardBudget: 300 * 1024 * 1024 + 2048,
      ),
      preview,
    );
  });

  _sweep('Place page, fits', () async {
    final preview = RasterPreview(await _solidPng(32, 32), srcW: 32, srcH: 32);
    return (
      PlacePage(
        preview: preview,
        srcRect: const Rect.fromLTWH(0, 0, 32, 32),
        canvasW: 64,
        canvasH: 64,
        gutterW: 64,
        gutterH: 64,
        placedW: 32,
        placedH: 32,
        startFrame: 0,
        memBudgetedBytes: 10 * 1024 * 1024,
        memHardBudget: 256 * 1024 * 1024,
      ),
      preview,
    );
  });
}
