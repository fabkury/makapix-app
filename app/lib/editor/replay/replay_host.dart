import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:makapix_club/engine_ffi.dart';

import 'action_runner.dart';
import 'journal_format.dart';
import 'visible_index.dart' as vi;

/// What the Replay viewer needs from a replayable Journal — abstract so the page is
/// widget-testable without the engine DLL (the PaletteHost pattern).
abstract class ReplayHost {
  /// Total action lines across all chapters (positions 0..actionCount).
  int get actionCount;

  /// The positions whose transition visibly changes the canvas (ascending, ends at
  /// [actionCount]) — the tick axis the sweep and slider step through, so draft fiddling
  /// and settings churn never consume playback time. See visible_index.dart.
  List<int> get visiblePositions;

  /// True once [init] finished and seeking works.
  bool get ready;

  /// Non-null when [init] failed (a missing chapter base, an unreadable journal…).
  String? get initError;

  /// 0..1 while [init] replays the journal and builds checkpoints.
  ValueListenable<double> get initProgress;

  /// Parse the journal, replay it end-to-end building checkpoints, and settle at the
  /// final state. Runs on the UI isolate in slices (checkpoints cannot cross isolates);
  /// yields between slices so input stays live.
  Future<void> init();

  /// Move the document to the state after the first [position] actions (latest-wins:
  /// rapid calls coalesce to the newest target). Completes when the state is current.
  Future<void> seek(int position);

  /// The position the document currently shows.
  int get position;

  /// The composited canvas at the current position — the frame the ARTIST was editing
  /// (the replay follows their focus). Same reused-scratch contract as
  /// `Engine.compositeFrame`: consume synchronously, never store or await first.
  (Uint8List rgba, int w, int h) currentFrame();

  /// Authored per-frame durations (µs) of the FINISHED document — the timelapse finale's
  /// cycle math. Valid once [ready].
  List<int> get endFrameDurationsUs;

  /// Canvas size of the FINISHED document (the timelapse letterbox math). Valid once [ready].
  (int, int) get endSize;

  void dispose();
}

/// The real host: owns its own [Engine] (never the editor's live session) and drives it
/// through the journal with engine-side checkpoints for real-time scrubbing.
class EngineReplayHost implements ReplayHost {
  EngineReplayHost({required this.journalText, required this.bases});

  /// The journal file's text and the chapter-base files' bytes, read by the caller
  /// (the editor page has the store; the host stays store-agnostic for tests).
  final String journalText;
  final Map<String, Uint8List> bases;

  Engine? _engine;
  final List<String> _actions = []; // flat, prefix-stripped DSL in journal order
  final Map<int, String> _chapterBaseAt = {}; // action index -> base file to load first
  List<int> _visible = const [];
  final List<(int pos, int id)> _checkpoints = []; // ascending by pos
  List<int> _endDurations = const [];
  (int, int) _endSize = (64, 64);
  int _pos = 0;
  bool _ready = false;
  String? _error;
  final ValueNotifier<double> _progress = ValueNotifier(0);
  int? _wantPos; // latest-wins seek target
  bool _seeking = false;

  @override
  int get actionCount => _actions.length;
  @override
  List<int> get visiblePositions => _visible;
  @override
  bool get ready => _ready;
  @override
  String? get initError => _error;
  @override
  ValueListenable<double> get initProgress => _progress;
  @override
  int get position => _pos;
  @override
  List<int> get endFrameDurationsUs => _endDurations;
  @override
  (int, int) get endSize => _endSize;

  @override
  Future<void> init() async {
    try {
      final parsed = parseJournal(journalText);
      if (parsed == null || parsed.chapters.isEmpty) {
        _error = 'This drawing has no replayable history yet.';
        return;
      }
      final flat = FlatJournal.from(parsed);
      for (final base in flat.chapterBaseAt.values) {
        if (!bases.containsKey(base)) {
          _error = 'Part of this replay is missing (a chapter base file).';
          return;
        }
      }
      _actions.addAll(flat.actions);
      _chapterBaseAt.addAll(flat.chapterBaseAt);
      if (_actions.isEmpty) {
        _error = 'This drawing has no replayable history yet.';
        return;
      }
      _visible = vi.visiblePositions(flat);
      _engine = Engine(64, 64);
      // One forward pass to the end, checkpointing on a fixed stride plus at every chapter
      // start (so a seek never straddles a chapter boundary). ≤300 checkpoints ≈ the
      // measured ~36 MiB worst case; the engine's byte budget bounds adversarial content.
      // A checkpoint at position 0 anchors seek-to-start (from-empty chapters have no
      // boundary checkpoint there; based chapters add a post-load one that outranks it).
      _takeCheckpoint();
      final stride = _strideFor(_actions.length);
      await _advance(_actions.length, checkpointStride: stride);
      _endDurations = _readDurations();
      _endSize = (_engine!.width, _engine!.height);
      _ready = true;
    } catch (e) {
      _error = 'Could not prepare the replay: $e';
    } finally {
      _progress.value = 1;
    }
  }

  static int _strideFor(int actions) => (actions / 300).ceil().clamp(100, 1 << 30);

