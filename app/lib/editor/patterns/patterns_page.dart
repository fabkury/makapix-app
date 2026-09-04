// The Patterns page (ADR 0025): a full-screen picker for the paint gate — Off first, a strip of
// recently used tiles, then the built-in catalog by family. Tiles render in the current primary
// color over the page background so what you see is what the tool will paint. The Gradient's
// variant ("Dither") offers only the three Bayer families plus Off. The page owns no editor state:
// it takes plain values and pops a [PatternPick] (or an `int` dither size for the Gradient), so
// widget tests drive it without the engine.
import 'package:flutter/material.dart';

import 'pattern_tile.dart';
import 'patterns_catalog.dart';

/// What the page pops for the four gated tools: [PatternOff] or a [PatternChosen] tile.
sealed class PatternPick {
  const PatternPick();
}

class PatternOff extends PatternPick {
  const PatternOff();
}

class PatternChosen extends PatternPick {
  const PatternChosen(this.tile);
  final PatternTile tile;
}

/// Paints [tile] repeated over the whole box at [scale] logical px per cell, ON cells in [color],
/// anchored at the box's top-left. OFF cells are left to whatever is behind.
class PatternTilePainter extends CustomPainter {
  const PatternTilePainter({required this.tile, required this.color, required this.scale});
  final PatternTile tile;
  final Color color;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cols = (size.width / scale).ceil();
    final rows = (size.height / scale).ceil();
    canvas.clipRect(Offset.zero & size);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (tile.on(x, y)) canvas.drawRect(Rect.fromLTWH(x * scale, y * scale, scale, scale), paint);
      }
    }
  }

  @override
  bool shouldRepaint(PatternTilePainter old) => old.tile != tile || old.color != color || old.scale != scale;
}

/// A tile preview box: the pattern tiled at [scale] px/cell inside a bordered square.
class PatternTileBox extends StatelessWidget {
  const PatternTileBox({
    super.key,
    required this.tile,
    required this.color,
    this.size = 48,
    this.scale = 4,
    this.selected = false,
    this.dimmed = false,
  });
  final PatternTile tile;
  final Color color;
  final double size, scale;
  final bool selected, dimmed;

  static const accent = Color(0xFF4080C0);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1E2226),
        border: Border.all(color: selected ? accent : Colors.white24, width: selected ? 2 : 1),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: dimmed ? 0.35 : 1,
        child: CustomPaint(painter: PatternTilePainter(tile: tile, color: color, scale: scale)),
      ),
    );
  }
}

class PatternsPage extends StatelessWidget {
  /// The paint-gate picker for Pencil / Brush / Eraser / Bucket. [current] is the global pattern
  /// (null if none was ever picked), [on] whether the current tool has it On, [recents] the
  /// most-recent-first strip. Pops a [PatternPick].
  const PatternsPage({
    super.key,
    required this.primary,
    required this.toolName,
    this.current,
    this.on = false,
    this.recents = const [],
  })  : gradient = false,
        dither = 0;

  /// The Gradient's variant: the three Bayer families and Off. Pops an `int` (0, 2, 4, 8).
  const PatternsPage.gradient({super.key, required this.primary, required this.dither})
      : gradient = true,
        toolName = 'Gradient',
        current = null,
        on = false,
        recents = const [];

  final Color primary;
  final String toolName;
  final PatternTile? current;
  final bool on;
  final List<PatternTile> recents;
  final bool gradient;
  final int dither;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(gradient ? 'Dither' : 'Patterns')),
      body: gradient ? _gradientBody(context) : _patternBody(context),
    );
  }

  // ---- the four gated tools ----

  Widget _patternBody(BuildContext context) {
    final selected = on ? current : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _offTile(context, selected: !on, subtitle: '$toolName paints every pixel', onTap: () => Navigator.pop(context, const PatternOff())),
        if (recents.isNotEmpty) ...[
          _header('Recent'),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final t in recents)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                    child: _tileButton(context, t, selected: t == selected, name: patternName(t) ?? 'Custom'),
                  ),
              ],
            ),
          ),
        ],
        for (final f in patternCatalog) ...[
          _header(f.name),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in f.entries) _tileButton(context, e.tile, selected: e.tile == selected, name: e.name),
            ],
          ),
        ],
      ],
    );
  }

  Widget _tileButton(BuildContext context, PatternTile t, {required bool selected, required String name}) {
    return Tooltip(
      message: '$name · ${t.w}×${t.h}',
      triggerMode: TooltipTriggerMode.longPress,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => Navigator.pop(context, PatternChosen(t)),
        child: PatternTileBox(tile: t, color: primary, selected: selected),
      ),
    );
  }

  // ---- the Gradient's dither ----

  Widget _gradientBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _offTile(context, selected: dither == 0, subtitle: 'A smooth ramp between the colors', onTap: () => Navigator.pop(context, 0)),
        _header('Bayer ordered dither'),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Each pixel takes one of the two nearest gradient colors — no blended shades. Larger matrices give more density steps.',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ),
        for (final n in kGradientDitherSizes)
          ListTile(
            leading: PatternTileBox(tile: bayerTile(n, n * n ~/ 2), color: primary, size: 44, scale: n == 8 ? 3 : 4),
            title: Text('Bayer $n×$n'),
            subtitle: Text('${n * n} density steps'),
            selected: dither == n,
            selectedTileColor: Colors.white10,
            onTap: () => Navigator.pop(context, n),
          ),
      ],
    );
  }

  // ---- shared ----

  Widget _offTile(BuildContext context, {required bool selected, required String subtitle, required VoidCallback onTap}) {
    return Card(
      color: selected ? const Color(0xFF2A4A6A) : null,
      child: ListTile(
        leading: const Icon(Icons.block),
        title: const Text('Off'),
        subtitle: Text(subtitle),
        trailing: selected ? const Icon(Icons.check, color: PatternTileBox.accent) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _header(String s) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
      );
}
