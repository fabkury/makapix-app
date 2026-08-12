// Battery-discipline debug counters (docs/battery/RECOMMENDATIONS.md, Phase 0).
//
// A static counter sink incremented from the hot paths (frame production, engine FFI
// fetches, image decodes, HTTP requests) plus a 5-second reporter that emits one
// logcat-greppable line per window:
//
//   [battery] fps=59.8 disp=12 comp=0 dec=12 dsl=140 mask=8 http=2
//
// Everything is compiled out of RELEASE builds (`kReleaseMode` is const, so the guarded
// bodies are eliminated); counters are live in DEBUG and PROFILE builds. Measurement
// sessions use PROFILE builds (AOT, near-release performance) — see tools/battery/README.md.
//
// The increment methods are safe from any isolate (plain static ints, no binding use);
// only [start] touches WidgetsBinding and it runs once, on the root isolate, from main().
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

abstract final class BatteryStats {
  static int _frames = 0; // frames produced (persistent frame callback)
  static int _displays = 0; // engine.display() full-canvas fetches
  static int _composites = 0; // engine.compositeFrame() fetches (playback/replay)
  static int _decodes = 0; // ui.decodeImageFromPixels calls (GPU texture uploads)
  static int _dslRuns = 0; // engine.run() DSL sends
  static int _outlineMasks = 0; // engine.outlineMask() selection fetches
  static int _httpRequests = 0; // Dio requests (both Club clients)

  static void display() {
    if (kReleaseMode) return;
    _displays++;
  }

  static void composite() {
    if (kReleaseMode) return;
    _composites++;
  }

  static void decode() {
    if (kReleaseMode) return;
    _decodes++;
  }

  static void dslRun() {
    if (kReleaseMode) return;
    _dslRuns++;
  }

  static void outlineMask() {
    if (kReleaseMode) return;
    _outlineMasks++;
  }

  static void httpRequest() {
    if (kReleaseMode) return;
    _httpRequests++;
  }

  static bool _started = false;
  static final Stopwatch _window = Stopwatch();

  /// Arm the frame counter and the 5 s reporter. No-op in release builds; call once
  /// from main() after `WidgetsFlutterBinding.ensureInitialized()`.
  ///
  /// The reporter line is emitted every window even when all counts are zero — a steady
  /// heartbeat makes scenario windows easy to average (and its absence in a logcat
  /// capture means the capture itself is broken, not that the app was idle).
  static void start() {
    if (kReleaseMode || _started) return;
    _started = true;
    WidgetsBinding.instance.addPersistentFrameCallback((_) => _frames++);
    _window.start();
    Timer.periodic(const Duration(seconds: 5), (_) => _report());
  }

  static void _report() {
    final secs = _window.elapsedMicroseconds / 1e6;
    _window.reset();
    final fps = secs > 0 ? (_frames / secs).toStringAsFixed(1) : '0.0';
    debugPrint('[battery] fps=$fps disp=$_displays comp=$_composites '
        'dec=$_decodes dsl=$_dslRuns mask=$_outlineMasks http=$_httpRequests');
    _frames = 0;
    _displays = 0;
    _composites = 0;
    _decodes = 0;
    _dslRuns = 0;
    _outlineMasks = 0;
    _httpRequests = 0;
  }
}
