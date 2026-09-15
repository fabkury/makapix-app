// The Place step's pure math (ADR 0019): the on-canvas size an import produces (mirroring the
// engine's placement paths), when the step applies, the placement geometry (engine-identical
// centering, free movement, clipping flags), the off-canvas gutter (ADR 0030: parked vs dropped,
// the memory estimate), and the shared preview's playback clock.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/dialogs/crop_dialog.dart';
import 'package:makapix_club/editor/dialogs/place_dialog.dart';
import 'package:makapix_club/editor/dialogs/raster_preview.dart';

void main() {
  group('importPlacedSize', () {
    test('a crop region: 1:1 when it fits, fitNoUpscale when larger', () {
      expect(importPlacedSize(srcW: 300, srcH: 300, canvasW: 64, canvasH: 64, mode: 2, crop: const Rect.fromLTWH(10, 10, 20, 16)),
          (w: 20, h: 16));
      expect(importPlacedSize(srcW: 300, srcH: 300, canvasW: 64, canvasH: 64, mode: 2, crop: const Rect.fromLTWH(0, 0, 128, 64)),
          (w: 64, h: 32));
      expect(fitNoUpscale(128, 64, 64, 64), (64, 32));
    });

    test('Stretch fills; Fit letterboxes by the binding axis; small 1:1 is its own size', () {
      expect(importPlacedSize(srcW: 300, srcH: 100, canvasW: 64, canvasH: 64, mode: 1), (w: 64, h: 64));
      expect(importPlacedSize(srcW: 300, srcH: 100, canvasW: 64, canvasH: 64, mode: 0), (w: 64, h: 21));
      expect(importPlacedSize(srcW: 16, srcH: 16, canvasW: 64, canvasH: 64, mode: 0), (w: 64, h: 64), reason: 'Fit upscales');
      final small = smallSourceImportArgs(scaleUp: false, srcW: 16, srcH: 12);
      expect(importPlacedSize(srcW: 16, srcH: 12, canvasW: 64, canvasH: 64, mode: small.mode, crop: small.crop), (w: 16, h: 12));
    });

    test('1:1 (Native, ADR 0030) is the source size, offered only within storage', () {
      expect(importPlacedSize(srcW: 300, srcH: 100, canvasW: 64, canvasH: 64, mode: kImportModeNative), (w: 300, h: 100));
      expect(nativeSizeOffered(300, 100, 192, 192), isFalse, reason: 'wider than the 3× storage');
      expect(nativeSizeOffered(192, 100, 192, 192), isTrue);
      expect(nativeSizeOffered(65, 65, 192, 192), isTrue);
    });
  });

  group('importPlacedSize with a crop under the Native code (ADR 0034)', () {
    test('the region keeps its size; the Crop code still downscales it', () {
      const crop = Rect.fromLTWH(0, 0, 128, 64);
      expect(importPlacedSize(srcW: 300, srcH: 300, canvasW: 64, canvasH: 64, mode: kImportModeNative, crop: crop),
          (w: 128, h: 64));
      expect(importPlacedSize(srcW: 300, srcH: 300, canvasW: 64, canvasH: 64, mode: 2, crop: crop), (w: 64, h: 32));
      expect(placementApplies((w: 128, h: 64), 64, 64), isTrue, reason: 'an oversize 1:1 crop goes through Place');
    });
  });

  group('placementApplies', () {
    test('whenever the result is not exactly the canvas', () {
      expect(placementApplies((w: 64, h: 64), 64, 64), isFalse, reason: 'exact / Stretch');
      expect(placementApplies((w: 64, h: 21), 64, 64), isTrue, reason: 'letterbox');
      expect(placementApplies((w: 16, h: 12), 64, 64), isTrue, reason: '1:1 small');
      expect(placementApplies((w: 20, h: 64), 64, 64), isTrue, reason: 'one dimension');
      expect(placementApplies((w: 300, h: 100), 64, 64), isTrue, reason: '1:1 oversize overhangs (ADR 0030)');
      expect(placementApplies((w: 64, h: 100), 64, 64), isTrue, reason: 'overhang on one axis only');
    });
  });

  group('PlaceGeometry gutter (ADR 0030)', () {
    // A 4×4 canvas with a full-canvas gutter: storage spans (-4,-4)…(8,8).
    PlaceGeometry g(int w, int h) => PlaceGeometry(canvasW: 4, canvasH: 4, w: w, h: h, gutterW: 4, gutterH: 4);

    test('storageRect and no-gutter default', () {
      expect(g(2, 2).storageRect, const Rect.fromLTWH(-4, -4, 12, 12));
      final plain = PlaceGeometry(canvasW: 4, canvasH: 4, w: 2, h: 2);
      expect(plain.storageRect, plain.canvasRect);
      plain.x = 5;
      expect(plain.nothingKept, isTrue, reason: 'without a gutter, off-canvas is beyond storage');
    });

    test('an oversize 1:1 import centers by truncating division and parks its overhang', () {
      final geo = g(6, 2);
      expect((geo.x, geo.y), (-1, 1)); // (4-6)/2 = -1, as the engine's i32 division
      expect(geo.fullyInside, isFalse);
      expect(geo.fullyKept, isTrue);
      expect(geo.visibleRect, const Rect.fromLTWH(0, 1, 4, 2));
      expect(geo.keptRect, geo.placedRect);
      expect(geo.parkedPixels, 4);
      expect(geo.droppedPixels, 0);
    });

    test('entirely off the canvas but inside storage is kept; beyond storage is dropped', () {
      final geo = g(2, 2);
      geo.x = 5;
      geo.y = -4;
      expect(geo.fullyOutside, isTrue);
      expect(geo.nothingKept, isFalse);
      expect(geo.parkedPixels, 4);
      geo.x = 7;
      geo.y = 7;
      expect(geo.keptRect, const Rect.fromLTWH(7, 7, 1, 1));
      expect(geo.droppedPixels, 3);
      expect(geo.parkedPixels, 1);
      geo.x = -9;
      geo.y = 0;
      expect(geo.nothingKept, isTrue);
      expect(geo.keptRect, Rect.zero);
    });
  });

  group('import memory estimate (ADR 0030)', () {
    test('frames × kept area × 4, never negative; the budget check needs a known budget', () {
      expect(importBytesEstimate(frames: 3, kept: const Rect.fromLTWH(-1, 0, 6, 2)), 3 * 12 * 4);
      expect(importBytesEstimate(frames: 0, kept: const Rect.fromLTWH(0, 0, 6, 2)), 0);
      expect(importBytesEstimate(frames: 2, kept: Rect.zero), 0);
      expect(importMayExceedBudget(estimate: 100, budgetedBytes: 50, hardBudget: 0), isFalse, reason: 'unknown budget');
      expect(importMayExceedBudget(estimate: 100, budgetedBytes: 50, hardBudget: 150), isFalse, reason: 'exactly at');
      expect(importMayExceedBudget(estimate: 101, budgetedBytes: 50, hardBudget: 150), isTrue);
    });
  });

  group('PlaceGeometry', () {
    test('starts centered exactly like the engine (truncating division)', () {
      final g = PlaceGeometry(canvasW: 64, canvasH: 64, w: 16, h: 12);
      expect((g.x, g.y), (24, 26));
      final odd = PlaceGeometry(canvasW: 7, canvasH: 7, w: 2, h: 2);
      expect((odd.x, odd.y), (2, 2)); // (7-2)/2 = 2.5 → 2, as the engine's i32 division
      expect(g.fullyInside, isTrue);
      expect(g.fullyOutside, isFalse);
    });

    test('nudge and direct set move freely; center() returns', () {
      final g = PlaceGeometry(canvasW: 64, canvasH: 64, w: 16, h: 12);
      g.nudge(-30, 0);
      expect(g.x, -6);
      expect(g.fullyInside, isFalse);
      expect(g.visibleRect, const Rect.fromLTWH(0, 26, 10, 12));
      g.x = 100;
      expect(g.fullyOutside, isTrue);
      expect(g.visibleRect, Rect.zero);
      g.center();
      expect((g.x, g.y), (24, 26));
    });

    test('visibleRect clips at every edge', () {
      final g = PlaceGeometry(canvasW: 8, canvasH: 8, w: 4, h: 4);
      g.x = -2;
      g.y = 6;
      expect(g.visibleRect, const Rect.fromLTWH(0, 6, 2, 2));
      g.x = 7;
      g.y = -3;
      expect(g.visibleRect, const Rect.fromLTWH(7, 0, 1, 1));
    });
  });

  group('RasterPreview.advance', () {
    test('static or single-frame previews never advance', () {
      final p = RasterPreview(Uint8List(0), srcW: 1, srcH: 1);
      expect(p.advance(0, const Duration(seconds: 5)), (0, Duration.zero));
      expect(p.animated, isFalse);
      expect(p.loaded, isFalse);
    });
  });
}
