// Stage overlay painters — the Animator's screen-space overlays over the reused editor
// CanvasPainter (selection box, pivot reticle, snap guides). All painters take the view's
// (scale, offset) and convert canvas coords on the fly, so strokes stay hairline at any zoom
// (the editor painters' convention).
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

const Color kAnimAccent = Color(0xFF4080C0);

/// Dashed axis-aligned bounding box + corner ticks around the selected Actor.
class ActorBoxPainter extends CustomPainter {
  final Rect boundsCanvas; // evaluated AABB in scene px
  final double scale;
  final Offset off;
  final bool dragging;
  const ActorBoxPainter(this.boundsCanvas, this.scale, this.off, {this.dragging = false});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      off.dx + boundsCanvas.left * scale,
      off.dy + boundsCanvas.top * scale,
      boundsCanvas.width * scale,
      boundsCanvas.height * scale,
    ).inflate(2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dragging ? 2.0 : 1.4
      ..color = dragging ? Colors.amber : kAnimAccent;

    // Dashes: walk the perimeter in fixed screen-px segments.
    const dash = 6.0, gap = 4.0;
    final path = Path()..addRect(r);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
    // Corner ticks.
    final tick = Paint()
      ..color = paint.color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas.drawPoints(PointMode.points, [c], tick);
    }
  }

  @override
  bool shouldRepaint(ActorBoxPainter old) =>
      old.boundsCanvas != boundsCanvas ||
      old.scale != scale ||
      old.off != off ||
      old.dragging != dragging;
}

/// The pivot reticle: a crosshair + circle at the Actor's pivot point.
class PivotHandlePainter extends CustomPainter {
  final Offset pivotCanvas; // continuous scene px
  final double scale;
  final Offset off;
  final bool grabbed;
  const PivotHandlePainter(this.pivotCanvas, this.scale, this.off, {this.grabbed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(off.dx + pivotCanvas.dx * scale, off.dy + pivotCanvas.dy * scale);
    final color = grabbed ? Colors.amber : Colors.cyanAccent;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grabbed ? 2.2 : 1.6
      ..color = color;
    canvas.drawCircle(c, 9, ring);
    final hair = Paint()
      ..strokeWidth = 1.2
      ..color = color;
    canvas.drawLine(c - const Offset(14, 0), c - const Offset(4, 0), hair);
    canvas.drawLine(c + const Offset(4, 0), c + const Offset(14, 0), hair);
    canvas.drawLine(c - const Offset(0, 14), c - const Offset(0, 4), hair);
    canvas.drawLine(c + const Offset(0, 4), c + const Offset(0, 14), hair);
  }

  @override
  bool shouldRepaint(PivotHandlePainter old) =>
      old.pivotCanvas != pivotCanvas ||
      old.scale != scale ||
      old.off != off ||
      old.grabbed != grabbed;
}

/// A snap guide to draw during a snapped drag.
class SnapGuide {
  /// Vertical guide at canvas x (null = none) / horizontal at canvas y.
  final double? x;
  final double? y;

  /// Rotation badge text ("15°"), drawn near the badge anchor when set.
  final String? badge;
  final Offset? badgeAnchorCanvas;
  const SnapGuide({this.x, this.y, this.badge, this.badgeAnchorCanvas});
}

/// Hairline alignment guides + the rotation-stop badge during snapped drags.
class SnapGuidePainter extends CustomPainter {
  final List<SnapGuide> guides;
  final double scale;
  final Offset off;
  const SnapGuidePainter(this.guides, this.scale, this.off);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..strokeWidth = 1
      ..color = Colors.amber.withValues(alpha: 0.8);
    for (final g in guides) {
      if (g.x != null) {
        final sx = off.dx + g.x! * scale;
        canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), line);
      }
      if (g.y != null) {
        final sy = off.dy + g.y! * scale;
        canvas.drawLine(Offset(0, sy), Offset(size.width, sy), line);
      }
      if (g.badge != null && g.badgeAnchorCanvas != null) {
        final anchor = Offset(
          off.dx + g.badgeAnchorCanvas!.dx * scale,
          off.dy + g.badgeAnchorCanvas!.dy * scale - 24,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: g.badge,
            style: const TextStyle(
                fontSize: 11, color: Colors.black, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final rect = Rect.fromCenter(
            center: anchor, width: tp.width + 10, height: tp.height + 6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()..color = Colors.amber,
        );
        tp.paint(canvas, rect.topLeft + const Offset(5, 3));
      }
    }
  }

  @override
  bool shouldRepaint(SnapGuidePainter old) =>
      old.guides != guides || old.scale != scale || old.off != off;
}
