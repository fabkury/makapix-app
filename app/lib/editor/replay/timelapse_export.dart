import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:makapix_club/engine_ffi.dart';

import 'action_runner.dart';
import 'journal_format.dart';
import 'mp4_channel.dart';
import 'timelapse_plan.dart';

/// The letterbox/padding color behind the upscaled art (0xRRGGBBAA, opaque dark).
const int kTimelapseBg = 0x141518FF;

/// What a finished export produced: an MP4 file path (mobile) or in-memory container
/// bytes (Windows WebP/GIF).
class TimelapseResult {
  const TimelapseResult.path(String this.mp4Path) : bytes = null;
  const TimelapseResult.bytes(Uint8List this.bytes) : mp4Path = null;
  const TimelapseResult.canceled()
      : mp4Path = null,
        bytes = null;

  final String? mp4Path;
  final Uint8List? bytes;
  bool get isCanceled => mp4Path == null && bytes == null;
}

/// Everything the export isolate needs, sent once at spawn. All fields are
/// isolate-sendable (plain data + SendPort + RootIsolateToken).
class _TimelapseJob {
  _TimelapseJob({
    required this.journalText,
    required this.bases,
    required this.entries,
    required this.outW,
    required this.outH,
    required this.mode,
    required this.mp4Path,
    required this.bitrateBps,
    required this.wordmarkRgba,
    required this.wmW,
    required this.wmH,
    required this.wmX,
    required this.wmY,
    required this.token,
    required this.reply,
  });

  final String journalText;
  final Map<String, Uint8List> bases;
  final List<TimelapseEntry> entries;
  final int outW;
  final int outH;
  final String mode; // 'mp4' | 'webp' | 'gif'
  final String? mp4Path;
  final int bitrateBps;
  final Uint8List? wordmarkRgba;
  final int wmW, wmH, wmX, wmY;
  final RootIsolateToken? token;
  final SendPort reply;
}

/// Runs a Timelapse export on its own isolate (its own engine — the established pattern:
/// the opaque session pointer never crosses isolates). Progress lands on [progress]
/// (0..1); [cancel] aborts between frames.
class TimelapseExporter {
  final ValueNotifier<double> progress = ValueNotifier(0);
  SendPort? _cmd;
  bool _canceled = false;

  void cancel() {
    _canceled = true;
    _cmd?.send('cancel');
  }

  Future<TimelapseResult> run({
    required String journalText,
    required Map<String, Uint8List> bases,
    required List<TimelapseEntry> entries,
    required TimelapseShape shape,
    required String mode,
    String? mp4Path,
    int bitrateBps = 2_500_000,
    Uint8List? wordmarkRgba,
    int wmW = 0,
    int wmH = 0,
    int wmX = 0,
    int wmY = 0,
  }) async {
    final reply = ReceivePort();
    final job = _TimelapseJob(
      journalText: journalText,
      bases: bases,
      entries: entries,
      outW: shape.outW,
      outH: shape.outH,
      mode: mode,
      mp4Path: mp4Path,
      bitrateBps: bitrateBps,
      wordmarkRgba: wordmarkRgba,
      wmW: wmW,
      wmH: wmH,
      wmX: wmX,
      wmY: wmY,
      token: mode == 'mp4' ? RootIsolateToken.instance : null,
      reply: reply.sendPort,
    );
    final isolate = await Isolate.spawn(_timelapseWorker, job, debugName: 'timelapse-export');
    try {
      await for (final msg in reply) {
        final m = msg as Map;
        if (m.containsKey('cmd')) {
          _cmd = m['cmd'] as SendPort;
          if (_canceled) _cmd!.send('cancel'); // canceled before the port arrived
        } else if (m.containsKey('progress')) {
          progress.value = (m['progress'] as num).toDouble();
        } else if (m.containsKey('done-path')) {
          return TimelapseResult.path(m['done-path'] as String);
        } else if (m.containsKey('done-bytes')) {
          return TimelapseResult.bytes(
              (m['done-bytes'] as TransferableTypedData).materialize().asUint8List());
        } else if (m.containsKey('canceled')) {
          return const TimelapseResult.canceled();
        } else if (m.containsKey('error')) {
          throw TimelapseExportException(m['error'] as String);
        }
      }
      throw const TimelapseExportException('export isolate exited unexpectedly');
    } finally {
      reply.close();
      isolate.kill(priority: Isolate.beforeNextEvent);
    }
  }
}

class TimelapseExportException implements Exception {
  const TimelapseExportException(this.message);
  final String message;
  @override
  String toString() => 'TimelapseExportException: $message';
}

