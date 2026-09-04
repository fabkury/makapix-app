// The Patterns page (ADR 0025): a full-screen picker for the paint gate. Off first, a strip of
// recently used tiles, then the built-in catalog by family. Tiles render in two fixed preview
// colors (ON and OFF, black on white by default, editable on the page and persisted by the
// editor), never in the primary color: a primary close to the page background would make the
// tiles unreadable, and the preview is about the tile's shape, not the paint. The tool itself
// still paints ON cells in the primary color. The Gradient's variant ("Dither") offers only the
// three Bayer families plus Off. The page owns no editor state beyond the two preview colors it
// edits: it takes plain values and pops a [PatternPick] (or an `int` dither size for the
// Gradient), so widget tests drive it without the engine.
import 'package:flutter/material.dart';

import '../widgets/painters.dart' show AlphaSwatch;
import 'pattern_tile.dart';
import 'patterns_catalog.dart';

/// The default preview colors: ON black, OFF white (user decision 2026-09-04).
const Color kPatternOnDefault = Color(0xFF000000);
const Color kPatternOffDefault = Color(0xFFFFFFFF);

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

/// Paints [tile] repeated over the whole box at [scale] logical px per cell, anchored at the
/// box's top-left: OFF cells in [offColor] (the whole box first), ON cells in [onColor] over it.
class PatternTilePainter extends CustomPainter {
  const PatternTilePainter({required this.tile, required this.onColor, required this.offColor, required this.scale});
  final PatternTile tile;
  final Color onColor, offColor;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = offColor);
    final paint = Paint()..color = onColor;
    final cols = (size.width / scale).ceil();
    final rows = (size.height / scale).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (tile.on(x, y)) canvas.drawRect(Rect.fromLTWH(x * scale, y * scale, scale, scale), paint);
      }
    }
  }

  @override
  bool shouldRepaint(PatternTilePainter old) =>
      old.tile != tile || old.onColor != onColor || old.offColor != offColor || old.scale != scale;
}

/// A tile preview box: the pattern tiled at [scale] px/cell inside a bordered square.
class PatternTileBox extends StatelessWidget {
  const PatternTileBox({
    super.key,
    required this.tile,
    required this.onColor,
    required this.offColor,
    this.size = 48,
    this.scale = 4,
    this.selected = false,
  });
  final PatternTile tile;
  final Color onColor, offColor;
  final double size, scale;
  final bool selected;

  static const accent = Color(0xFF4080C0);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: selected ? accent : Colors.white24, width: selected ? 2 : 1),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: PatternTilePainter(tile: tile, onColor: onColor, offColor: offColor, scale: scale)),
    );
  }
}

/// Opens a color picker for [initial] and resolves to the chosen color, or null when dismissed.
typedef PatternColorPicker = Future<Color?> Function(Color initial);

class PatternsPage extends StatefulWidget {
  /// The paint-gate picker for Pencil / Brush / Eraser / Bucket. [current] is the global pattern
  /// (null if none was ever picked), [on] whether the current tool has it On, [recents] the
  /// most-recent-first strip. Pops a [PatternPick]. [pickColor] opens the editor's color dialog
  /// for the two preview colors; [onDisplayColorsChanged] reports every change so the editor
  /// can persist it.
  const PatternsPage({
    super.key,
    required this.toolName,
    this.current,
    this.on = false,
    this.recents = const [],
    this.onColor = kPatternOnDefault,
    this.offColor = kPatternOffDefault,
    this.pickColor,
    this.onDisplayColorsChanged,
  })  : gradient = false,
        dither = 0;

  /// The Gradient's variant: the three Bayer families and Off. Pops an `int` (0, 2, 4, 8).
  const PatternsPage.gradient({
    super.key,
    required this.dither,
    this.onColor = kPatternOnDefault,
    this.offColor = kPatternOffDefault,
    this.pickColor,
    this.onDisplayColorsChanged,
  })  : gradient = true,
        toolName = 'Gradient',
        current = null,
        on = false,
        recents = const [];

