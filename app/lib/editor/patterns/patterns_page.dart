// The Patterns page (ADR 0025): a full-screen picker for the paint gate. Off first, a strip of
// recently used tiles, then the built-in catalog by family. Tiles render in two fixed preview
// colors (ON and OFF, black on white by default, editable on the page and persisted by the
// editor), never in the primary color: a primary close to the page background would make the
// tiles unreadable, and the preview is about the tile's shape, not the paint. The tool itself
// still paints ON cells in the primary color. The Gradient's variant ("Dither") offers the dither
// families of ADR 0028 (Bayer, blue noise, halftone, lines, noise) plus Off, each as a full-width
// OFF→ON ramp strip that walks every density step (2026-09-16; [DitherStripTile]) with the name
// and hint under it. The page owns no editor state beyond the two preview colors it edits: it takes
// plain values and pops a [PatternPick] (or a [DitherKind] for the Gradient), so widget tests
// drive it without the engine.
import 'package:flutter/material.dart';

import 'package:makapix_club/l10n/l10n.dart';

import '../widgets/painters.dart' show AlphaSwatch;
import 'gradient_dither.dart';
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
        dither = DitherKind.off;

  /// The Gradient's variant: every dither family and Off. Pops a [DitherKind].
  const PatternsPage.gradient({
    super.key,
    required this.dither,
    this.onColor = kPatternOnDefault,
    this.offColor = kPatternOffDefault,
    this.pickColor,
    this.onDisplayColorsChanged,
  })  : gradient = true,
        toolName = '',
        current = null,
        on = false,
        recents = const [];

  /// The tool's name as the artist reads it (already in the current language).
  final String toolName;
  final PatternTile? current;
  final bool on;
  final List<PatternTile> recents;
  final bool gradient;
  final DitherKind dither;
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
      appBar: AppBar(title: Text(widget.gradient ? context.l10n.optDither : context.l10n.patternsTitle)),
      body: widget.gradient ? _gradientBody(context) : _patternBody(context),
    );
  }

  // ---- the four gated tools ----

  Widget _patternBody(BuildContext context) {
    final selected = widget.on ? widget.current : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _hint(context.l10n.patternsHint(widget.toolName)),
        _colorsRow(),
        _offTile(context,
            selected: !widget.on,
            subtitle: context.l10n.patternsOffSub,
            onTap: () => Navigator.pop(context, const PatternOff())),
        if (widget.recents.isNotEmpty) ...[
          _header(context.l10n.patternsRecent),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final t in widget.recents)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                    child: _tileButton(context, t, selected: t == selected, name: patternName(t) ?? context.l10n.patternCustom),
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
      message: '$name, ${t.w}×${t.h}', // l10n-ignore: a name and a size
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
        _hint(context.l10n.ditherPageHint),
        _colorsRow(),
        DitherStripTile(
            kind: DitherKind.off,
            onColor: _on,
            offColor: _off,
            selected: widget.dither.isOff,
            onTap: () => Navigator.pop(context, DitherKind.off)),
        for (final family in DitherKind.families) ...[
          _header(family.label),
          for (final k in DitherKind.inFamily(family))
            DitherStripTile(
                kind: k,
                onColor: _on,
                offColor: _off,
                selected: widget.dither == k,
                onTap: () => Navigator.pop(context, k)),
        ],
      ],
    );
  }

  // ---- shared ----

  /// The two preview colors (ON, OFF) with a swap between them. Tapping a swatch opens the color
  /// dialog when the host provided one.
  Widget _colorsRow() {
    Widget swatch(String label, Color c, bool on) => Semantics(
          button: true,
          label: context.l10n.patternsSwatchLabel(label),
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
        // The label gives way (two lines) before the swatches run off a narrow phone.
        Flexible(
          child: Text(context.l10n.patternsPreviewColors, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ),
        const SizedBox(width: 10),
        swatch(context.l10n.patternOnLabel, _on, true),
        IconButton(
          tooltip: context.l10n.patternsSwap,
          icon: const Icon(Icons.swap_horiz, size: 20),
          onPressed: () => _setColors(_off, _on),
        ),
        swatch(context.l10n.patternOffLabel, _off, false),
      ]),
    );
  }

  Widget _hint(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(s, style: const TextStyle(fontSize: 13, color: Colors.white70)),
      );

  Widget _offTile(BuildContext context, {required bool selected, required String subtitle, required VoidCallback onTap}) {
    // The mask variant's Off card; the Gradient variant's Off is a [DitherStripTile].
    return Card(
      color: selected ? const Color(0xFF2A4A6A) : null,
      child: ListTile(
        leading: const Icon(Icons.block),
        title: Text(context.l10n.optOff),
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

/// One Dither page row (2026-09-16): a full-width ramp strip through [kind] — OFF color to ON
/// color, every density step left to right, [scale] logical px per cell, [height] tall — with
/// "name · hint" under it. The strip carries the selection accent; a check marks the row.
class DitherStripTile extends StatelessWidget {
  const DitherStripTile({
    super.key,
    required this.kind,
    required this.onColor,
    required this.offColor,
    required this.selected,
    required this.onTap,
    this.scale = 3,
    this.height = 48,
  });
  final DitherKind kind;
  final Color onColor, offColor;
  final bool selected;
  final VoidCallback onTap;
  final double scale, height;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? Colors.white10 : null,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Container(
            height: height,
            decoration: BoxDecoration(
              border: Border.all(color: selected ? PatternTileBox.accent : Colors.white24, width: selected ? 2 : 1),
              borderRadius: BorderRadius.circular(4),
            ),
            clipBehavior: Clip.antiAlias,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: DitherRampPainter(kind: kind, onColor: onColor, offColor: offColor, scale: scale),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // The note may take two lines: on one, the longer translations ended in an ellipsis.
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kind.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('· ${kind.hint}',
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  overflow: TextOverflow.ellipsis),
            ),
            if (selected) const Icon(Icons.check, size: 18, color: PatternTileBox.accent),
          ]),
        ]),
      ),
    );
  }
}
