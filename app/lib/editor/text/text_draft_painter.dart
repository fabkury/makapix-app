// What the shell draws for the Text tool on top of the canvas (ADR 0039). The glyph pixels
// themselves are NOT here: the engine previews them inside the composite, exactly as a commit
// would write them. These painters add the things that are never pixels — the Text Draft's
// box, its Wrap-width handle, and the Missing-glyph markers — plus the mask sample the font
// picker shows.
// l10n-ignore-file: no display text.
import 'package:flutter/material.dart';

import 'text_layout.dart';

/// The Text Draft's chrome, in SCREEN space: an outline around the layout box, a round handle
/// on its right edge (drag it to set the Wrap width), and a hollow amber box wherever the Font
/// cannot draw a character. Positions are canvas pixels; [scale]/[off] are the view transform.
class TextDraftPainter extends CustomPainter {
  const TextDraftPainter({
    required this.box,
    required this.markers,
    required this.wrapped,
    required this.scale,
    required this.off,
  });

  /// The layout box in canvas pixels.
  final Rect box;

  /// The Missing-glyph markers in canvas pixels.
  final List<Rect> markers;

  /// Whether the box has a Wrap width (a solid edge) or follows the text (a dashed one).
  final bool wrapped;
  final double scale;
  final Offset off;

  /// The radius of the Wrap-width handle, and the screen-space slop a finger gets around it.
  static const double handleRadius = 7, handleSlop = 22;

  /// The handle's center in screen space — shared with the drag hit-test.
  static Offset handleCenter(Rect box, double scale, Offset off) =>
      Offset(off.dx + box.right * scale, off.dy + (box.top + box.height / 2) * scale);

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;
    final r = Rect.fromLTRB(
        off.dx + box.left * scale, off.dy + box.top * scale, off.dx + box.right * scale, off.dy + box.bottom * scale);
    final halo = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final line = Paint()
      ..color = const Color(0xFF4DA3FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (wrapped) {
      canvas.drawRect(r, halo);
      canvas.drawRect(r, line);
    } else {
      _dashedRect(canvas, r, halo);
      _dashedRect(canvas, r, line);
    }
    final amberHalo = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final amber = Paint()
      ..color = const Color(0xFFFFB300)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in markers) {
      final mr = Rect.fromLTRB(
              off.dx + m.left * scale, off.dy + m.top * scale, off.dx + m.right * scale, off.dy + m.bottom * scale)
          .deflate(0.75);
      canvas.drawRect(mr, amberHalo);
      canvas.drawRect(mr, amber);
    }
    final c = handleCenter(box, scale, off);
    canvas.drawCircle(c, handleRadius, Paint()..color = Colors.black);
    canvas.drawCircle(c, handleRadius - 1.5, Paint()..color = const Color(0xFF4DA3FF));
    canvas.drawCircle(c, 2, Paint()..color = Colors.white);
  }

  static void _dashedRect(Canvas canvas, Rect r, Paint p) {
    const dash = 5.0, gap = 4.0;
    void seg(Offset a, Offset b) {
      final len = (b - a).distance;
      if (len <= 0) return;
      final dir = (b - a) / len;
      for (var t = 0.0; t < len; t += dash + gap) {
        final e = t + dash < len ? t + dash : len;
        canvas.drawLine(a + dir * t, a + dir * e, p);
      }
    }

    seg(r.topLeft, r.topRight);
    seg(r.topRight, r.bottomRight);
    seg(r.bottomRight, r.bottomLeft);
    seg(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(TextDraftPainter old) =>
      old.box != box || old.markers != markers || old.wrapped != wrapped || old.scale != scale || old.off != off;
}

/// The rectangle a drag is sweeping out before any Text Draft exists (a drag starts a Text
/// Draft with a Wrap width). Screen-space corners.
class TextBoxDragPainter extends CustomPainter {
  const TextBoxDragPainter(this.a, this.b);
  final Offset a, b;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromPoints(a, b);
    canvas.drawRect(
        r,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    canvas.drawRect(
        r,
        Paint()
          ..color = const Color(0xFF4DA3FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(TextBoxDragPainter old) => old.a != a || old.b != b;
}

/// A laid-out text drawn at [scale] logical pixels per font pixel, hard-edged: the font
/// picker's row sample. Sized by [sizeFor]; ink outside the layout box is clipped.
class TextSamplePainter extends CustomPainter {
  const TextSamplePainter(this.layout, {required this.scale, required this.color});
  final TextLayout layout;
  final double scale;
  final Color color;

  static Size sizeFor(TextLayout layout, double scale) =>
      Size(layout.boxWidth * scale, layout.boxHeight * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final m = layout.mask;
    if (m == null) return;
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (var y = 0; y < m.height; y++) {
      var x = 0;
      while (x < m.width) {
        if (!m.get(x, y)) {
          x++;
          continue;
        }
        final start = x;
        while (x < m.width && m.get(x, y)) {
          x++;
        }
        canvas.drawRect(
            Rect.fromLTWH((layout.maskX + start) * scale, (layout.maskY + y) * scale, (x - start) * scale, scale), paint);
      }
    }
  }

  @override
  bool shouldRepaint(TextSamplePainter old) => old.layout != layout || old.scale != scale || old.color != color;
}
