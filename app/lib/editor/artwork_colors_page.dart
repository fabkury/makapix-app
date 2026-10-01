// The "Artwork colors" page: the inspect-before-commit flow behind the palette page's "From
// artwork colors" (user decision 2026-09-01). Extraction runs while a spinner shows (the host
// may run it off the UI thread); the result is either a message (over the 256-color cap, an
// empty artwork, a failed read) or the extracted palette as a scrollable swatch grid in the
// order the created palette will have. Tap / long-press / right-click a swatch for its exact
// value (copy), to add it to the active palette, or to make it the primary color. Accept creates
// the "Artwork colors" palette; Reject (only live when there is a palette to reject) or the back
// gesture discards. Talks to the engine only through [PaletteHost], so widget tests drive it
// with a fake.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:makapix_club/l10n/l10n.dart';

import 'package:makapix_club/ui/layout.dart';

import 'palette_io.dart';
import 'palette_page.dart' show PaletteHost, kMaxPaletteColors;
import 'widgets/painters.dart' show AlphaSwatch;

enum ArtworkColorsStatus { extracting, ready, overLimit, empty, failed }

/// Interprets the host's used-colors JSON: `{"colors":[...]}` → ready (or empty when the list
/// is), `{"over_limit":true}` → overLimit, anything else (an unloadable snapshot returns `{}`)
/// → failed. Pure, unit-tested.
({ArtworkColorsStatus status, List<Color> colors}) parseArtworkColors(String jsonText) {
  try {
    final r = json.decode(jsonText) as Map<String, dynamic>;
    if (r['over_limit'] == true) return (status: ArtworkColorsStatus.overLimit, colors: const []);
    final list = r['colors'];
    if (list is! List) return (status: ArtworkColorsStatus.failed, colors: const []);
    final colors = [for (final h in list) parseHexColor(h.toString())];
    return (status: colors.isEmpty ? ArtworkColorsStatus.empty : ArtworkColorsStatus.ready, colors: colors);
  } catch (_) {
    return (status: ArtworkColorsStatus.failed, colors: const []);
  }
}

/// What "Copy" puts on the clipboard: `#RRGGBB` for an opaque color, `#RRGGBBAA` otherwise
/// (user decision 2026-09-01 — web-style for the common case, exact when alpha matters).
String artworkColorClipboardText(Color c) {
  final full = hexRgba(c);
  return full.endsWith('FF') ? full.substring(0, 7) : full;
}

/// "R 58 · G 123 · B 213 · A 255" — the exact 8-bit channels.
String artworkColorChannels(Color c) {
  final v = c.toARGB32();
  final l = appL10n;
  return '${l.colorLetterR} ${(v >> 16) & 0xFF} · ${l.colorLetterG} ${(v >> 8) & 0xFF} · '
      '${l.colorLetterB} ${v & 0xFF} · ${l.colorLetterA} ${(v >> 24) & 0xFF}';
}

class ArtworkColorsPage extends StatefulWidget {
  const ArtworkColorsPage({super.key, required this.host});
  final PaletteHost host;

  @override
  State<ArtworkColorsPage> createState() => _ArtworkColorsPageState();
}

class _ArtworkColorsPageState extends State<ArtworkColorsPage> {
  static const _accent = Color(0xFF4080C0);

  ArtworkColorsStatus _status = ArtworkColorsStatus.extracting;
  List<Color> _colors = const [];

  @override
  void initState() {
    super.initState();
    widget.host.extractArtworkColors().then((jsonText) {
      if (!mounted) return;
      final r = parseArtworkColors(jsonText);
      setState(() {
        _status = r.status;
        _colors = r.colors;
      });
    }, onError: (_) {
      if (mounted) setState(() => _status = ArtworkColorsStatus.failed);
    });
  }

  bool get _ready => _status == ArtworkColorsStatus.ready;

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  // Accept: create the palette. The colors already arrive in SortPalette order (the sorted
  // query), so no SortPalette follow-up — the grid the user inspected IS the palette. Pops with
  // the count so the palette page can toast it.
  void _accept() {
    // The palette is named in the current language: the name is the artist's from here on.
    final err = widget.host.run(buildImportScript(context.l10n.artworkColorsTitle, _colors));
    if (err != null) debugPrint('palette DSL error: $err');
    Navigator.of(context).pop(_colors.length);
  }

