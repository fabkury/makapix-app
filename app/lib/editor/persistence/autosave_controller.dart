import 'dart:async';

import 'package:flutter/foundation.dart';

import 'drawing_meta.dart';
import 'drawing_store.dart';

/// Drives autosave for ONE library drawing. Owns the periodic timer, change-detection, a coalescing
/// single-flight writer, and the immediate "flush now" used on app-background / leaving the editor.
///
/// Engine-agnostic: it pulls bytes through the injected [serialize] callback and metadata through
/// [buildMeta]. **Both are invoked synchronously** at request time (before any `await`), so they are
/// safe to call right up to `engine.dispose()` and the async write never touches a freed engine.
/// This also keeps the controller unit-testable with fakes.
///
/// Cadence: every [interval] (default 5 s, comfortably under the 10 s loss budget), if there has
/// been activity, it serializes and writes the doc **only if the bytes actually changed** (FNV-1a
/// hash). Thumbnails are not handled here (the gallery generates/caches them) to keep all engine
/// access on the synchronous path.
class AutosaveController {
  final String id;
  final DrawingStore store;

  /// Current document as `.mkpx` bytes (engine.save). Returns empty when not serializable; the
  /// controller then writes nothing (never clobbers a good file).
  final Uint8List Function() serialize;

  /// Current metadata for this drawing (the caller stamps `updatedAt`). Invoked synchronously.
  final DrawingMeta Function() buildMeta;

  /// Called (non-fatally) when a write fails — e.g. to show a throttled "couldn't autosave" toast.
  final void Function(Object error)? onError;

  /// Invoked from the drain immediately BEFORE each physical `writeDoc`, with the FNV-1a-64
  /// of the exact bytes about to be written. The Journal's write-ahead hook: the recorder
  /// flushes its buffer and appends a marker for these bytes, so the journal is durably on
  /// disk before the document that supersedes it. Failures are swallowed — the document is
  /// authoritative; a missed marker merely re-anchors the journal on the next attach.
  final Future<void> Function(int fnv64)? preWrite;

  /// True while whatever [serialize] reads (the engine) still holds the document this controller
  /// was started for. Checked synchronously before every serialize: once it turns false, every
  /// write is refused, so another drawing's content can never land in [id]'s folder (ADR 0014,
  /// amended 2026-09-22). Null = always current.
  final bool Function()? isCurrent;

  /// Called (non-fatally) when a write is refused because [isCurrent] turned false — a bug in the
  /// caller's switch sequencing, never a user-facing condition.
  final void Function()? onStale;

  final Duration interval;

  AutosaveController({
    required this.id,
    required this.store,
    required this.serialize,
    required this.buildMeta,
    this.onError,
    this.preWrite,
    this.isCurrent,
    this.onStale,
    this.interval = const Duration(seconds: 5),
  });

  Timer? _timer;
  bool _activity = false; // coarse "something happened" gate for the cheap serialize
  int _lastHash = 0;
  bool _hasSaved = false;
  ({Uint8List bytes, DrawingMeta meta, int fnv})? _pending; // latest write waiting (latest-wins)
  bool _draining = false;
  bool _stopped = false;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => _runCycle());
  }

  /// Mark that the user did something. Cheap; only gates the periodic serialize. The hash is the
  /// real arbiter of whether a write happens, so over-marking (e.g. from a query) is harmless.
  void markActivity() => _activity = true;

  Future<void> _runCycle() async {
    if (_stopped || !_activity) return;
    _activity = false;
    if (_refuseStale()) return;
    final bytes = serialize();
    if (bytes.isEmpty) return;
    final h = fnv1a64(bytes);
    if (_hasSaved && h == _lastHash) return; // nothing changed since last save
    _lastHash = h;
    _hasSaved = true;
    await _enqueue(bytes, buildMeta(), h);
  }

  /// Force the latest state to disk immediately (background / leave / switch / create). Serializes
  /// AND builds metadata synchronously (before any `await`), so it is safe to call right before
  /// `engine.dispose()` without awaiting. Returns once the write completes (callers that can await
  /// — e.g. switching drawings — should). Byte-identical state skips the write — the same hash
  /// short-circuit as the periodic cycle, so lifecycle-transition bursts don't rewrite (and
  /// re-fsync) an unchanged document. [battery F11]
  /// A no-op once [stop] has been called or once [isCurrent] turns false.
  Future<void> flushNow() {
    if (_stopped || _refuseStale()) return Future<void>.value();
    final bytes = serialize(); // sync: captured before the first await / engine free
    if (bytes.isEmpty) return Future<void>.value();
    final h = fnv1a64(bytes);
    if (_hasSaved && h == _lastHash) return Future<void>.value(); // already on disk
    final meta = buildMeta(); // sync: also captured before any engine free
    _lastHash = h;
    _hasSaved = true;
    return _enqueue(bytes, meta, _lastHash);
  }

  bool _refuseStale() {
    if (isCurrent == null || isCurrent!()) return false;
    onStale?.call();
    return true;
  }

  /// Stop the periodic timer without tearing the controller down — the app went to
  /// background and the pre-pause [flushNow] already captured the state, so ~12 isolate
  /// wakeups/min would buy nothing. [resume] re-arms it. [battery F12]
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  /// Restart the periodic timer after [pause]. No-op once [stop] has been called.
  void resume() {
    if (_stopped) return;
    start();
  }

  @visibleForTesting
  bool get timerActive => _timer != null;

  Future<void> _enqueue(Uint8List bytes, DrawingMeta meta, int fnv) {
    _pending = (bytes: bytes, meta: meta, fnv: fnv);
    return _drain();
  }

  // Single-flight, latest-wins: only one writer runs; bursts coalesce to the newest bytes. No engine
  // access here — bytes and meta were captured synchronously by the caller.
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending != null) {
        final job = _pending!;
        _pending = null;
        if (preWrite != null) {
          try {
            await preWrite!(job.fnv); // journal write-ahead; never blocks the doc write
          } catch (_) {}
        }
        try {
          await store.writeDoc(id, job.bytes);
          await store.writeMeta(job.meta);
        } catch (e) {
          onError?.call(e);
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Stop the timer and let any pending write finish; later [flushNow] calls write nothing.
  /// Idempotent.
  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    await _drain();
  }

  @visibleForTesting
  Future<void> debugCycle() => _runCycle();

  // 64-bit FNV-1a over the bytes (native Dart ints wrap at 64-bit). Change-detection only — not a
  // cryptographic hash; collisions are irrelevant beyond an astronomically-unlikely missed save
  // that the next real change would catch anyway. Public: the Journal hashes loaded doc bytes
  // with the IDENTICAL function (mask included) to match its crash-sync markers.
  static int fnv1a64(Uint8List b) {
    var h = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (var i = 0; i < b.length; i++) {
      h = (h ^ b[i]) * prime;
    }
    return h & 0x7FFFFFFFFFFFFFFF;
  }
}
