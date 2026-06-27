import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Interactive crop-rectangle picker over a source image. Returns the crop rect in
/// **source pixels** (SPEC §16.1).
class CropDialog extends StatefulWidget {
  final ui.Image image;
  const CropDialog({super.key, required this.image});
  @override
  State<CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<CropDialog> {
  late double scale;
  late double boxW, boxH;
  Offset? _start;
  Rect _disp = Rect.zero; // display-coordinate crop rect

  @override
  void initState() {
    super.initState();
    final w = widget.image.width.toDouble();
    final h = widget.image.height.toDouble();
    scale = (360 / w) < (360 / h) ? 360 / w : 360 / h;
    boxW = w * scale;
    boxH = h * scale;
    _disp = Rect.fromLTWH(0, 0, boxW, boxH); // default = whole image
  }

  Rect _toSource(Rect d) {
    final iw = widget.image.width.toDouble();
    final ih = widget.image.height.toDouble();
    return Rect.fromLTRB(
      (d.left / scale).clamp(0.0, iw),
      (d.top / scale).clamp(0.0, ih),
      (d.right / scale).clamp(0.0, iw),
      (d.bottom / scale).clamp(0.0, ih),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Drag to select crop area'),
      content: SizedBox(
        width: boxW,
        height: boxH,
        child: GestureDetector(
          onPanStart: (e) => setState(() => _start = e.localPosition),
          onPanUpdate: (e) {
            if (_start == null) return;
            final a = _start!;
            final b = e.localPosition;
            final left = (a.dx < b.dx ? a.dx : b.dx).clamp(0.0, boxW);
            final right = (a.dx < b.dx ? b.dx : a.dx).clamp(0.0, boxW);
            final top = (a.dy < b.dy ? a.dy : b.dy).clamp(0.0, boxH);
            final bottom = (a.dy < b.dy ? b.dy : a.dy).clamp(0.0, boxH);
            setState(() => _disp = Rect.fromLTRB(left, top, right, bottom));
          },
          child: CustomPaint(painter: _CropPainter(widget.image, _disp, boxW, boxH), size: Size(boxW, boxH)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: () {
              final s = _toSource(_disp);
              Navigator.pop(context, s.width < 1 || s.height < 1 ? null : s);
            },
            child: const Text('Use crop')),
      ],
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect crop;
  final double w, h;
  _CropPainter(this.image, this.crop, this.w, this.h);
  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(0, 0, w, h);
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.drawRect(dst, Paint()..color = const Color(0x99000000));
    if (crop.width > 0 && crop.height > 0) {
      final cs = Rect.fromLTRB(crop.left / w * image.width, crop.top / h * image.height, crop.right / w * image.width, crop.bottom / h * image.height);
      canvas.drawImageRect(image, cs, crop, Paint()..filterQuality = FilterQuality.medium);
      canvas.drawRect(crop, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.amber);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop;
}