  // The color sheet: exact value, copy, add to the active palette, set as primary.
  void _colorSheet(Color c) {
    final hex = hexRgba(c);
    final clip = artworkColorClipboardText(c);
    final pals = widget.host.readPalettes();
    final activeName = pals.active < pals.palettes.length ? pals.palettes[pals.active].shownName : null;
    final l10n = context.l10n;
    showAppSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: AlphaSwatch(color: c, width: 40, height: 40, diagonal: true, borderRadius: 6),
            title: Text(hex, style: const TextStyle(fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
            subtitle: Text(artworkColorChannels(c)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(l10n.acCopy(clip)),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: clip));
              _toast(l10n.acCopied(clip));
            },
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(activeName == null ? l10n.acAddToActive : l10n.acAddTo(activeName)),
            enabled: activeName != null,
            onTap: () {
              Navigator.pop(ctx);
              _addToActivePalette(c);
            },
          ),
          ListTile(
            leading: const Icon(Icons.colorize),
            title: Text(l10n.acSetPrimary),
            onTap: () {
              Navigator.pop(ctx);
              widget.host.setPrimary(c);
              _toast(l10n.acPrimarySet(clip));
            },
          ),
        ]),
      ),
    );
  }

  // Duplicates are skipped with a note and a full palette refuses (user decision 2026-09-01);
  // otherwise one journaled AddPaletteColor. The page stays open either way.
  void _addToActivePalette(Color c) {
    final pals = widget.host.readPalettes();
    if (pals.active >= pals.palettes.length) return;
    final p = pals.palettes[pals.active];
    if (p.colors.contains(c)) {
      _toast(context.l10n.acAlreadyIn(p.shownName));
      return;
    }
    if (p.colors.length >= kMaxPaletteColors) {
      _toast(context.l10n.acFull(p.shownName, kMaxPaletteColors));
      return;
    }
    final err = widget.host.run('AddPaletteColor(${hexRgba(c)})');
    if (err != null) debugPrint('palette DSL error: $err');
    _toast(context.l10n.acAdded(p.shownName));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.artworkColorsTitle)),
      body: Column(children: [
        Expanded(child: _body()),
        _buttons(),
      ]),
    );
  }

  Widget _body() => switch (_status) {
        ArtworkColorsStatus.extracting => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(context.l10n.acExtracting),
            ]),
          ),
        ArtworkColorsStatus.overLimit => _message(Icons.palette_outlined,
            context.l10n.acOverTitle(kMaxPaletteColors), context.l10n.acOverBody(kMaxPaletteColors)),
        ArtworkColorsStatus.empty =>
          _message(Icons.brush_outlined, context.l10n.acEmptyTitle, context.l10n.acEmptyBody),
        ArtworkColorsStatus.failed =>
          _message(Icons.error_outline, context.l10n.acFailedTitle, context.l10n.acFailedBody),
        ArtworkColorsStatus.ready => _grid(),
      };

  Widget _message(IconData icon, String title, String detail) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: Colors.white54),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        ),
      );

  Widget _grid() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            context.l10n.acSummary(_colors.length),
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
        // [G-19] Extraction reads the committed document; a pending Draft is a display-only
        // preview and is not part of what was read. Said here, where the result is.
        if (widget.host.hasPendingDraft)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(context.l10n.acPendingNote, style: const TextStyle(color: Colors.amber, fontSize: 13)),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 44, mainAxisSpacing: 4, crossAxisSpacing: 4),
            itemCount: _colors.length,
            itemBuilder: (ctx, i) => _swatch(_colors[i]),
          ),
        ),
      ]);

  Widget _swatch(Color c) => GestureDetector(
        onTap: () => _colorSheet(c),
        onLongPress: () => _colorSheet(c),
        onSecondaryTap: () => _colorSheet(c),
        child: LayoutBuilder(
          builder: (ctx, cons) =>
              AlphaSwatch(color: c, width: cons.maxWidth, height: cons.maxHeight, diagonal: true, borderRadius: 4),
        ),
      );

  // Reject is live only when there is a palette to reject. The other button is Accept while a
  // palette is (or may still be) coming — inert during extraction — and reads "Close" once the
  // outcome is a message: nothing to accept about a failure (user decision 2026-09-01).
  Widget _buttons() {
    final terminalMessage = _status != ArtworkColorsStatus.extracting && !_ready;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _ready ? () => Navigator.of(context).pop() : null,
              child: Text(context.l10n.acReject),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _accent),
              onPressed: _ready ? _accept : (terminalMessage ? () => Navigator.of(context).pop() : null),
              child: Text(terminalMessage ? context.l10n.commonClose : context.l10n.acAccept),
            ),
          ),
        ]),
      ),
    );
  }
}
