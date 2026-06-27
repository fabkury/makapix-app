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
