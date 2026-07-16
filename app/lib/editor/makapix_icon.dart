// Custom Makapix tool icons: const vector data (generated) + a small painter.
// Designs live in tools/icons/gen_icons.py; the approved set is compiled to
// makapix_icons.g.dart by tools/icons/build_final.py. No packages, no assets:
// each icon is a list of fill/stroke path segments on a 24x24 design grid,
// scaled to whatever size the widget is given (same contract as Icon).
import 'package:flutter/widgets.dart';

part 'makapix_icons.g.dart';

/// One custom icon: an ordered list of drawing segments on a 24x24 grid.
class MpxIcon {
  final List<MpxSeg> segs;
  const MpxIcon._(this.segs);
}

/// One drawing segment: a filled or 2px-round-stroked path, encoded as a flat
/// op stream: 0 moveTo(x,y) - 1 lineTo(x,y) - 2 cubicTo(x1,y1,x2,y2,x,y) - 3 close.
class MpxSeg {
  final bool fill;
  final List<double> ops;
  const MpxSeg(this.fill, this.ops);
}

/// Renders an [MpxIcon] at [size]. Like [Icon], the colour defaults to the
/// ambient [IconTheme] so it works inside buttons, list tiles, etc.
class MakapixIcon extends StatelessWidget {
  final MpxIcon icon;
  final double size;
  final Color? color;
  const MakapixIcon(this.icon, {super.key, required this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    return CustomPaint(size: Size.square(size), painter: _MpxPainter(icon, c));
  }
}

class _MpxPainter extends CustomPainter {
  final MpxIcon icon;
  final Color color;
  _MpxPainter(this.icon, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / 24.0);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    for (final seg in icon.segs) {
      final path = Path();
      final o = seg.ops;
      var i = 0;
      while (i < o.length) {
        switch (o[i].toInt()) {
          case 0:
            path.moveTo(o[i + 1], o[i + 2]);
            i += 3;
          case 1:
            path.lineTo(o[i + 1], o[i + 2]);
            i += 3;
          case 2:
            path.cubicTo(o[i + 1], o[i + 2], o[i + 3], o[i + 4], o[i + 5], o[i + 6]);
            i += 7;
          default:
            path.close();
            i += 1;
        }
      }
      canvas.drawPath(path, seg.fill ? fill : stroke);
    }
  }

  @override
  bool shouldRepaint(_MpxPainter oldDelegate) =>
      oldDelegate.icon != icon || oldDelegate.color != color;
}