Future<void> _timelapseWorker(_TimelapseJob job) async {
  final cmd = ReceivePort();
  var canceled = false;
  cmd.listen((msg) {
    if (msg == 'cancel') canceled = true;
  });
  job.reply.send({'cmd': cmd.sendPort});

  Engine? engine;
  final mp4 = job.mode == 'mp4' ? Mp4EncoderChannel() : null;
  var mp4Started = false;
  var pushStarted = false;
  try {
    if (job.token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(job.token!);
    }
    final parsed = parseJournal(job.journalText);
    if (parsed == null) throw const TimelapseExportException('unreadable journal');
    final flat = FlatJournal.from(parsed);
    engine = Engine(64, 64);

    // Sink init.
    final isI420 = job.mode == 'mp4';
    if (mp4 != null) {
      await mp4.start(
        width: job.outW,
        height: job.outH,
        fps: 30,
        bitrateBps: job.bitrateBps,
        path: job.mp4Path!,
      );
      mp4Started = true;
    } else {
      final fmt = job.mode == 'gif' ? 0 : 1;
      if (!engine.tlEncodeBegin(fmt, job.outW, job.outH)) {
        throw const TimelapseExportException('encoder init failed');
      }
      pushStarted = true;
    }

    // Linear replay with frame emission at each entry.
    var pos = 0;
    void advanceTo(int target) {
      while (pos < target) {
        final base = flat.chapterBaseAt[pos];
        if (base != null) {
          final bytes = job.bases[base];
          if (bytes == null || !engine!.load(bytes).loaded) {
            throw TimelapseExportException('chapter base $base failed to load');
          }
        }
        var end = target;
        for (var i = pos + 1; i < end; i++) {
          if (flat.chapterBaseAt.containsKey(i)) {
            end = i;
            break;
          }
        }
        // Drop only lines the engine rejects (e.g. verbs from a newer app), never the batch
        // remainder — the previous code discarded the error entirely.
        runActionsSkippingBad(engine!.run, flat.actions, pos, end, onSkip: debugPrint);
        pos = end;
      }
    }

    var ptsUs = 0;
    var overlayOn = false;
    var lastFrame = Uint8List(0);
    final total = job.entries.length;
    for (var i = 0; i < total; i++) {
      if (canceled) {
        job.reply.send({'canceled': true});
        return;
      }
      final e = job.entries[i];
      if (e.isFinale) {
        // The finale begins: the whole journal has replayed; brand the padding (only when
        // a placement was computed — never over the pixels).
        if (!overlayOn && job.wordmarkRgba != null) {
          engine.setTimelapseOverlay(job.wordmarkRgba, job.wmW, job.wmH, job.wmX, job.wmY);
          overlayOn = true;
        }
      } else {
        advanceTo(e.position!);
      }
      final frameIndex = e.isFinale ? e.frameIndex! : engine.activeFrame;
      final scale = letterboxScale(engine.width, engine.height, job.outW, job.outH);
      final frame = engine.timelapseFrame(
          frameIndex, scale, job.outW, job.outH, kTimelapseBg, isI420 ? 1 : 0);
      if (frame.isEmpty) throw const TimelapseExportException('frame render failed');
      if (mp4 != null) {
        await mp4.feed(frame, ptsUs);
        ptsUs += e.durationUs;
        lastFrame = frame;
      } else {
        if (!engine.tlEncodePush(frame, (e.durationUs / 1000).round().clamp(1, 1 << 24))) {
          throw const TimelapseExportException('frame encode failed');
        }
      }
      if (i % 10 == 0 || i == total - 1) {
        job.reply.send({'progress': (i + 1) / total});
      }
      // Yield so the cancel listener runs even between synchronous encodes.
      await Future<void>.delayed(Duration.zero);
    }

    if (mp4 != null) {
      // The muxer derives durations from PTS deltas, so the final frame's hold would be
      // lost — close the stream with a duplicate frame at the end timestamp.
      if (lastFrame.isNotEmpty) await mp4.feed(lastFrame, ptsUs);
      final path = await mp4.finish();
      mp4Started = false;
      job.reply.send({'done-path': path});
    } else {
      final bytes = engine.tlEncodeEnd();
      pushStarted = false;
      if (bytes.isEmpty) throw const TimelapseExportException('encoder finalization failed');
      job.reply.send({'done-bytes': TransferableTypedData.fromList([bytes])});
    }
  } catch (e) {
    if (mp4 != null && mp4Started) await mp4.abort();
    if (pushStarted) engine?.tlEncodeAbort();
    job.reply.send({'error': e.toString()});
  } finally {
    if (engine != null) {
      engine.setTimelapseOverlay(null, 0, 0, 0, 0); // process-wide — always clear
      engine.dispose();
    }
    cmd.close();
  }
}
