import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CanvasPainter extends CustomPainter {
  final ui.Image? image;
  final double scale; // screen px per canvas px (view transform)
  final Offset off; // canvas top-left in screen px
  CanvasPainter(this.image, this.scale, this.off);

  /// Checkerboard cell size in SCREEN (logical) pixels. Deliberately independent of [scale]:
  /// pixels the user paints grow and shrink with the zoom while true transparency always shows
  /// the same-sized checker — that contrast is what lets a painted grey checker pattern be told
  /// apart from actual transparent pixels.
  static const double checkerCell = 8;

  // One 2×2-cell tile, tiled by an ImageShader. Same two greys the engine used when it baked
  // the checker into the display buffer, for visual continuity. The shader is anchored to the
  // VIEWPORT (identity matrix), not the image: zooming moves the image origin on screen, so an
  // origin-anchored pattern darts around during a pinch — a perfectly still backdrop is what
  // reads as "not part of the drawing".
  static final Paint _checkerPaint = _buildCheckerPaint();

  static Paint _buildCheckerPaint() {
    const c = checkerCell;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(const Rect.fromLTWH(0, 0, c * 2, c * 2), Paint()..color = const Color(0xFFC8C8C8));
    final dark = Paint()..color = const Color(0xFFA0A0A0);
    canvas.drawRect(const Rect.fromLTWH(c, 0, c, c), dark);
    canvas.drawRect(const Rect.fromLTWH(0, c, c, c), dark);
    final tile = rec.endRecording().toImageSync((c * 2).toInt(), (c * 2).toInt());
    return Paint()
      ..shader = ui.ImageShader(tile, TileMode.repeated, TileMode.repeated,
          Matrix4.identity().storage,
          filterQuality: FilterQuality.none);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;
    final iw = image!.width.toDouble(), ih = image!.height.toDouble();
    final dst = Rect.fromLTWH(off.dx, off.dy, iw * scale, ih * scale);
    // The transparency checker, under the artwork: fixed to the screen, clipped to the image.
    canvas.drawRect(dst, _checkerPaint);
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    canvas.drawImageRect(image!, Rect.fromLTWH(0, 0, iw, ih), dst, paint);
  }

  @override
  bool shouldRepaint(CanvasPainter old) => old.image != image || old.scale != scale || old.off != off;
}

// Thin, animated marching-ants selection outline drawn in SCREEN space (so it stays a
// hairline regardless of how large the canvas pixels are scaled).
class OutlinePainter extends CustomPainter {
  final List<List<int>> edges; // [x1,y1,x2,y2,t] in canvas-corner coords
  final double scale; // screen px per canvas px (view transform)
  final Offset off; // canvas top-left in screen px
  final Animation<double> anim;
  OutlinePainter(this.edges, this.scale, this.off, this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    if (edges.isEmpty || scale <= 0) return;
    final ox = off.dx, oy = off.dy;
    final phase = (anim.value * 4).floor(); // 4-unit marching period
    final dark = <Offset>[];
    final light = <Offset>[];
    for (final e in edges) {
      final p1 = Offset(ox + e[0] * scale, oy + e[1] * scale);
      final p2 = Offset(ox + e[2] * scale, oy + e[3] * scale);
      if (((e[4] + phase) % 4) < 2) {
        dark..add(p1)..add(p2);
      } else {
        light..add(p1)..add(p2);
      }
    }
    final black = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.4
      ..isAntiAlias = false;
    final white = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4
      ..isAntiAlias = false;
    canvas.drawPoints(ui.PointMode.lines, dark, black);
    canvas.drawPoints(ui.PointMode.lines, light, white);
  }

  @override
  bool shouldRepaint(OutlinePainter old) => true; // driven by the animation
}

/// The PRECISION-mode reticle footprint outline — deliberately distinct from the selection's
/// black/white marching ants ([OutlinePainter]) so an off-finger draw target is never mistaken for
/// a pixel selection. A continuous dark backing with amber dashes marching along it.
class CursorOutlinePainter extends CustomPainter {
  final List<List<int>> edges; // [x1,y1,x2,y2,t] in canvas-corner coords
  final double scale;
  final Offset off;
  final Animation<double> anim;
  CursorOutlinePainter(this.edges, this.scale, this.off, this.anim) : super(repaint: anim);

