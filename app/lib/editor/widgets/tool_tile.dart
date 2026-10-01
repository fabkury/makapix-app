// The row-3 tool tile: icon over a one-line label, 54 × 42 logical px (times the chrome scale).
// A widget of its own so the label's fit can be tested in every language without the engine
// (test/l10n/tool_label_fit_test.dart) — the tile is the tightest text box in the app.
import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

import '../tools.dart';

class ToolTile extends StatelessWidget {
  const ToolTile(
    this.tool, {
    super.key,
    required this.selected,
    this.hover = false,
    this.active = false,
    this.enabled = true,
    this.scale = 1,
  });

  final ToolDef tool;

  /// The active draw tool (blue).
  final bool selected;
  final bool hover;

  /// An on toggle like Onion / Play (amber).
  final bool active;

  /// False dims the tile (Undo / Redo with nothing to undo / redo).
  final bool enabled;
  final double scale;

  /// The tile's width at scale 1. The label may use all of it — the tile has no padding.
  static const double width = 54;
  static const double labelFontSize = 8.5;

  /// The widest a label may measure in Roboto at scale 1. The 6 px under [width] is the
  /// reserve for platform fonts that set wider than Roboto (San Francisco on iOS, Segoe UI on
  /// Windows, OEM fonts on Android). Enforced per language by tool_label_fit_test.dart.
  static const double labelBudget = 48;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final fg = selected ? Colors.white : (active ? Colors.amber : Colors.white70);
    final tile = Container(
      width: width * s,
      height: 42 * s,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF4080C0) : const Color(0xFF26292E),
        borderRadius: BorderRadius.circular(6),
        border: hover
            ? Border.all(color: Colors.amber, width: 2)
            : (active ? Border.all(color: Colors.amber, width: 1.5) : null),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          tool.iconWidget(size: 18 * s, color: fg),
          const SizedBox(height: 1),
          Text(tool.shortLabel(context.l10n),
              style: TextStyle(fontSize: labelFontSize * s, color: active ? Colors.amber : null),
              maxLines: 1,
              overflow: TextOverflow.clip),
        ],
      ),
    );
    return enabled ? tile : Opacity(opacity: 0.4, child: tile);
  }
}
