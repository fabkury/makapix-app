import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/replay/journal_format.dart';

void main() {
  group('grammar round-trips', () {
    test('marker line', () {
      final line = markerLine(0x1a2b3c4d5e6f0718);
      expect(line, '# marker 1a2b3c4d5e6f0718');
      expect(parseMarkerLine(line), 0x1a2b3c4d5e6f0718);
      expect(parseMarkerLine('# marker zz'), isNull);
      expect(parseMarkerLine('+3 Tap(1,1)'), isNull);
    });

    test('marker masks to the autosave 63-bit convention', () {
      // fnv1a64 masks its result; markerLine must produce the identical value for a raw hash.
      expect(parseMarkerLine(markerLine(-1)), 0x7FFFFFFFFFFFFFFF);
    });

    test('chapter header', () {
      final t = DateTime.utc(2026, 8, 11, 14, 3, 22, 418);
      final line = chapterHeaderLine(2, t, 'chapter-0002.mkpx', 'import');
      final parsed = parseChapterHeaderLine(line)!;
      expect(parsed.seq, 2);
      expect(parsed.t, t);
      expect(parsed.base, 'chapter-0002.mkpx');
      expect(parsed.reason, 'import');
      // base=none → null base.
      expect(parseChapterHeaderLine(chapterHeaderLine(1, t, null, 'fresh'))!.base, isNull);
    });

    test('chapter header ignores unknown trailing fields (forward compat)', () {
      final parsed = parseChapterHeaderLine(
          '# chapter 3 t=2026-08-11T14:03:22.418Z base=none reason=fresh future=stuff x=1');
      expect(parsed, isNotNull);
      expect(parsed!.seq, 3);
      expect(parsed.reason, 'fresh');
    });

    test('action line', () {
      final line = actionLine(16, 'PointerMove(11,12); #trail');
      expect(line, '+16 PointerMove(11,12); #trail');
      final a = parseActionLine(line)!;
      expect(a.deltaMs, 16);
      expect(a.dsl, 'PointerMove(11,12); #trail');
      expect(parseActionLine('+x Tap(1,1)'), isNull);
      expect(parseActionLine('+-3 Tap(1,1)'), isNull);
      expect(parseActionLine('# marker abc'), isNull);
    });

    test('chapter base file names are zero-padded', () {
      expect(chapterBaseFileName(1), 'chapter-0001.mkpx');
      expect(chapterBaseFileName(123), 'chapter-0123.mkpx');
    });
  });

  group('parseJournal', () {
    test('parses chapters with actions; skips markers and unknown directives', () {
      final text = '$kJournalVersionHeader\n'
          '${chapterHeaderLine(1, DateTime.utc(2026), null, 'fresh')}\n'
          '+0 NewDocument(64,64)\n'
          '+0 SetSeed(7)\n'
          '${markerLine(42)}\n'
          '# future directive to skip\n'
          '+120 PointerDown(3,3)\n'
          '${chapterHeaderLine(2, DateTime.utc(2026, 2), 'chapter-0002.mkpx', 'import')}\n'
          '+5 Tap(1,1)\n';
      final j = parseJournal(text)!;
      expect(j.chapters.length, 2);
      expect(j.actionCount, 4);
      expect(j.chapters[0].actions.map((a) => a.dsl).toList(),
          ['NewDocument(64,64)', 'SetSeed(7)', 'PointerDown(3,3)']);
      expect(j.chapters[1].base, 'chapter-0002.mkpx');
      expect(j.chapters[1].actions.single.dsl, 'Tap(1,1)');
    });

    test('missing or wrong version header → null', () {
      expect(parseJournal(''), isNull);
      expect(parseJournal('#mkpxj 999\n+0 Tap(1,1)\n'), isNull);
      expect(parseJournal('+0 Tap(1,1)\n'), isNull);
    });

    // ADR 0015. A journal written by an older build MUST still parse: a header this rejects
    // makes attachResume treat the file as foreign and rename it aside, discarding the
    // artist's whole replay history. This test is the guard on that landmine.
    test('every past epoch stays readable, and reports its own epoch', () {
      for (var e = 1; e <= kJournalEpoch; e++) {
        final text = '#mkpxj $e\n'
            '${chapterHeaderLine(1, DateTime.utc(2026), null, 'fresh')}\n'
            '+0 Tap(1,1)\n';
        final j = parseJournal(text);
        expect(j, isNotNull, reason: 'epoch $e must remain readable');
        expect(j!.epoch, e);
        expect(j.chapters.single.actions.single.dsl, 'Tap(1,1)');
      }
    });

    test('new journals are written at the current epoch', () {
      expect(kJournalVersionHeader, '#mkpxj $kJournalEpoch');
      expect(journalEpochOf(kJournalVersionHeader), kJournalEpoch);
      expect(journalEpochOf('#mkpxj 1'), 1, reason: 'the pre-policy epoch');
      expect(journalEpochOf('not a header'), isNull);
      expect(journalEpochOf('#mkpxj 0'), isNull);
    });

    test('multi-statement lines stay verbatim', () {
      final text = '$kJournalVersionHeader\n'
          '${chapterHeaderLine(1, DateTime.utc(2026), null, 'fresh')}\n'
          '+0 SetBrushSize(3); SetBrushShape(Round)\n';
      final j = parseJournal(text)!;
      expect(j.chapters.single.actions.single.dsl, 'SetBrushSize(3); SetBrushShape(Round)');
    });
  });

  group('scanJournalBytes', () {
    test('byte offsets survive multi-byte UTF-8 in DSL text', () {
      final line1 = '+0 RenameLayer(0, "cão")'; // multi-byte ã
      final text = '$kJournalVersionHeader\n$line1\n+1 Tap(1,1)\n';
      final bytes = Uint8List.fromList(utf8.encode(text));
      final scan = scanJournalBytes(bytes);
      expect(scan.tornTailStart, isNull);
      expect(scan.lines.length, 3);
      expect(scan.lines[1].text, line1);
      // The third line's byte extent must slice back to exactly its bytes.
      final l2 = scan.lines[2];
      expect(utf8.decode(bytes.sublist(l2.start, l2.end)), '+1 Tap(1,1)\n');
    });

    test('torn trailing fragment is reported, complete lines kept', () {
      final bytes = Uint8List.fromList(utf8.encode('$kJournalVersionHeader\n+0 Tap(1,1)\n+5 PointerDo'));
      final scan = scanJournalBytes(bytes);
      expect(scan.lines.length, 2);
      expect(scan.tornTailStart, utf8.encode('$kJournalVersionHeader\n+0 Tap(1,1)\n').length);
    });

    test('CRLF tolerated in line text, extents include the newline bytes', () {
      final bytes = Uint8List.fromList(utf8.encode('$kJournalVersionHeader\r\n+0 Tap(1,1)\r\n'));
      final scan = scanJournalBytes(bytes);
      expect(scan.lines[0].text, kJournalVersionHeader);
      expect(scan.lines[1].text, '+0 Tap(1,1)');
      expect(scan.tornTailStart, isNull);
    });
  });
}