  static const _amber = Color(0xFFFFC400);

  @override
  void paint(Canvas canvas, Size size) {
    if (edges.isEmpty || scale <= 0) return;
    final ox = off.dx, oy = off.dy;
    final phase = (anim.value * 4).floor(); // 4-unit marching period
    final back = <Offset>[]; // full dark backing (continuous outline, for contrast)
    final dash = <Offset>[]; // amber dashes (the marching "on" segments)
    for (final e in edges) {
      final p1 = Offset(ox + e[0] * scale, oy + e[1] * scale);
      final p2 = Offset(ox + e[2] * scale, oy + e[3] * scale);
      back..add(p1)..add(p2);
      if (((e[4] + phase) % 4) < 2) dash..add(p1)..add(p2);
    }
    canvas.drawPoints(
        ui.PointMode.lines, back, Paint()..color = Colors.black..strokeWidth = 2.5..isAntiAlias = false);
    canvas.drawPoints(
        ui.PointMode.lines, dash, Paint()..color = _amber..strokeWidth = 1.6..isAntiAlias = false);
  }

  @override
  bool shouldRepaint(CursorOutlinePainter old) => true; // driven by the animation
}

/// Marching ants for an UNCOMMITTED selection draft (the Select Shape tool's draw → adjust → commit
/// flow). Deliberately a distinct cyan-on-dark identity from the committed selection's black/white
/// ants ([OutlinePainter]) — the two can show at once (existing selection + the draft about to be
/// combined into it), so the draft must never read as a live selection. The segments trace the exact
/// pixels the draft would select, so the preview matches what Commit produces (only the colour differs).
class SelectionDraftPainter extends CustomPainter {
  final List<List<int>> edges; // [x1,y1,x2,y2,t] in canvas-corner coords
  final double scale;
  final Offset off;
  final Animation<double> anim;
  SelectionDraftPainter(this.edges, this.scale, this.off, this.anim) : super(repaint: anim);

  static const _cyan = Color(0xFF00E5FF);

  @override
  void paint(Canvas canvas, Size size) {
    if (edges.isEmpty || scale <= 0) return;
    final ox = off.dx, oy = off.dy;
    final phase = (anim.value * 4).floor(); // 4-unit marching period (matches the selection ants)
    final back = <Offset>[]; // continuous dark backing for contrast against any pixels
    final dash = <Offset>[]; // cyan dashes (the marching "on" segments)
    for (final e in edges) {
      final p1 = Offset(ox + e[0] * scale, oy + e[1] * scale);
      final p2 = Offset(ox + e[2] * scale, oy + e[3] * scale);
      back..add(p1)..add(p2);
      if (((e[4] + phase) % 4) < 2) dash..add(p1)..add(p2);
    }
    canvas.drawPoints(
        ui.PointMode.lines, back, Paint()..color = const Color(0xCC04323B)..strokeWidth = 2.5..isAntiAlias = false);
    canvas.drawPoints(
        ui.PointMode.lines, dash, Paint()..color = _cyan..strokeWidth = 1.6..isAntiAlias = false);
  }

  @override
  bool shouldRepaint(SelectionDraftPainter old) => true; // driven by the animation
}

