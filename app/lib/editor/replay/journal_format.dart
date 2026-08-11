/// The Journal's on-disk grammar (ADR 0003) — pure: no dart:io, no engine.
///
/// A Journal is plain UTF-8 text, one record per line:
///
/// ```
/// #mkpxj 1
/// # chapter 1 t=2026-08-11T14:03:22.418Z base=none reason=fresh
/// +0 NewDocument(64,64)
/// +0 SetSeed(1754921002418)
/// +1234 PointerDown(10,12)
/// +16 PointerMove(11,12)
/// # marker 1a2b3c4d5e6f0718
/// # chapter 2 t=... base=chapter-0002.mkpx reason=import
/// ...
/// ```
///
/// Every directive is `#`-prefixed, which the engine's `run_script` skips — so a chapter's
/// action tail with the `+<delta-ms> ` prefixes stripped is a directly valid mkpx script
/// (the on-device validation path). Deltas are milliseconds since the previous action line
/// in the same chapter (the chapter header's `t` for the first). Chapter headers tolerate
/// unknown trailing `key=value` fields (forward compatibility).
library;

import 'dart:convert';
import 'dart:typed_data';

/// The version header — always the Journal's first line.
const String kJournalVersionHeader = '#mkpxj 1';

/// The Journal's file name inside a drawing's folder.
const String kJournalFileName = 'journal.mkpxj';

/// The immutable chapter-base file name for chapter [seq] (compact `.mkpx` bytes).
String chapterBaseFileName(int seq) => 'chapter-${seq.toString().padLeft(4, '0')}.mkpx';

/// Render one action line: `+<delta-ms> <verbatim dsl>`.
String actionLine(int deltaMs, String dsl) => '+$deltaMs $dsl';

/// Render a marker line for the autosave byte-hash (16 lowercase hex digits of FNV-1a-64).
String markerLine(int fnv64) =>
    '# marker ${(fnv64 & 0x7FFFFFFFFFFFFFFF).toRadixString(16).padLeft(16, '0')}';

/// Render a chapter header. [t] is stamped in UTC; [base] is a chapter-base file name or
/// null for a from-empty chapter; [reason] is diagnostic (fresh/open/club/import/reanchor).
String chapterHeaderLine(int seq, DateTime t, String? base, String reason) =>
    '# chapter $seq t=${t.toUtc().toIso8601String()} base=${base ?? 'none'} reason=$reason';

/// One parsed action: the delta and the verbatim DSL text (which may itself contain
/// `;`-separated statements — recorded and replayed as one line).
class JournalAction {
  const JournalAction(this.deltaMs, this.dsl);
  final int deltaMs;
  final String dsl;
}

/// One parsed chapter: its header fields plus the action lines in order. [base] is null for
/// a from-empty chapter (guaranteed by the recorder to begin with a `NewDocument` action).
class JournalChapter {
  JournalChapter({required this.seq, required this.t, required this.base, required this.reason});
  final int seq;
  final DateTime t;
  final String? base;
  final String reason;
  final List<JournalAction> actions = [];
}

/// A fully parsed Journal (the replay driver's model — offsets and markers are the
/// scanner's business, not this one's).
class ParsedJournal {
  ParsedJournal(this.chapters);
  final List<JournalChapter> chapters;
  int get actionCount => chapters.fold(0, (n, c) => n + c.actions.length);
}

/// Parse a marker line; null when [line] is not one.
int? parseMarkerLine(String line) {
  if (!line.startsWith('# marker ')) return null;
  return int.tryParse(line.substring('# marker '.length).trim(), radix: 16);
}

/// Parse a chapter header; null when [line] is not one. Unknown trailing `key=value`
/// fields are ignored.
JournalChapter? parseChapterHeaderLine(String line) {
  if (!line.startsWith('# chapter ')) return null;
  final parts = line.substring('# chapter '.length).trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return null;
  final seq = int.tryParse(parts.first);
  if (seq == null) return null;
  DateTime? t;
  String? base;
  var reason = '';
  for (final kv in parts.skip(1)) {
    final eq = kv.indexOf('=');
    if (eq <= 0) continue;
    final key = kv.substring(0, eq), value = kv.substring(eq + 1);
    switch (key) {
      case 't':
        t = DateTime.tryParse(value);
      case 'base':
        base = value == 'none' ? null : value;
      case 'reason':
        reason = value;
      default: // unknown field — forward compatible
    }
  }
  if (t == null) return null;
  return JournalChapter(seq: seq, t: t, base: base, reason: reason);
}

/// Parse an action line (`+<delta-ms> <dsl>`); null when [line] is not one.
JournalAction? parseActionLine(String line) {
  if (!line.startsWith('+')) return null;
  final sp = line.indexOf(' ');
  if (sp <= 1) return null;
  final delta = int.tryParse(line.substring(1, sp));
  if (delta == null || delta < 0) return null;
  return JournalAction(delta, line.substring(sp + 1));
}

/// Parse a whole Journal text into chapters for the replay driver. Returns null when the
/// version header is missing/unsupported. Directive lines it doesn't recognize (and marker
/// lines) are skipped — the format is additive.
ParsedJournal? parseJournal(String text) {
  final lines = const LineSplitter().convert(text);
  if (lines.isEmpty || lines.first.trim() != kJournalVersionHeader) return null;
  final chapters = <JournalChapter>[];
  for (final raw in lines.skip(1)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final chapter = parseChapterHeaderLine(line);
    if (chapter != null) {
      chapters.add(chapter);
      continue;
    }
    final action = parseActionLine(line);
    if (action != null && chapters.isNotEmpty) {
      chapters.last.actions.add(action);
    }
    // Anything else (markers, future directives) is skipped.
  }
  return ParsedJournal(chapters);
}

/// One physical line of a journal file with its BYTE extent — the trim/repair unit.
/// [end] is exclusive and includes the trailing newline byte(s).
class ScannedLine {
  const ScannedLine(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

/// The scanner's result: complete lines (each ending in `\n` in the file) plus whether a
/// torn trailing fragment (no final newline — a crash mid-append) follows them.
class JournalScan {
  const JournalScan(this.lines, this.tornTailStart);

  final List<ScannedLine> lines;

  /// Byte offset where a torn (newline-less) trailing fragment begins, or null when the
  /// file ends cleanly. Repair = truncate to this offset.
  final int? tornTailStart;
}

/// Scan raw journal bytes into complete lines with byte offsets (UTF-8 decoded per line,
/// malformed sequences replaced). Works on bytes — layer/palette names in DSL text can be
/// multi-byte, so string indices would lie about file offsets.
JournalScan scanJournalBytes(Uint8List bytes) {
  final lines = <ScannedLine>[];
  var start = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0x0A) {
      var textEnd = i;
      if (textEnd > start && bytes[textEnd - 1] == 0x0D) textEnd--; // tolerate CRLF
      lines.add(ScannedLine(start, i + 1, utf8.decode(bytes.sublist(start, textEnd), allowMalformed: true)));
      start = i + 1;
    }
  }
  return JournalScan(lines, start < bytes.length ? start : null);
}
