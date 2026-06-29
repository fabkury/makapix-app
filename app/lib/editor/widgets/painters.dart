import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CanvasPainter extends CustomPainter {
  final ui.Image? image;
  final double scale; // screen px per canvas px (view transform)
  final Offset off; // canvas top-left in screen px
  CanvasPainter(this.image, this.scale, this.off);
  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;
    final iw = image!.width.toDouble(), ih = image!.height.toDouble();
    final dst = Rect.fromLTWH(off.dx, off.dy, iw * scale, ih * scale);
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
/// SCREEN space. The arm reaches just beyond the box corner so it never sits under the shape.
class ShapeRotateHandlePainter extends CustomPainter {
  final Offset center, corner; // canvas-pixel coords
  final double rotation; // radians
  final double scale;
  final Offset off;
  const ShapeRotateHandlePainter(this.center, this.corner, this.rotation, this.scale, this.off);

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;
    Offset sc(Offset c) => Offset(off.dx + (c.dx + 0.5) * scale, off.dy + (c.dy + 0.5) * scale);
    final cs = sc(center), bs = sc(corner);
    final arm = (bs - cs).distance + 24.0;
    final ret = cs + Offset(math.cos(rotation), math.sin(rotation)) * (arm < 56.0 ? 56.0 : arm);
    canvas.drawLine(cs, ret, Paint()..color = Colors.black..strokeWidth = 4..isAntiAlias = true);
    canvas.drawLine(cs, ret, Paint()..color = const Color(0xFF4DA3FF)..strokeWidth = 2..isAntiAlias = true);
    canvas.drawCircle(ret, 11, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 4..isAntiAlias = true);
    canvas.drawCircle(ret, 11, Paint()..color = const Color(0xFF4DA3FF)..style = PaintingStyle.stroke..strokeWidth = 2.5..isAntiAlias = true);
    canvas.drawCircle(ret, 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(ShapeRotateHandlePainter o) =>
      o.center != center || o.corner != corner || o.rotation != rotation || o.scale != scale || o.off != off;
}

/// Screen-space radius of the Ruler's endpoint reticles. Also the grab radius for dragging an end
/// (shared with the gesture code), so "tap within the reticle to move that coordinate".
const double kRulerReticleRadius = 36.0;

/// The Ruler tool's overlay: a measurement line between two canvas points, a large draggable
/// reticle targeting each end, each end's X,Y, and the straight-line length in pixels. Drawn in
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

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: ' $text ',
        style: const TextStyle(fontSize: 11, color: Colors.white, backgroundColor: Color(0xCC000000)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
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
