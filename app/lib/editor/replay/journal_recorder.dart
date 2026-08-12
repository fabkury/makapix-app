import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'journal_format.dart';

/// How [JournalRecorder.attachResume] reconciled the Journal with the loaded document.
enum JournalAttachOutcome {
  /// The journal's tail matches a marker for the loaded bytes (trimmed to it if needed):
  /// recording continues in the current chapter.
  continued,

  /// The journal could not be reconciled (missing/foreign/damaged, or no marker matches):
  /// the caller must cut a chapter anchored on the engine's ACTUAL current content
  /// (`cutChapter(engine.saveCompact(), reason: 'reanchor')`) before recording continues.
  reanchorNeeded,
}

/// The always-on Journal writer for ONE drawing (ADR 0003; CONTEXT.md "Journal").
///
/// Engine-free and injectable ([dir] + [clock]) — unit-tested like the autosave controller.
/// Ordering guarantees, load-bearing for crash safety:
///  * a chapter-base FILE is durably on disk before the header line that references it is
///    appended (a crash between them leaves a harmless orphan file, never a dangling ref);
///  * [markerBeforeSave] resolves only after every buffered line AND the marker are
///    appended + fsynced — the autosave calls it before `writeDoc`, making the journal
///    write-ahead of the document it describes;
///  * [record] never throws and never blocks: it is a synchronous buffer append, drained
///    by a single-flight writer (the autosave `_drain` idiom).
///
/// IO shape: open-append-fsync-close per drain — no standing file handle, so the drawing
/// folder stays deletable on Windows and attach-time trims can truncate freely.
class JournalRecorder {
  JournalRecorder({required this.dir, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Directory dir;
  final DateTime Function() _clock;

  File get _file => File(p.join(dir.path, kJournalFileName));

  bool _attached = false;
  int _chapterSeq = 0;
  int _lastEventWallMs = 0;
  int _actionCount = 0;
  final List<_Op> _queue = [];
  bool _draining = false;
  Future<void> _drainDone = Future<void>.value();

  bool get isAttached => _attached;

  /// Recorded action lines so far (post-trim on resume) — telemetry/tests.
  int get actionCount => _actionCount;

  /// The current chapter sequence number (0 = no chapter yet).
  int get chapterSeq => _chapterSeq;

  // ---- attach ----------------------------------------------------------------

  /// Brand-new blank drawing: version header + chapter 1 (base=none, reason=fresh).
  /// The caller must then emit `NewDocument(w,h)` and the settings baseline THROUGH the
  /// DSL seam, so the live engine and the journal converge from a common origin.
  Future<void> attachFresh() async {
    final t = _clock();
    _chapterSeq = 1;
    _lastEventWallMs = t.millisecondsSinceEpoch;
    _append('$kJournalVersionHeader\n${chapterHeaderLine(1, t, null, 'fresh')}\n');
    _attached = true;
    await flush();
  }

  /// Brand-new drawing whose content arrived as bytes (external `.mkpx` open, Club
  /// edit/remix): chapter 1 anchored on [baseBytes]. The caller then emits the baseline.
  Future<void> attachFreshWithBase(Uint8List baseBytes, {required String reason}) async {
    final t = _clock();
    _chapterSeq = 1;
    _lastEventWallMs = t.millisecondsSinceEpoch;
    final name = chapterBaseFileName(1);
    _queue.add(_ChapterFileOp(name, baseBytes));
    _append('$kJournalVersionHeader\n${chapterHeaderLine(1, t, name, reason)}\n');
    _attached = true;
    await flush();
  }

  /// Existing library drawing. [docFnv] = the autosave FNV-1a-64 of the bytes actually
  /// loaded into the engine (null when unknown — e.g. the load failed). Reconciles the
  /// journal with that document: repairs a torn tail, then trims back to the LATEST
  /// matching marker ([JournalAttachOutcome.continued]), or asks the caller to re-anchor.
  /// Existing content is never destroyed — an unreconcilable journal is either kept (a
  /// re-anchor chapter is appended after it) or, when structurally invalid, renamed aside.
  Future<JournalAttachOutcome> attachResume({int? docFnv}) async {
    try {
      final outcome = await _attachResumeInner(docFnv);
      _attached = true;
      return outcome;
    } catch (e) {
      debugPrint('journal resume failed (re-anchoring): $e');
      _attached = true;
      return JournalAttachOutcome.reanchorNeeded;
    }
  }

  Future<JournalAttachOutcome> _attachResumeInner(int? docFnv) async {
    if (!await _file.exists()) {
      _append('$kJournalVersionHeader\n');
      await flush();
      return JournalAttachOutcome.reanchorNeeded;
    }
    final bytes = await _file.readAsBytes();
    final scan = scanJournalBytes(bytes);

    // A structurally foreign file (bad/missing version header) is renamed aside — never
    // overwritten — and a fresh journal starts.
    if (scan.lines.isEmpty || scan.lines.first.text.trim() != kJournalVersionHeader) {
      final aside = '${_file.path}.bad-${_clock().millisecondsSinceEpoch}';
      try {
        await _file.rename(aside);
      } catch (_) {}
      _append('$kJournalVersionHeader\n');
      await flush();
      return JournalAttachOutcome.reanchorNeeded;
    }

    // Repair a torn trailing fragment (crash mid-append: always the physical tail).
    if (scan.tornTailStart != null) {
      await _truncateTo(scan.tornTailStart!);
    }

    // Find the LATEST marker matching the loaded document's byte hash.
    int? trimTo;
    if (docFnv != null) {
      final want = docFnv & 0x7FFFFFFFFFFFFFFF;
      for (final line in scan.lines) {
        final fnv = parseMarkerLine(line.text);
        if (fnv != null && fnv == want) trimTo = line.end;
      }
    }
    if (trimTo == null) {
      // No reconcilable point. Keep the content; the caller appends a re-anchor chapter.
      _restoreStateFromScan(scan.lines, scan.lines.length);
      return JournalAttachOutcome.reanchorNeeded;
    }

    // Verify every chapter base referenced BEFORE the trim point still exists (a crash
    // window or external tampering could have removed one — replay would dead-end).
    var linesBeforeTrim = 0;
    for (final line in scan.lines) {
      if (line.end > trimTo) break;
      linesBeforeTrim++;
      final chapter = parseChapterHeaderLine(line.text);
      if (chapter?.base != null && !File(p.join(dir.path, chapter!.base!)).existsSync()) {
        _restoreStateFromScan(scan.lines, scan.lines.length);
        return JournalAttachOutcome.reanchorNeeded;
      }
    }

    await _truncateTo(trimTo);
    _restoreStateFromScan(scan.lines, linesBeforeTrim);
    return JournalAttachOutcome.continued;
  }

  /// Rebuild recorder state (chapter seq, action count, last event wall time) from the
  /// first [lineCount] scanned lines.
  void _restoreStateFromScan(List<ScannedLine> lines, int lineCount) {
    _chapterSeq = 0;
    _actionCount = 0;
    var chapterT = 0;
    var sumDeltas = 0;
    for (final line in lines.take(lineCount)) {
      final chapter = parseChapterHeaderLine(line.text);
      if (chapter != null) {
        _chapterSeq = chapter.seq;
        chapterT = chapter.t.millisecondsSinceEpoch;
        sumDeltas = 0;
        continue;
      }
      final action = parseActionLine(line.text);
      if (action != null) {
        _actionCount++;
        sumDeltas += action.deltaMs;
      }
    }
    _lastEventWallMs = chapterT + sumDeltas;
  }

  Future<void> _truncateTo(int length) async {
    final raf = await _file.open(mode: FileMode.append);
    try {
      await raf.truncate(length);
    } finally {
      await raf.close();
    }
  }

  // ---- recording -------------------------------------------------------------

  /// Verbatim tap for one DSL line as sent to the engine. Synchronous, non-throwing,
  /// no-op while detached. A defensive embedded `\n` splits into continuation lines
  /// (`+0`-prefixed) so one record is always whole physical lines.
  ///
  /// Playback preview verbs (Play/Pause/AdvanceClock — vsync clock chatter, up to
  /// 120/s) are excluded HERE, centrally, so every tap stays verbatim and the policy
  /// has one tested home. A dropped record advances neither [_lastEventWallMs] nor
  /// [_actionCount]: the NEXT real action's delta then spans the playback period, so
  /// Σ-deltas == wall clock still holds for [_restoreStateFromScan]. The parse side
  /// keeps understanding these verbs (old journals contain them; visible_index already
  /// marks them invisible). The AdvanceClock match is a prefix test: a multi-statement
  /// line BEGINNING with it would be dropped whole — acceptable, playback verbs are
  /// only ever sent standalone (editor_page.engine.dart is the sole sender).
  void record(String dsl) {
    if (!_attached) return;
    final parts = dsl.split('\n').where((s) => !_isPlaybackVerb(s)).toList();
    if (parts.isEmpty) return; // wall clock deliberately NOT advanced (see above)
    final now = _clock().millisecondsSinceEpoch;
    final delta = (now - _lastEventWallMs).clamp(0, 0x7FFFFFFFFFFF);
    _lastEventWallMs = now;
    final sb = StringBuffer(actionLine(delta, parts.first))..write('\n');
    for (final cont in parts.skip(1)) {
      sb
        ..write(actionLine(0, cont))
        ..write('\n');
    }
    _actionCount += parts.length;
    _append(sb.toString());
    if (_pendingBytes > 64 * 1024) unawaited(flush()); // preview-heavy safety valve
  }

  static bool _isPlaybackVerb(String s) {
    final t = s.trim();
    return t == 'Play()' || t == 'Pause()' || t.startsWith('AdvanceClock(');
  }

  /// Close the current chapter and open the next, anchored on [baseBytes]. The header is
  /// enqueued synchronously — any [record] issued after this call lands in the new
  /// chapter — and the base file write is ordered BEFORE the header's append.
  Future<void> cutChapter(Uint8List baseBytes, {required String reason}) async {
    if (!_attached) return;
    final t = _clock();
    _chapterSeq += 1;
    _lastEventWallMs = t.millisecondsSinceEpoch;
    final name = chapterBaseFileName(_chapterSeq);
    _queue.add(_ChapterFileOp(name, baseBytes));
    _append('${chapterHeaderLine(_chapterSeq, t, name, reason)}\n');
    await flush();
  }

  /// Write-ahead marker for an imminent autosave of bytes hashing to [fnv64]: drains
  /// every buffered line plus the marker, fsynced, before resolving. The autosave invokes
  /// this from its drain immediately before `writeDoc`.
  Future<void> markerBeforeSave(int fnv64) async {
    if (!_attached) return;
    _append('${markerLine(fnv64)}\n');
    await flush();
  }

  // ---- draining --------------------------------------------------------------

  int get _pendingBytes {
    var n = 0;
    for (final op in _queue) {
      if (op is _AppendOp) n += op.text.length;
    }
    return n;
  }

  void _append(String text) {
    final tail = _queue.isNotEmpty ? _queue.last : null;
    if (tail is _AppendOp) {
      tail.text.write(text);
    } else {
      _queue.add(_AppendOp()..text.write(text));
    }
  }

  /// Drain the op queue to disk in order (single-flight; concurrent callers share the
  /// same completion).
  Future<void> flush() {
    if (_draining) {
      // The active drain loops until the queue is empty, so ops enqueued before this call
      // are covered by the in-flight completion.
      return _drainDone;
    }
    _draining = true;
    final done = _drain().whenComplete(() => _draining = false);
    _drainDone = done;
    return done;
  }

  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final op = _queue.removeAt(0);
      try {
        switch (op) {
          case _ChapterFileOp(:final name, :final bytes):
            // tmp → rename, the store's atomic-write pattern; the base is immutable after.
            await dir.create(recursive: true);
            final tmp = File(p.join(dir.path, '$name.tmp'));
            await tmp.writeAsBytes(bytes, flush: true);
            await tmp.rename(p.join(dir.path, name));
          case _AppendOp(:final text):
            await dir.create(recursive: true);
            final raf = await _file.open(mode: FileMode.append);
            try {
              await raf.writeFrom(utf8.encode(text.toString()));
              await raf.flush();
            } finally {
              await raf.close();
            }
        }
      } catch (e) {
        // A journal write must never break editing: drop the op, log, move on. The
        // consistency story self-heals — a missing marker just re-anchors on next attach.
        debugPrint('journal write failed: $e');
      }
    }
  }

  // ---- teardown --------------------------------------------------------------

  /// Flush and stop recording. Awaited by switch paths before any `store.delete`, so no
  /// append is in flight when the folder is removed (Windows file locks).
  Future<void> detach() async {
    _attached = false;
    await flush();
  }

  /// Fire-and-forget [detach] for `dispose()` — everything recorded so far was captured
  /// synchronously as strings, so nothing here touches the engine.
  void detachSoon() {
    _attached = false;
    unawaited(flush());
  }
}

sealed class _Op {}

class _AppendOp extends _Op {
  final StringBuffer text = StringBuffer();
}

class _ChapterFileOp extends _Op {
  _ChapterFileOp(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}