  final String toolName;
  final PatternTile? current;
  final bool on;
  final List<PatternTile> recents;
  final bool gradient;
  final int dither;
  final Color onColor, offColor;
  final PatternColorPicker? pickColor;
  final void Function(Color onColor, Color offColor)? onDisplayColorsChanged;

  @override
  State<PatternsPage> createState() => _PatternsPageState();
}

class _PatternsPageState extends State<PatternsPage> {
  late Color _on = widget.onColor;
  late Color _off = widget.offColor;

  void _setColors(Color on, Color off) {
    setState(() {
      _on = on;
      _off = off;
    });
    widget.onDisplayColorsChanged?.call(on, off);
  }

  Future<void> _pick({required bool on}) async {
    final picker = widget.pickColor;
    if (picker == null) return;
    final c = await picker(on ? _on : _off);
    if (c == null || !mounted) return;
    _setColors(on ? c : _on, on ? _off : c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.gradient ? 'Dither' : 'Patterns')),
      body: widget.gradient ? _gradientBody(context) : _patternBody(context),
    );
  }

  // ---- the four gated tools ----

  Widget _patternBody(BuildContext context) {
    final selected = widget.on ? widget.current : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _hint('Tap a pattern to use it with the ${widget.toolName}. Cells shown in the ON color get painted with the '
            'primary color; OFF cells leave the pixel as it is.'),
        _colorsRow(),
        _offTile(context,
            selected: !widget.on,
            subtitle: '${widget.toolName} paints every pixel',
            onTap: () => Navigator.pop(context, const PatternOff())),
        if (widget.recents.isNotEmpty) ...[
          _header('Recent'),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final t in widget.recents)
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
      message: '$name, ${t.w}×${t.h}',
      triggerMode: TooltipTriggerMode.longPress,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => Navigator.pop(context, PatternChosen(t)),
        child: PatternTileBox(tile: t, onColor: _on, offColor: _off, selected: selected),
      ),
    );
  }

  // ---- the Gradient's dither ----

  Widget _gradientBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _hint('Tap a matrix size to dither the gradient. Each pixel takes one of the two nearest gradient colors, '
            'never a blended shade; larger matrices give more density steps.'),
        _colorsRow(),
        _offTile(context,
            selected: widget.dither == 0,
            subtitle: 'A smooth ramp between the colors',
            onTap: () => Navigator.pop(context, 0)),
        _header('Bayer ordered dither'),
        for (final n in kGradientDitherSizes)
          ListTile(
            leading: PatternTileBox(
                tile: bayerTile(n, n * n ~/ 2), onColor: _on, offColor: _off, size: 44, scale: n == 8 ? 3 : 4),
            title: Text('Bayer $n×$n'),
            subtitle: Text('${n * n} density steps'),
            selected: widget.dither == n,
            selectedTileColor: Colors.white10,
            onTap: () => Navigator.pop(context, n),
          ),
      ],
    );
  }

  // ---- shared ----

  /// The two preview colors (ON, OFF) with a swap between them. Tapping a swatch opens the color
  /// dialog when the host provided one.
  Widget _colorsRow() {
    Widget swatch(String label, Color c, bool on) => Semantics(
          button: true,
          label: '$label preview color',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: widget.pickColor == null ? null : () => _pick(on: on),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AlphaSwatch(color: c, width: 28, height: 28, borderRadius: 4, borderColor: Colors.white54),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(children: [
        const Text('Preview colors', style: TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(width: 10),
        swatch('ON', _on, true),
        IconButton(
          tooltip: 'Swap the preview colors',
          icon: const Icon(Icons.swap_horiz, size: 20),
          onPressed: () => _setColors(_off, _on),
        ),
        swatch('OFF', _off, false),
      ]),
    );
  }

  Widget _hint(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(s, style: const TextStyle(fontSize: 13, color: Colors.white70)),
      );

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
