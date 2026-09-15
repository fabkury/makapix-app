// One row of the Layers page (ADR 0033): the layer's own thumbnail on the checker, the
// bottom-first number, the name, the state badges (display only — every tap on a row selects),
// the opacity when below 100 %, the blend badge when non-Normal, an "empty" tag, the
// active-layer border in the strip's blue, and the amber selection (wash + border + check).
// Stateless and lean — a stack can hold 128 of these — so no Material ink, no Tooltip, a
// RawImage rather than Image. Every gesture lives on the list.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../blend_modes.dart';
import '../frames/frame_tile.dart' show kFramesAccent, kFramesSelect;
import '../widgets/painters.dart';
import 'layer_model.dart';

/// The row height in unscaled logical pixels for the two densities.
const double kLayerRowHeightCompact = 44;
const double kLayerRowHeightRoomy = 60;

const Color _kRowBg = Color(0xFF101214);
const Color _kThumbBg = Color(0xFF3A3D42);
const Color _kSelectedWash = Color(0x48FFC107);

class LayerRowTile extends StatelessWidget {
  const LayerRowTile({
    super.key,
    required this.layer,
    required this.image,
    required this.aspect,
    required this.number,
    required this.active,
    required this.selected,
    required this.height,
    required this.scale,
  });

  final LayerRow layer;
  final ui.Image? image;

  /// Artwork width / height (the placeholder's shape while the thumb is pending).
  final double aspect;

  /// The 1-based, bottom-first number.
  final int number;
  final bool active;
  final bool selected;
  final double height;
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
    final border = active ? kFramesAccent : (selected ? kFramesSelect : Colors.black26);
    final dim = !layer.visible;
    final nameStyle = TextStyle(
      fontSize: 13 * scale,
      color: dim ? Colors.white38 : Colors.white,
      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
    );
    final tagStyle = TextStyle(fontSize: 10 * scale, color: Colors.white54);
    final tags = <Widget>[
      if (!layer.visible) Icon(Icons.visibility_off, size: 14 * scale, color: Colors.white54),
      if (layer.locked) Icon(Icons.lock, size: 14 * scale, color: Colors.white54),
      if (layer.opacity < 255) Text('${(layer.opacity * 100 / 255).round()} %', style: tagStyle),
      if (layer.blend != 'Normal') Text(blendBadge(layer.blend), style: tagStyle),
      if (layer.isEmpty) Text('empty', style: tagStyle.copyWith(fontStyle: FontStyle.italic)),
    ];
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _kRowBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border, width: active || selected ? 2 : 1),
        ),
        child: Stack(fit: StackFit.expand, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(children: [
              SizedBox(
                width: 28 * scale,
                child: Text('$number',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(fontSize: 10 * scale, color: active ? Colors.white : Colors.white54, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              AspectRatio(aspectRatio: imgAspect, child: Opacity(opacity: dim ? 0.4 : 1, child: thumb)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(layer.name.isEmpty ? '(unnamed)' : layer.name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: nameStyle),
              ),
              for (final t in tags) ...[const SizedBox(width: 8), t],
            ]),
          ),
          if (selected) ...[
            const ColoredBox(color: _kSelectedWash),
            Positioned(
              left: 2,
              top: 2,
              child: Icon(Icons.check_circle, size: 14 * scale, color: kFramesSelect, shadows: const [Shadow(color: Colors.black87, blurRadius: 3)]),
            ),
          ],
        ]),
      ),
    );
  }
}