/// Draggable endpoint markers for an uncommitted figure (Line/Rect/Ellipse). Drawn in SCREEN
/// space as a ringed target at each endpoint so it stays a constant on-screen size and frames the
/// pixel without hiding it.
class HandlePainter extends CustomPainter {
  final List<Offset> points; // endpoint positions in canvas-pixel coords (cell top-left)
  final double scale; // screen px per canvas px
  final Offset off; // canvas top-left in screen px
  const HandlePainter(this.points, this.scale, this.off);

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;
    final r = (scale * 0.95).clamp(11.0, 22.0);
    final halo = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..isAntiAlias = true;
    final ring = Paint()
      ..color = const Color(0xFF4DA3FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..isAntiAlias = true;
    final dot = Paint()..color = Colors.white;
    for (final p in points) {
      final c = Offset(off.dx + (p.dx + 0.5) * scale, off.dy + (p.dy + 0.5) * scale);
      canvas.drawCircle(c, r, halo);
      canvas.drawCircle(c, r, ring);
      canvas.drawCircle(c, 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(HandlePainter old) =>
      old.points != points || old.scale != scale || old.off != off;
}

/// The Shape tool's rotate handle: a line from the box centre out to a draggable reticle, drawn in
/// SCREEN space. By default the arm reaches just beyond the box corner so it never sits under the
/// shape; an explicit [arm] (screen px) overrides that — the Rotate tool's draft uses it to pin the
/// reticle to the bbox's right border when un-rotated.
class ShapeRotateHandlePainter extends CustomPainter {
  final Offset center, corner; // canvas-pixel coords
  final double rotation; // radians
  final double scale;
  final Offset off;
  final double? arm; // screen-px arm length; null = just beyond the corner (min 56)
  const ShapeRotateHandlePainter(this.center, this.corner, this.rotation, this.scale, this.off, {this.arm});

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;
    Offset sc(Offset c) => Offset(off.dx + (c.dx + 0.5) * scale, off.dy + (c.dy + 0.5) * scale);
    final cs = sc(center), bs = sc(corner);
    final auto = (bs - cs).distance + 24.0;
    final ret = cs + Offset(math.cos(rotation), math.sin(rotation)) * (arm ?? (auto < 56.0 ? 56.0 : auto));
    canvas.drawLine(cs, ret, Paint()..color = Colors.black..strokeWidth = 4..isAntiAlias = true);
    canvas.drawLine(cs, ret, Paint()..color = const Color(0xFF4DA3FF)..strokeWidth = 2..isAntiAlias = true);
    canvas.drawCircle(ret, 11, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 4..isAntiAlias = true);
    canvas.drawCircle(ret, 11, Paint()..color = const Color(0xFF4DA3FF)..style = PaintingStyle.stroke..strokeWidth = 2.5..isAntiAlias = true);
    canvas.drawCircle(ret, 2.5, Paint()..color = Colors.white);
    // A tiny live degree readout, centred just above the connecting arm.
    final mid = Offset((cs.dx + ret.dx) / 2, (cs.dy + ret.dy) / 2);
    var perp = Offset(-(ret.dy - cs.dy), ret.dx - cs.dx);
    if (perp.distance > 0) perp = perp / perp.distance;
    if (perp.dy > 0) perp = -perp; // keep the label on the upper side of the line
    _degLabel(canvas, '${_degrees(rotation)}°', mid + perp * 13);
  }

  // Normalise radians to a signed whole degree in (-180, 180].
  int _degrees(double rad) {
    var d = (rad * 180 / math.pi) % 360;
    if (d > 180) d -= 360;
    return d.round();
  }

  void _degLabel(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: ' $text ',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white, backgroundColor: Color(0xCC000000)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(ShapeRotateHandlePainter o) =>
      o.center != center || o.corner != corner || o.rotation != rotation || o.scale != scale || o.off != off || o.arm != arm;
}

/// The Triangle's apex-skew handle: a faint rail along the (rotated) top edge with a diamond reticle
/// at the apex. Dragging the diamond slides the tip horizontally between the two base corners. Drawn
/// in SCREEN space. A distinct amber colour so it never reads as a size or rotate handle.
class TriangleTipHandlePainter extends CustomPainter {
  final Offset apex, railA, railB; // canvas-pixel coords (cell top-left)
  final double scale;
  final Offset off;
  const TriangleTipHandlePainter(this.apex, this.railA, this.railB, this.scale, this.off);

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;
    Offset sc(Offset c) => Offset(off.dx + (c.dx + 0.5) * scale, off.dy + (c.dy + 0.5) * scale);
    final a = sc(railA), b = sc(railB), ap = sc(apex);
    // The travel rail: the tip can only slide along here (parallel to the base).
    canvas.drawLine(a, b, Paint()..color = const Color(0x66000000)..strokeWidth = 4..isAntiAlias = true);
    canvas.drawLine(a, b, Paint()..color = const Color(0x99FFB300)..strokeWidth = 2..isAntiAlias = true);
    // A diamond reticle at the apex.
    const r = 9.0;
    final dia = Path()
      ..moveTo(ap.dx, ap.dy - r)
      ..lineTo(ap.dx + r, ap.dy)
      ..lineTo(ap.dx, ap.dy + r)
      ..lineTo(ap.dx - r, ap.dy)
      ..close();
    canvas.drawPath(dia, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 4..isAntiAlias = true);
    canvas.drawPath(dia, Paint()..color = const Color(0xFFFFB300)..isAntiAlias = true);
    canvas.drawCircle(ap, 2.0, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(TriangleTipHandlePainter o) =>
      o.apex != apex || o.railA != railA || o.railB != railB || o.scale != scale || o.off != off;
}

/// Screen-space radius of the Ruler's endpoint reticles. Also the grab radius for dragging an end
/// (shared with the gesture code), so "tap within the reticle to move that coordinate".
const double kRulerReticleRadius = 52.0;

/// The Ruler tool's overlay: a measurement line between two canvas points, a large draggable
/// reticle targeting each end, each end's X,Y, and the straight-line length in pixels — plus the
/// axis-aligned legs of the right triangle under the diagonal (the horizontal and vertical
/// distances), drawn semitransparent so the main measurement stays dominant. Drawn in
/// SCREEN space; never touches the pixel buffer.
class RulerPainter extends CustomPainter {
  final Offset a, b; // endpoints in canvas-pixel coords (cell top-left)
  final double scale; // screen px per canvas px
  final Offset off; // canvas top-left in screen px
  const RulerPainter(this.a, this.b, this.scale, this.off);

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;
    Offset sc(Offset c) => Offset(off.dx + (c.dx + 0.5) * scale, off.dy + (c.dy + 0.5) * scale);
    final pa = sc(a), pb = sc(b);
    // The axis-aligned legs of the measurement triangle (drawn first, so the main diagonal and
    // the reticles stay on top). Skipped when the diagonal is itself axis-aligned (the triangle
    // collapses onto the main line and the legs would just restate its length).
    final dxPx = (b.dx - a.dx).abs(), dyPx = (b.dy - a.dy).abs();
    if (dxPx >= 1 && dyPx >= 1) {
      final corner = Offset(pb.dx, pa.dy); // horizontal leg from A, vertical leg into B
      final haloF = Paint()..color = const Color(0x59000000)..strokeWidth = 3..isAntiAlias = true;
      final lineF = Paint()..color = const Color(0x59FFC400)..strokeWidth = 1.5..isAntiAlias = true;
      canvas.drawLine(pa, corner, haloF);
      canvas.drawLine(pa, corner, lineF);
      canvas.drawLine(corner, pb, haloF);
      canvas.drawLine(corner, pb, lineF);
      // Leg labels sit at each leg's midpoint, nudged to the OUTSIDE of the triangle so they
      // never collide with the diagonal's length label.
      final hMid = Offset((pa.dx + corner.dx) / 2, pa.dy + (pb.dy > pa.dy ? -18 : 8));
      final legRight = pb.dx >= pa.dx; // triangle interior is left of the vertical leg
      final vMid = Offset(corner.dx + (legRight ? 6 : -6), (corner.dy + pb.dy) / 2 - 7);
      _label(canvas, '${dxPx.round()} px', hMid, faint: true, centerX: true);
      _label(canvas, '${dyPx.round()} px', vMid, faint: true, alignRight: !legRight);
    }
    canvas.drawLine(pa, pb, Paint()..color = Colors.black..strokeWidth = 3..isAntiAlias = true);
    canvas.drawLine(pa, pb, Paint()..color = const Color(0xFFFFC400)..strokeWidth = 1.5..isAntiAlias = true);
    _reticle(canvas, pa);
    _reticle(canvas, pb);
    final len = (b - a).distance;
    const lbl = kRulerReticleRadius * 0.72;
    _label(canvas, '${a.dx.toInt()}, ${a.dy.toInt()}', pa + const Offset(lbl, lbl));
    _label(canvas, '${b.dx.toInt()}, ${b.dy.toInt()}', pb + const Offset(lbl, lbl));
    _label(canvas, '${len.toStringAsFixed(1)} px', Offset((pa.dx + pb.dx) / 2, (pa.dy + pb.dy) / 2));
  }

  // A gun-sight reticle: a ring with crosshair arms and a clear centre (so the target pixel shows).
  void _reticle(Canvas canvas, Offset c) {
    const r = kRulerReticleRadius;
    const gap = 6.0;
    final halo = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 3.5..isAntiAlias = true;
    final ring = Paint()..color = const Color(0xFFFFC400)..style = PaintingStyle.stroke..strokeWidth = 1.5..isAntiAlias = true;
    canvas.drawCircle(c, r, halo);
    canvas.drawCircle(c, r, ring);
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      final p1 = c + d * gap, p2 = c + d * r;
      canvas.drawLine(p1, p2, halo);
      canvas.drawLine(p1, p2, ring);
    }
    canvas.drawCircle(c, 1.8, Paint()..color = const Color(0xFFFFC400));
  }

  /// `faint` renders the semitransparent style of the triangle legs; `centerX` centres the text
  /// horizontally on `at`; `alignRight` puts the text's right edge at `at` (for labels that must
  /// grow away from the vertical leg).
  void _label(Canvas canvas, String text, Offset at,
      {bool faint = false, bool centerX = false, bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: ' $text ',
        style: faint
            ? const TextStyle(fontSize: 11, color: Colors.white70, backgroundColor: Color(0x66000000))
            : const TextStyle(fontSize: 11, color: Colors.white, backgroundColor: Color(0xCC000000)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var p = at;
    if (centerX) p = p.translate(-tp.width / 2, 0);
    if (alignRight) p = p.translate(-tp.width, 0);
    tp.paint(canvas, p);
  }

  @override
  bool shouldRepaint(RulerPainter old) => old.a != a || old.b != b || old.scale != scale || old.off != off;
}

/// The pixel grid: thin hairlines on every canvas-pixel boundary, drawn in SCREEN space so each
/// line stays 1 device pixel regardless of how large the canvas pixels are upscaled (unlike baking
/// it into the canvas, which produced thick, upscaled gridlines). Hidden when cells get too small
/// to be useful, so a zoomed-out large canvas doesn't turn into a grey wash.
class GridPainter extends CustomPainter {
  final int cols, rows; // canvas size in pixels
  final double scale; // screen px per canvas px
  final Offset off; // canvas top-left in screen px
  const GridPainter(this.cols, this.rows, this.scale, this.off);

  // Below this on-screen cell size the per-pixel grid is suppressed (too dense to read).
  static const double minCellPx = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale < minCellPx || cols <= 0 || rows <= 0) return;
    final paint = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = 0 // hairline: as thin as the device allows (1 device pixel)
      ..isAntiAlias = false;
    final x0 = off.dx, y0 = off.dy;
    final right = x0 + cols * scale, bottom = y0 + rows * scale;
    final lines = <Offset>[];
    for (var c = 0; c <= cols; c++) {
      final x = x0 + c * scale;
      lines..add(Offset(x, y0))..add(Offset(x, bottom));
    }
    for (var r = 0; r <= rows; r++) {
      final y = y0 + r * scale;
      lines..add(Offset(x0, y))..add(Offset(right, y));
    }
    canvas.drawPoints(ui.PointMode.lines, lines, paint);
  }

  @override
  bool shouldRepaint(GridPainter o) =>
      o.cols != cols || o.rows != rows || o.scale != scale || o.off != off;
}

/// A small two-tone checkerboard, used behind layer thumbnails so transparent areas read as
/// transparent (the layers film-strip shows each layer against a transparent background).
class CheckerPainter extends CustomPainter {
  const CheckerPainter();
  static const double cell = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFF3A3D42);
    final dark = Paint()..color = const Color(0xFF26282C);
    canvas.drawRect(Offset.zero & size, light);
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if ((r + c).isEven) continue;
        canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(CheckerPainter old) => false;
}
