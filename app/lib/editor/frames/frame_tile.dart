// One tile of the contact sheet (ADR 0031): the thumbnail on the checker, the 1-based number,
// the duration badge, the active-frame border in the strip's blue, and the amber selection
// (wash + border + check). Stateless and lean — a roll can hold 1024 of these — so no Material
// ink, no Tooltip, a RawImage rather than Image. Every gesture lives on the grid.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../widgets/painters.dart';

/// The label strip under the thumbnail, in unscaled logical pixels.
const double kFrameTileLabelBand = 18;

/// The active-frame marker: the film roll's blue, so "active" reads the same on both.
const Color kFramesAccent = Color(0xFF4080C0);

/// The selection color (wash, border, check, rubber-band): amber, never the active blue, so a
/// selected tile and the active tile stay distinguishable at a glance.
const Color kFramesSelect = Color(0xFFFFC107);
const Color _kTileBg = Color(0xFF101214);
const Color _kThumbBg = Color(0xFF3A3D42);
const Color _kSelectedWash = Color(0x48FFC107);

class FrameTile extends StatelessWidget {
  const FrameTile({
    super.key,
    required this.image,
    required this.aspect,
    required this.number,
    required this.durationMs,
    required this.active,
    required this.selected,
    required this.scale,
  });

  final ui.Image? image;

  /// Artwork width / height (the placeholder's shape while the thumb is pending).
  final double aspect;
  final int number;
  final double durationMs;
  final bool active;
  final bool selected;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final img = image;
    final imgAspect = img != null && img.height > 0 ? img.width / img.height : aspect;
    final thumb = img != null
        ? CustomPaint(
            painter: const CheckerPainter(),
            child: RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.none),
          )
        : const ColoredBox(color: _kThumbBg);
    // Active wins the border (it is the drawing target); a selected active tile still shows
    // the amber wash and check.
    final border = active ? kFramesAccent : (selected ? kFramesSelect : Colors.black26);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kTileBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border, width: active || selected ? 2 : 1),
      ),
      child: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            Padding(
              padding: const EdgeInsets.all(2),
              child: Center(child: AspectRatio(aspectRatio: imgAspect, child: thumb)),
            ),
            if (selected) ...[
              const ColoredBox(color: _kSelectedWash),
              Positioned(
                left: 4,
                top: 4,
                child: Icon(
                  Icons.check_circle,
                  size: 18 * scale,
                  color: kFramesSelect,
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 3)],
                ),
              ),
            ],
          ]),
        ),
        SizedBox(
          height: kFrameTileLabelBand * scale,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              Text('$number',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 10 * scale, color: active ? Colors.white : Colors.white70, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Expanded(
                child: Text('${durationMs.toStringAsFixed(durationMs == durationMs.roundToDouble() ? 0 : 1)} ms',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(fontSize: 9 * scale, color: Colors.white54)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
