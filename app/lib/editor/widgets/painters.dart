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
    final r = (scale * 0.8).clamp(8.0, 18.0);
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

/// Screen-space radius of the Ruler's endpoint reticles. Also the grab radius for dragging an end
/// (shared with the gesture code), so "tap within the reticle to move that coordinate".
const double kRulerReticleRadius = 28.0;

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
