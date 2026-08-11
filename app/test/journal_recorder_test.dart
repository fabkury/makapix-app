import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/persistence/autosave_controller.dart';
import 'package:makapix_club/editor/replay/journal_format.dart';
import 'package:makapix_club/editor/replay/journal_recorder.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late DateTime now;
  DateTime clock() => now;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mkpx_journal_test');
    now = DateTime.utc(2026, 8, 11, 12, 0, 0);
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  File journalFile() => File(p.join(dir.path, kJournalFileName));
  Future<String> journalText() => journalFile().readAsString();
  Uint8List base(int fill) => Uint8List.fromList(List.filled(64, fill));

  JournalRecorder recorder() => JournalRecorder(dir: dir, clock: clock);

  group('attachFresh', () {
    test('writes version header + chapter 1 (base=none, reason=fresh)', () async {
      final j = recorder();
      await j.attachFresh();
      final lines = const LineSplitter().convert(await journalText());
      expect(lines[0], kJournalVersionHeader);
      final c = parseChapterHeaderLine(lines[1])!;
      expect(c.seq, 1);
      expect(c.base, isNull);
      expect(c.reason, 'fresh');
      expect(j.isAttached, isTrue);
      expect(j.chapterSeq, 1);
    });
  });

  group('attachFreshWithBase', () {
    test('chapter base file is durably written and referenced', () async {
      final j = recorder();
      await j.attachFreshWithBase(base(7), reason: 'open');
      final baseFile = File(p.join(dir.path, chapterBaseFileName(1)));
      expect(await baseFile.readAsBytes(), base(7));
      final lines = const LineSplitter().convert(await journalText());
      expect(parseChapterHeaderLine(lines[1])!.base, chapterBaseFileName(1));
      expect(File(p.join(dir.path, '${chapterBaseFileName(1)}.tmp')).existsSync(), isFalse);
    });
  });

  group('record + deltas', () {
    test('first delta offsets from the header t, then relative; skew clamps to 0', () async {
      final j = recorder();
      await j.attachFresh();
      now = now.add(const Duration(milliseconds: 1234));
      j.record('PointerDown(1,1)');
      now = now.add(const Duration(milliseconds: 16));
      j.record('PointerMove(2,2)');
      now = now.subtract(const Duration(milliseconds: 500)); // clock skew backwards
      j.record('PointerUp()');
      await j.flush();
      final actions = parseJournal(await journalText())!.chapters.single.actions;
      expect(actions.map((a) => a.deltaMs).toList(), [1234, 16, 0]);
      expect(j.actionCount, 3);
    });

    test('an embedded newline splits into +0 continuation lines', () async {
      final j = recorder();
      await j.attachFresh();
      j.record('Tap(1,1)\nTap(2,2)');
      await j.flush();
      final actions = parseJournal(await journalText())!.chapters.single.actions;
      expect(actions.length, 2);
      expect(actions[1].deltaMs, 0);
    });

    test('record while detached is a no-op and never throws', () {
      final j = recorder();
      expect(() => j.record('Tap(1,1)'), returnsNormally);
      expect(j.actionCount, 0);
    });
  });

  group('markerBeforeSave ordering', () {
    test('buffered lines are on disk before the marker line', () async {
      final j = recorder();
      await j.attachFresh();
      j.record('Tap(3,3)');
      await j.markerBeforeSave(0xABC);
      final lines = const LineSplitter().convert(await journalText());
      final tapIdx = lines.indexWhere((l) => l.contains('Tap(3,3)'));
      final markerIdx = lines.indexWhere((l) => parseMarkerLine(l) != null);
      expect(tapIdx, isNot(-1));
      expect(markerIdx, greaterThan(tapIdx));
      expect(parseMarkerLine(lines[markerIdx]), 0xABC);
    });
  });

  group('cutChapter', () {
    test('later records land after the header; base ordered before header', () async {
      final j = recorder();
      await j.attachFresh();
      j.record('Tap(1,1)');
      final cut = j.cutChapter(base(9), reason: 'import');
      j.record('Tap(2,2)'); // issued while the cut is in flight
      await cut;
      await j.flush();
      final parsed = parseJournal(await journalText())!;
      expect(parsed.chapters.length, 2);
      expect(parsed.chapters[0].actions.map((a) => a.dsl), ['Tap(1,1)']);
      expect(parsed.chapters[1].actions.map((a) => a.dsl), ['Tap(2,2)']);
      expect(File(p.join(dir.path, chapterBaseFileName(2))).existsSync(), isTrue);
    });
  });

  group('attachResume', () {
    Future<JournalRecorder> buildJournal({required int markerFnv}) async {
      final j = recorder();
      await j.attachFresh();
      j.record('NewDocument(64,64)');
      j.record('Tap(1,1)');
      await j.markerBeforeSave(markerFnv);
      await j.detach();
      return j;
    }

    test('in-sync tail → continued, no trim', () async {
      await buildJournal(markerFnv: 0x111);
      final before = await journalText();
      final j = recorder();
      expect(await j.attachResume(docFnv: 0x111), JournalAttachOutcome.continued);
      expect(await journalText(), before);
      expect(j.chapterSeq, 1);
      expect(j.actionCount, 2);
    });

    test('tail after the last matching marker is trimmed byte-exactly', () async {
      final j0 = await buildJournal(markerFnv: 0x222);
      final expected = await journalText();
      // Un-markered tail: actions the autosave never captured.
      final j1 = recorder();
      expect(await j1.attachResume(docFnv: 0x222), JournalAttachOutcome.continued);
      j1.record('Tap(9,9)');
      j1.record('Tap(8,8)');
      await j1.detach();
      expect(await journalText(), isNot(expected));
      final j2 = recorder();
      expect(await j2.attachResume(docFnv: 0x222), JournalAttachOutcome.continued);
      expect(await journalText(), expected, reason: 'trim must restore the exact marker suffix');
      expect(j0.actionCount, 2);
    });

    test('an EARLIER marker matches (the .bak fallback case) and trims to it', () async {
      final j = recorder();
      await j.attachFresh();
      j.record('Tap(1,1)');
      await j.markerBeforeSave(0x333); // the .bak's state
      final atBak = await journalText();
      j.record('Tap(2,2)');
      await j.markerBeforeSave(0x444); // the (now corrupt) primary's state
      j.record('Tap(3,3)');
      await j.detach();
      final j2 = recorder();
      expect(await j2.attachResume(docFnv: 0x333), JournalAttachOutcome.continued);
      expect(await journalText(), atBak);
    });

    test('no matching marker → reanchorNeeded, content preserved', () async {
      await buildJournal(markerFnv: 0x555);
      final before = await journalText();
      final j = recorder();
      expect(await j.attachResume(docFnv: 0x999), JournalAttachOutcome.reanchorNeeded);
      expect(await journalText(), before, reason: 'reanchor never destroys history');
      // The re-anchor chapter continues the sequence.
      await j.cutChapter(base(1), reason: 'reanchor');
      expect(parseJournal(await journalText())!.chapters.last.seq, 2);
    });

    test('null docFnv → reanchorNeeded', () async {
      await buildJournal(markerFnv: 0x666);
      final j = recorder();
      expect(await j.attachResume(docFnv: null), JournalAttachOutcome.reanchorNeeded);
    });

    test('no journal file → fresh version header + reanchorNeeded', () async {
      final j = recorder();
      expect(await j.attachResume(docFnv: 0x1), JournalAttachOutcome.reanchorNeeded);
      expect((await journalText()).startsWith(kJournalVersionHeader), isTrue);
    });

    test('foreign file is renamed aside, never overwritten', () async {
      await journalFile().writeAsString('not a journal at all\n');
      final j = recorder();
      expect(await j.attachResume(docFnv: 0x1), JournalAttachOutcome.reanchorNeeded);
      final aside = dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('$kJournalFileName.bad-'));
      expect(aside.length, 1);
      expect(await aside.first.readAsString(), 'not a journal at all\n');
    });

    test('torn trailing line is repaired before reconciliation', () async {
      await buildJournal(markerFnv: 0x777);
      // Simulate a crash mid-append: raw bytes without a trailing newline.
      final raf = await journalFile().open(mode: FileMode.append);
      await raf.writeFrom(utf8.encode('+5 PointerDo'));
      await raf.close();
      final j = recorder();
      expect(await j.attachResume(docFnv: 0x777), JournalAttachOutcome.continued);
      final text = await journalText();
      expect(text.endsWith('\n'), isTrue);
      expect(text.contains('PointerDo'), isFalse);
    });

    test('a referenced chapter base gone missing → reanchorNeeded', () async {
      final j = recorder();
      await j.attachFreshWithBase(base(5), reason: 'open');
      j.record('Tap(1,1)');
      await j.markerBeforeSave(0x888);
      await j.detach();
      await File(p.join(dir.path, chapterBaseFileName(1))).delete();
      final j2 = recorder();
      expect(await j2.attachResume(docFnv: 0x888), JournalAttachOutcome.reanchorNeeded);
    });

    test('wall-clock reconstruction: the first resumed delta spans the gap', () async {
      await buildJournal(markerFnv: 0x999);
      now = now.add(const Duration(hours: 3)); // a new sitting, hours later
      final j = recorder();
      expect(await j.attachResume(docFnv: 0x999), JournalAttachOutcome.continued);
      j.record('Tap(4,4)');
      await j.flush();
      final actions = parseJournal(await journalText())!.chapters.single.actions;
      expect(actions.last.deltaMs, const Duration(hours: 3).inMilliseconds);
    });
  });

  group('teardown', () {
    test('detach drains; the folder is deletable afterwards (Windows locks)', () async {
      final j = recorder();
      await j.attachFresh();
      j.record('Tap(1,1)');
      await j.detach();
      expect(j.isAttached, isFalse);
      await dir.delete(recursive: true); // must not throw (no held handle)
      expect(dir.existsSync(), isFalse);
      dir = await Directory.systemTemp.createTemp('mkpx_journal_test'); // for tearDown
    });
  });

  group('fnv contract', () {
    test('marker round-trips the autosave fnv1a64 of real bytes', () async {
      final bytes = Uint8List.fromList(utf8.encode('mkpx test bytes'));
      final fnv = AutosaveController.fnv1a64(bytes);
      expect(parseMarkerLine(markerLine(fnv)), fnv);
    });
  });
}