  List<int> _readDurations() {
    try {
      final st = json.decode(_engine!.stateJson()) as Map<String, dynamic>;
      final frames = st['frame_detail'] as List? ?? const [];
      return [for (final f in frames) (((f as Map)['duration_us'] as num?) ?? 100000).toInt()];
    } catch (_) {
      return const [100000];
    }
  }

  /// Run actions forward from [_pos] to [target], loading chapter bases at their
  /// boundaries, optionally taking checkpoints every [checkpointStride] actions (init's
  /// forward pass only — seeks never add checkpoints, keeping id order = journal order).
  Future<void> _advance(int target, {int? checkpointStride}) async {
    final engine = _engine!;
    const slice = 2000; // yield granularity: input liveness + init progress
    while (_pos < target) {
      // A chapter boundary at the current position: load its base (it IS part of this
      // position's canonical state); init additionally checkpoints the post-load state so
      // backward seeks re-enter the chapter without a base reload.
      final base = _chapterBaseAt[_pos];
      if (base != null) {
        final status = engine.load(bases[base]!);
        if (!status.loaded) {
          throw StateError('chapter base $base failed to load ($status)');
        }
        if (checkpointStride != null) _takeCheckpoint();
      }
      // Batch a run of actions up to the next chapter boundary / checkpoint point / slice.
      var end = (_pos + slice < target) ? _pos + slice : target;
      for (var i = _pos + 1; i < end; i++) {
        if (_chapterBaseAt.containsKey(i)) {
          end = i;
          break;
        }
      }
      if (checkpointStride != null) {
        final nextCp = ((_pos ~/ checkpointStride) + 1) * checkpointStride;
        if (nextCp > _pos && nextCp < end) end = nextCp;
      }
      // A journal recorded what the editor SENT — a parse error in it usually replays to the
      // same rejection. A verb from a NEWER app version is the exception: it drops only its
      // own line (never the batch remainder), so the replay diverges minimally.
      runActionsSkippingBad(engine.run, _actions, _pos, end, onSkip: debugPrint);
      _pos = end;
      if (checkpointStride != null) {
        if (_pos % checkpointStride == 0 || _chapterBaseAt.containsKey(_pos)) {
          _takeCheckpoint();
        }
        _progress.value = (_pos / _actions.length).clamp(0.0, 1.0);
        await Future<void>.delayed(Duration.zero); // yield to input during init
      }
    }
    // Stopping EXACTLY on a chapter boundary: the base load is part of this position's
    // canonical state (checkpoints taken here during init are post-load), so apply it —
    // idempotent if the loop later re-loads when advancing onward.
    final atBoundary = _chapterBaseAt[_pos];
    if (atBoundary != null) {
      final status = engine.load(bases[atBoundary]!);
      if (!status.loaded) {
        throw StateError('chapter base $atBoundary failed to load ($status)');
      }
    }
  }

  void _takeCheckpoint() {
    final id = _engine!.checkpointTake();
    if (id < 0) return; // mid-draft — the next stride point will catch one
    _checkpoints.add((_pos, id));
    // Resync against eviction so the map never references dead ids.
    final live = _engine!.checkpointIds().toSet();
    _checkpoints.removeWhere((c) => !live.contains(c.$2));
  }

  @override
  Future<void> seek(int position) async {
    if (!_ready) return;
    _wantPos = position.clamp(0, _actions.length);
    if (_seeking) return; // the in-flight loop will pick the newest target up
    _seeking = true;
    try {
      while (_wantPos != null) {
        final target = _wantPos!;
        _wantPos = null;
        await _seekTo(target);
      }
    } finally {
      _seeking = false;
    }
  }

  Future<void> _seekTo(int target) async {
    if (target == _pos) return;
    if (target > _pos) {
      // Forward: incremental when the gap is small (the auto-play fast path), else hop
      // to the nearest checkpoint at or before the target first.
      final hop = _nearestCheckpointAtOrBefore(target);
      if (hop != null && hop.$1 > _pos) {
        if (_restore(hop)) _pos = hop.$1;
      }
      await _advance(target);
      return;
    }
    // Backward: restore the nearest checkpoint at or before the target, then run the gap.
    final hop = _nearestCheckpointAtOrBefore(target);
    if (hop != null && _restore(hop)) {
      _pos = hop.$1;
    } else {
      // No usable checkpoint (all evicted below target): replay from zero — the journal's
      // own first actions/base reset the session.
      _pos = 0;
    }
    await _advance(target);
  }

  (int, int)? _nearestCheckpointAtOrBefore(int target) {
    (int, int)? best;
    for (final c in _checkpoints) {
      // >= so of two checkpoints at one position (pre-/post-base-load at a chapter start)
      // the LATER take — the post-load, canonical state — wins.
      if (c.$1 <= target && (best == null || c.$1 >= best.$1)) best = c;
    }
    return best;
  }

  bool _restore((int, int) cp) {
    if (_engine!.checkpointRestore(cp.$2)) return true;
    _checkpoints.remove(cp); // evicted under us — drop and let callers fall back
    return false;
  }

  @override
  (Uint8List, int, int) currentFrame() {
    final engine = _engine!;
    return (engine.compositeFrame(engine.activeFrame), engine.width, engine.height);
  }

  @override
  void dispose() {
    _engine?.checkpointClear();
    _engine?.dispose();
    _engine = null;
    _progress.dispose();
  }
}
