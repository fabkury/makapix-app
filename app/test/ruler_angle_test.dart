// The Ruler's Angle mode is pure Dart overlay math (the engine never hears about the Ruler):
// an interior angle at vertex A between arms A→B and A→C, a default C spawned 30° off the
// baseline, and a degree chip whose anchor flips to the reflex side when the wedge is too
// narrow. These tests cover the pure functions plus a rasterized painter smoke test — no
// engine binary required.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/widgets/painters.dart';

/// Rasterize RulerPainter over a transparent surface and return straight-RGBA pixel bytes.
Future<ByteData> rasterize(Offset a, Offset b, Offset? c, double scale, Offset off, int outW, int outH) async {
  final rec = ui.PictureRecorder();
  RulerPainter(a, b, scale, off, c: c).paint(Canvas(rec), Size(outW.toDouble(), outH.toDouble()));
  final img = await rec.endRecording().toImage(outW, outH);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  img.dispose();
  return bytes!;
}

int alphaAt(ByteData b, int w, int x, int y) => b.getUint8((y * w + x) * 4 + 3);

/// Any non-transparent pixel in the (2r+1)² window around (cx,cy)? Sampled loosely because the
/// arc stroke is antialiased.
bool anyInk(ByteData b, int w, int cx, int cy, int r) {
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      if (alphaAt(b, w, x, y) > 0) return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rulerAngleDeg', () {
    const a = Offset.zero;
    test('perpendicular arms measure 90', () {
      expect(rulerAngleDeg(a, const Offset(10, 0), const Offset(0, 5)), closeTo(90, 1e-9));
    });
    test('collinear same-direction arms measure 0', () {
      expect(rulerAngleDeg(a, const Offset(10, 0), const Offset(20, 0)), closeTo(0, 1e-9));
    });
    test('opposite arms measure 180', () {
      expect(rulerAngleDeg(a, const Offset(10, 0), const Offset(-10, 0)), closeTo(180, 1e-9));
    });
    test('the 2:1 pixel slope reads 26.565 (why the label keeps one decimal)', () {
      expect(rulerAngleDeg(a, const Offset(10, 0), const Offset(10, 5)), closeTo(26.565, 0.01));
    });
    test('near-collinear arms never NaN (acos clamp)', () {
      final d = rulerAngleDeg(a, const Offset(10, 0), const Offset(20, 1e-7));
      expect(d, isNotNull);
      expect(d!.isNaN, isFalse);
    });
    test('a zero-length arm has no angle', () {
      expect(rulerAngleDeg(a, a, const Offset(0, 5)), isNull); // B == A
      expect(rulerAngleDeg(a, const Offset(10, 0), a), isNull); // C == A
    });
  });

  group('defaultRulerC', () {
    test('roughly baseline length, ~30 degrees off it, screen-CCW (above a rightward line)', () {
      const a = Offset(3, 7), b = Offset(13, 7);
      final c = defaultRulerC(a, b);
      expect((c - a).distance, closeTo((b - a).distance, 1.0)); // whole-cell rounding jitter
      expect(rulerAngleDeg(a, b, c), closeTo(30, 4));
      expect(c.dy, lessThan(a.dy)); // screen-CCW: y grows down, so "above" is smaller y
    });
    test('spawns on whole cells — A/B are whole cells and a fractional C would stick forever '
        '(the grab-offset drag preserves the fraction), skewing snapped angles off 90.0', () {
      const a = Offset(3, 7), b = Offset(13, 7);
      final c = defaultRulerC(a, b);
      expect(c.dx, c.dx.roundToDouble());
      expect(c.dy, c.dy.roundToDouble());
    });
    test('degenerate A==B still yields a grabbable whole-cell point away from A', () {
      const a = Offset(5, 5);
      final c = defaultRulerC(a, a);
      expect((c - a).distance, greaterThan(1));
      expect(c.dx, c.dx.roundToDouble());
      expect(c.dy, c.dy.roundToDouble());
    });
  });

  group('angleLabelAnchor', () {
    const pa = Offset.zero;
    double interiorDot(Offset anchor, Offset pb, Offset pc) {
      final u = (pb - pa) / (pb - pa).distance, v = (pc - pa) / (pc - pa).distance;
      final s = u + v;
      return (anchor - pa).dx * s.dx + (anchor - pa).dy * s.dy;
    }

    test('wide angle: chip sits inside the wedge (interior bisector side)', () {
      const pb = Offset(100, 0), pc = Offset(0, 100);
      final anchor = angleLabelAnchor(pa, pb, pc, kRulerAngleArcRadius);
      expect(interiorDot(anchor, pb, pc), greaterThan(0));
    });
    test('narrow angle: chip flips to the reflex side so it never crams between the arms', () {
      const pb = Offset(100, 0);
      final pc = Offset(100 * 0.9848, 100 * 0.1736); // ~10 degrees off the baseline
      final anchor = angleLabelAnchor(pa, pb, pc, kRulerAngleArcRadius);
      expect(interiorDot(anchor, pb, pc), lessThan(0));
    });
    test('straight arms (180): bisector vanishes but the anchor stays finite', () {
      const pb = Offset(100, 0), pc = Offset(-100, 0);
      final anchor = angleLabelAnchor(pa, pb, pc, kRulerAngleArcRadius);
      expect(anchor.dx.isFinite && anchor.dy.isFinite, isTrue);
      expect((anchor - pa).distance, greaterThan(kRulerAngleArcRadius));
    });
    test('degenerate arm: fallback anchor above the vertex', () {
      final anchor = angleLabelAnchor(pa, pa, const Offset(9, 0), kRulerAngleArcRadius);
      expect(anchor.dy, lessThan(0));
    });
  });

  group('RulerPainter', () {
    test('angle mode paints the vertex arc; length mode leaves that spot untouched', () async {
      // a=(0,0) b=(10,0) c=(0,10) at scale 10, off (60,60): vertex pa=(65,65), 90-degree arms
      // along +x and +y. The arc (radius 28) crosses the diagonal at pa + 28/sqrt(2)*(1,1).
      const a = Offset.zero, b = Offset(10, 0), c = Offset(0, 10);
      const scale = 10.0, off = Offset(60, 60);
      const probeX = 65 + 19, probeY = 65 + 19; // ≈ pa + 28·(cos45, sin45)
      final withC = await rasterize(a, b, c, scale, off, 240, 240);
      final withoutC = await rasterize(a, b, null, scale, off, 240, 240);
      expect(anyInk(withC, 240, probeX, probeY, 3), isTrue, reason: 'arc missing in angle mode');
      expect(anyInk(withoutC, 240, probeX, probeY, 3), isFalse,
          reason: 'length mode painted where only the arc should be');
    });
    test('angle mode drops the faint dx/dy leg triangles (main lines only)', () async {
      // Diagonal baseline a=(0,0) b=(10,6) at scale 10, off (60,60): the horizontal leg's corner
      // sits at (pb.dx, pa.dy) = (165, 65) — well clear of the reticles, the main lines, the arc,
      // and every label. Legs must paint there in Length mode and nothing in Angle mode.
      const a = Offset.zero, b = Offset(10, 6), c = Offset(0, 10);
      const scale = 10.0, off = Offset(60, 60);
      final lengthMode = await rasterize(a, b, null, scale, off, 240, 240);
      final angleMode = await rasterize(a, b, c, scale, off, 240, 240);
      expect(anyInk(lengthMode, 240, 165, 65, 1), isTrue, reason: 'legs missing in length mode');
      expect(anyInk(angleMode, 240, 165, 65, 1), isFalse, reason: 'legs painted in angle mode');
    });
    test('shouldRepaint keys on c', () {
      const p = RulerPainter(Offset.zero, Offset(10, 0), 10, Offset.zero, c: Offset(0, 10));
      const same = RulerPainter(Offset.zero, Offset(10, 0), 10, Offset.zero, c: Offset(0, 10));
      const noC = RulerPainter(Offset.zero, Offset(10, 0), 10, Offset.zero);
      expect(p.shouldRepaint(same), isFalse);
      expect(p.shouldRepaint(noC), isTrue);
      expect(noC.shouldRepaint(p), isTrue);
    });
  });
}
