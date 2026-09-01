// The Place step's pure math (ADR 0019): the on-canvas size an import produces (mirroring the
// engine's placement paths), when the step applies, the placement geometry (engine-identical
// centering, free movement, clipping flags), and the shared preview's playback clock.
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
  });

  group('placementApplies', () {
    test('only when the result leaves canvas uncovered', () {
      expect(placementApplies((w: 64, h: 64), 64, 64), isFalse, reason: 'exact / Stretch');
      expect(placementApplies((w: 64, h: 21), 64, 64), isTrue, reason: 'letterbox');
      expect(placementApplies((w: 16, h: 12), 64, 64), isTrue, reason: '1:1 small');
      expect(placementApplies((w: 20, h: 64), 64, 64), isTrue, reason: 'one dimension');
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
