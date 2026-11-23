// The font picker (ADR 0039; docs/text-tool/DESIGN.md "The font picker"): every bundled Font,
// smallest native size first, each row drawn in its own glyphs and showing the artist's current
// text. Recently used Fonts ride on top, three chips narrow by script, and the Fonts that cannot
// draw the current text sink to the bottom, dimmed. The page owns no editor state: it takes
// plain values and pops the chosen Font's id, so a widget test drives it without the engine.
import 'package:flutter/material.dart';

import 'package:makapix_club/l10n/l10n.dart';

import 'pixel_font.dart';
import 'text_draft_painter.dart';
import 'text_layout.dart';

/// The sample a row shows: the first line of the artist's text, or the Font's own name.
String fontSampleText(String text, PixelFontEntry entry) {
  final line = text.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return entry.name;
  final runes = line.runes.toList();
  return runes.length <= 32 ? line : String.fromCharCodes(runes.take(32));
}

/// Logical pixels per font pixel in a row's sample.
const double kFontSampleScale = 2;

class FontPickerPage extends StatefulWidget {
  const FontPickerPage({
    super.key,
    required this.library,
    required this.currentId,
    required this.text,
    required this.recents,
    this.preferredLang,
  });

  final PixelFontLibrary library;
  final String? currentId;

  /// The Text Draft's words (may be empty).
  final String text;

  /// Recently used Font ids, most recent first.
  final List<String> recents;

  /// The language form to list first among the CJK entries of one size ('ja', 'zh-Hans', …).
  final String? preferredLang;

  @override
  State<FontPickerPage> createState() => _FontPickerPageState();
}

class _FontPickerPageState extends State<FontPickerPage> {
  String _filter = 'all'; // l10n-ignore: filter id
  late final Future<void> _loaded = widget.library.loadAll();

  bool _matches(PixelFontEntry e) => _filter == 'all' || e.scripts.contains(_filter); // l10n-ignore: filter id

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fontPickerTitle)),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(l10n.fontPickerLoadFailed)));
          }
          return _buildList(context);
        },
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final l10n = context.l10n;
    final lib = widget.library;
    // The preferred language form leads its size's CJK group; everything else keeps the
    // manifest order (smallest first).
    final entries = [...lib.entries];
    if (widget.preferredLang != null) {
      int rank(PixelFontEntry e) => e.lang == widget.preferredLang ? 0 : 1;
      final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])];
      indexed.sort((a, b) {
        final (ai, ae) = a;
        final (bi, be) = b;
        if (ae.isCjk && be.isCjk && ae.px == be.px && rank(ae) != rank(be)) return rank(ae) - rank(be);
        return ai - bi;
      });
      entries
        ..clear()
        ..addAll(indexed.map((p) => p.$2));
    }
    final can = <PixelFontEntry>[], cannot = <PixelFontEntry>[];
    for (final e in entries.where(_matches)) {
      final f = lib.peek(e.id);
      if (f == null) continue;
      (f.missingIn(widget.text) == 0 ? can : cannot).add(e);
    }
    final recents = [
      for (final id in widget.recents)
        if (lib.entry(id) != null && lib.peek(id) != null) lib.entry(id)!,
    ];
    final rows = <Widget>[
      if (recents.isNotEmpty) ...[
        _sectionLabel(l10n.fontPickerRecent),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final e in recents)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  key: ValueKey('font-recent-${e.id}'),
                  label: Text(e.name),
                  onPressed: () => Navigator.of(context).pop(e.id),
                ),
              ),
          ]),
        ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Wrap(spacing: 8, children: [
          for (final (id, label) in [
            ('all', l10n.optAll),
            ('latin', l10n.fontFilterLatin),
            ('cyrillic', l10n.fontFilterCyrillic),
            ('cjk', l10n.fontFilterCjk),
          ])
            ChoiceChip(
              key: ValueKey('font-filter-$id'),
              label: Text(label),
              selected: _filter == id,
              selectedColor: const Color(0xFF30A050),
              onSelected: (_) => setState(() => _filter = id),
            ),
        ]),
      ),
      for (final e in can) _row(context, e, dimmed: false),
      if (cannot.isNotEmpty) ...[
        _sectionLabel(l10n.fontPickerCannotDraw),
        for (final e in cannot) _row(context, e, dimmed: true),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Text(
          [for (final c in lib.credits.values) c].join('\n'),
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ),
    ];
    return ListView.builder(itemCount: rows.length, itemBuilder: (_, i) => rows[i]);
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Text(s, style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w600)),
      );

  Widget _row(BuildContext context, PixelFontEntry e, {required bool dimmed}) {
    final font = widget.library.peek(e.id)!;
    final layout = layoutText(fontSampleText(widget.text, e), font);
    // Every row is drawn at the same whole-number magnification, so the list shows the fonts'
    // true relative sizes: the one fact a pixel artist is choosing by.
    const scale = kFontSampleScale;
    final selected = e.id == widget.currentId;
    return Material(
      color: selected ? const Color(0xFF24382A) : Colors.transparent,
      child: InkWell(
        key: ValueKey('font-row-${e.id}'),
        onTap: () => Navigator.of(context).pop(e.id),
        child: Opacity(
          opacity: dimmed ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('${e.px} px', // l10n-ignore: unit
                    style: const TextStyle(fontSize: 11, color: Colors.white60, fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ),
                if (selected) const Icon(Icons.check, size: 16, color: Color(0xFF6DAA2C)),
              ]),
              const SizedBox(height: 6),
              ClipRect(
                child: SizedBox(
                  width: double.infinity,
                  height: layout.boxHeight * scale,
                  child: CustomPaint(painter: TextSamplePainter(layout, scale: scale, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
