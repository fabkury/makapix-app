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

  final Duration interval;

  AutosaveController({
    required this.id,
    required this.store,
    required this.serialize,
    required this.buildMeta,
    this.onError,
    this.interval = const Duration(seconds: 5),
  });

  Timer? _timer;
  bool _activity = false; // coarse "something happened" gate for the cheap serialize
  int _lastHash = 0;
  bool _hasSaved = false;
  ({Uint8List bytes, DrawingMeta meta})? _pending; // latest write waiting (latest-wins)
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
    final bytes = serialize();
    if (bytes.isEmpty) return;
    final h = _fnv1a(bytes);
    if (_hasSaved && h == _lastHash) return; // nothing changed since last save
    _lastHash = h;
    _hasSaved = true;
    await _enqueue(bytes, buildMeta());
  }

  /// Force the latest state to disk immediately (background / leave / switch / create). Serializes
  /// AND builds metadata synchronously (before any `await`), so it is safe to call right before
  /// `engine.dispose()` without awaiting. Returns once the write completes (callers that can await
  /// — e.g. switching drawings — should).
  Future<void> flushNow() {
    final bytes = serialize(); // sync: captured before the first await / engine free
    if (bytes.isEmpty) return Future<void>.value();
    final meta = buildMeta(); // sync: also captured before any engine free
    _lastHash = _fnv1a(bytes);
    _hasSaved = true;
    return _enqueue(bytes, meta);
  }

  Future<void> _enqueue(Uint8List bytes, DrawingMeta meta) {
    _pending = (bytes: bytes, meta: meta);
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

  /// Stop the timer and let any pending write finish. Idempotent.
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
  // that the next real change would catch anyway.
  static int _fnv1a(Uint8List b) {
    var h = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (var i = 0; i < b.length; i++) {
      h = (h ^ b[i]) * prime;
    }
    return h & 0x7FFFFFFFFFFFFFFF;
  }
}
