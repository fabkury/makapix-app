import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shared frame clock for synchronized animation playback.
///
/// State is the wall-clock time in ms since the Unix epoch, sampled ONCE per vsync tick
/// — every synced tile derives its frame index from the same sample, so tiles change
/// frames on the same tick and repaints batch. Tiles watch it through a `select` on
/// their computed frame index, so they rebuild only when that index actually changes.
///
/// The ticker runs only while at least one synced widget is registered AND the app is
/// foregrounded. Registration happens in the widgets' initState/dispose: GridView.builder
/// mounts only visible(+cacheExtent) tiles, so mount ≈ visibility — and when AppShell
/// unmounts the Club pillar every tile disposes, so pillar gating comes free. Because
/// frame = f(wall clock), stopping is always safe: a resumed clock is instantly correct,
/// with no catch-up logic.
class SyncFrameClock extends StateNotifier<int> with WidgetsBindingObserver {
  SyncFrameClock() : super(DateTime.now().millisecondsSinceEpoch) {
    WidgetsBinding.instance.addObserver(this);
  }

  Ticker? _ticker;
  int _registrants = 0;
  bool _foreground = true;

  /// A synced widget that wants ticks (call from initState / when playback turns on).
  void register() {
    _registrants++;
    _update();
  }

  /// The matching teardown (call from dispose / when playback turns off).
  void unregister() {
    assert(_registrants > 0, 'unregister() without a matching register()');
    _registrants--;
    _update();
  }

  @visibleForTesting
  int get registrantCount => _registrants;

  @visibleForTesting
  bool get isTicking => _ticker?.isActive ?? false;

  void _update() {
    final shouldRun = _registrants > 0 && _foreground;
    final running = _ticker?.isActive ?? false;
    if (shouldRun && !running) {
      // Fresh sample on start so a just-mounted tile doesn't paint a stale instant.
      state = DateTime.now().millisecondsSinceEpoch;
      (_ticker ??= Ticker(_onTick)).start();
    } else if (!shouldRun && running) {
      _ticker!.stop();
    }
  }

  void _onTick(Duration _) {
    state = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` is just focus loss on desktop — keep playing; stop only when the app
    // is actually not visible. Resync on resume is automatic (frame = f(wall clock)).
    _foreground =
        state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _update();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    super.dispose();
  }
}

/// Kept warm for the app lifetime (NOT autoDispose), like `playerControllerProvider` —
/// the ticker itself stops whenever no synced widget is registered.
final syncFrameClockProvider =
    StateNotifierProvider<SyncFrameClock, int>((ref) => SyncFrameClock());
