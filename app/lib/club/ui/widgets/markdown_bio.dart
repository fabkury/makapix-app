import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'external_links.dart';

/// The Club bio mini-markdown — a deliberate mirror of the website's
/// `MarkdownBio.tsx`, which is NOT full markdown but a tiny inline language:
///
///   **bold** · *italic* · [text](url) · `code` · [text]{color:#hex|name}
///
/// No nesting, no block elements; newlines pass through as-is.

/// One parsed run of bio text.
class BioSegment {
  final String text;
  final String type; // text | bold | italic | code | link | color
  final String? url; // link only
  final Color? color; // color only
  const BioSegment(this.text, this.type, {this.url, this.color});
}

// The website's allowed named colors (CSS values).
const Map<String, Color> _namedColors = {
  'red': Color(0xFFFF0000),
  'blue': Color(0xFF0000FF),
  'green': Color(0xFF008000),
  'yellow': Color(0xFFFFFF00),
  'purple': Color(0xFF800080),
  'pink': Color(0xFFFFC0CB),
  'cyan': Color(0xFF00FFFF),
  'white': Color(0xFFFFFFFF),
  'black': Color(0xFF000000),
  'orange': Color(0xFFFFA500),
  'gray': Color(0xFF808080),
  'grey': Color(0xFF808080),
  'magenta': Color(0xFFFF00FF),
  'lime': Color(0xFF00FF00),
  'teal': Color(0xFF008080),
  'navy': Color(0xFF000080),
  'maroon': Color(0xFF800000),
  'olive': Color(0xFF808000),
};

/// `#rgb` / `#rrggbb` or a name from the website's allowlist; null = invalid
/// (the segment renders as plain text, like the website).
Color? parseBioColor(String raw) {
  final s = raw.trim().toLowerCase();
  final named = _namedColors[s];
  if (named != null) return named;
  final m = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6})$').firstMatch(s);
  if (m == null) return null;
  var hex = m.group(1)!;
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  return Color(int.parse('ff$hex', radix: 16));
}

class _Pattern {
  final RegExp regex;
  final String type;
  const _Pattern(this.regex, this.type);
}

// Order matters — more specific first (same list and order as the website).
final List<_Pattern> _patterns = [
  _Pattern(RegExp(r'\[([^\]]+)\]\{color:([^}]+)\}'), 'color'),
  _Pattern(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), 'link'),
  _Pattern(RegExp(r'\*\*([^*]+)\*\*'), 'bold'),
  _Pattern(RegExp(r'\*([^*]+)\*'), 'italic'),
  _Pattern(RegExp(r'`([^`]+)`'), 'code'),
];

/// Pure parse: overlapping matches keep the earlier start (ties: the more
/// specific pattern), everything else passes through as plain text.
///
/// Known quirk, kept deliberately for website parity: each regex scans
/// non-overlappingly on its own, so in `**b** *i*` the italic pattern first
/// eats the phantom `* *` (bold closer + italic opener) and the real `*i*`
/// is never seen — the website renders it as literal text too. Change only
/// together with `MarkdownBio.tsx`.
List<BioSegment> parseBioMarkdown(String text) {
  final matches = <({int start, int end, int prio, String type, Match m})>[];
  for (var p = 0; p < _patterns.length; p++) {
    for (final m in _patterns[p].regex.allMatches(text)) {
      matches.add((start: m.start, end: m.end, prio: p, type: _patterns[p].type, m: m));
    }
  }
  matches.sort((a, b) => a.start != b.start ? a.start - b.start : a.prio - b.prio);

  final out = <BioSegment>[];
  var cursor = 0;
  for (final x in matches) {
    if (x.start < cursor) continue; // overlaps an accepted match
    if (x.start > cursor) out.add(BioSegment(text.substring(cursor, x.start), 'text'));
    final inner = x.m.group(1)!;
    switch (x.type) {
      case 'color':
        final c = parseBioColor(x.m.group(2)!);
        // Invalid color → the raw source renders as plain text (website parity).
        out.add(c == null
            ? BioSegment(text.substring(x.start, x.end), 'text')
            : BioSegment(inner, 'color', color: c));
      case 'link':
        final url = x.m.group(2)!.trim();
        // Stricter than the website: only http(s) becomes a tappable link.
        final ok = url.toLowerCase().startsWith('http://') ||
            url.toLowerCase().startsWith('https://');
        out.add(ok
            ? BioSegment(inner, 'link', url: url)
            : BioSegment(text.substring(x.start, x.end), 'text'));
      default:
        out.add(BioSegment(inner, x.type));
    }
    cursor = x.end;
  }
  if (cursor < text.length) out.add(BioSegment(text.substring(cursor), 'text'));
  return out;
}

/// Renders a bio with the mini-markdown above. Links open externally.
class MarkdownBio extends StatefulWidget {
  final String bio;
  final TextStyle style;
  const MarkdownBio({super.key, required this.bio, this.style = const TextStyle(fontSize: 13)});

  @override
  State<MarkdownBio> createState() => _MarkdownBioState();
}

class _MarkdownBioState extends State<MarkdownBio> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final linkColor = Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    for (final s in parseBioMarkdown(widget.bio)) {
      switch (s.type) {
        case 'bold':
          spans.add(TextSpan(text: s.text, style: const TextStyle(fontWeight: FontWeight.w700)));
        case 'italic':
          spans.add(TextSpan(text: s.text, style: const TextStyle(fontStyle: FontStyle.italic)));
        case 'code':
          spans.add(TextSpan(
              text: s.text,
              style: const TextStyle(
                  fontFamily: 'monospace', backgroundColor: Color(0x33FFFFFF))));
        case 'color':
          spans.add(TextSpan(text: s.text, style: TextStyle(color: s.color)));
        case 'link':
          final r = TapGestureRecognizer()
            ..onTap = () => openExternalUrl(context, s.url!);
          _recognizers.add(r);
          spans.add(TextSpan(
              text: s.text,
              style: TextStyle(color: linkColor, decoration: TextDecoration.underline),
              recognizer: r));
        default:
          spans.add(TextSpan(text: s.text));
      }
    }
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
