import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makapix_club/engine_ffi.dart' show premultiplyRgbaInPlace;

import 'replay_host.dart';

/// The remembered sweep-duration choice (15/30/60 s), shared across replay sessions.
const String _kSweepSecondsPref = 'replay.sweepSeconds_v1';

/// The selectable sweep durations — the whole journal in this many seconds, mirroring the
/// timelapse export's presets.
const List<int> kSweepSecondsChoices = [15, 30, 60];

/// The Replay viewer (CONTEXT.md "Replay"): a read-only, scrubbable "making-of" of one
/// drawing, backed by its own engine via [ReplayHost] — the live editing session is never
/// touched. The time axis is the action index (dense: every slider pixel is work
/// happening); auto-play sweeps the whole journal in ~30–60 s. No HUD — the drawing is
/// the star; the canvas follows the frame the artist was editing.
class ReplayPage extends StatefulWidget {
  const ReplayPage({super.key, required this.host, required this.title, this.onShareTimelapse});

  final ReplayHost host;
  final String title;

  /// "Share timelapse" (the export flow); the AppBar action is hidden when null.
  final VoidCallback? onShareTimelapse;

  @override
  State<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends State<ReplayPage> {
  final ValueNotifier<ui.Image?> _image = ValueNotifier(null);
  int _imageGen = 0; // staleness stamp: decodes can land out of order (the editor's idiom)
  // The slider thumb in VISIBLE-CHANGE index space (0..visibleCount) — every tick of the
  // sweep and every pixel of the slider is a change you can see; draft fiddling and
  // settings churn never consume playback time. Advanced fractionally by the sweep.
  double _uiIdx = 0;
  bool _playing = false;
  Timer? _sweep;
  bool _seekBusy = false;

  ReplayHost get host => widget.host;

  int get _visibleCount => host.visiblePositions.length;

  /// The journal position a visible-index thumb value maps to (0 = the starting state).
  int _positionOf(int idx) => idx <= 0 ? 0 : host.visiblePositions[idx.clamp(1, _visibleCount) - 1];

  @override
  void initState() {
    super.initState();
    _loadSweepPref();
    _start();
  }

  Future<void> _loadSweepPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_kSweepSecondsPref);
      if (mounted && saved != null && kSweepSecondsChoices.contains(saved)) {
        setState(() => _sweepSeconds = saved);
      }
    } catch (_) {/* prefs unavailable → keep the default */}
  }

  void _setSweepSeconds(int seconds) {
    setState(() => _sweepSeconds = seconds);
    // The sweep rate is recomputed every tick, so a mid-replay switch takes effect on the
    // next tick without restarting; position is kept.
    unawaited(SharedPreferences.getInstance()
        .then((p) => p.setInt(_kSweepSecondsPref, seconds))
        .catchError((_) => true));
  }

  Future<void> _start() async {
    await host.init();
    if (!mounted) return;
    setState(() {});
    if (host.ready) {
      unawaited(_showCurrent());
      _play(); // the demo moment: the making-of starts sweeping on open
    }
  }

  /// The chosen sweep duration: the whole journal's VISIBLE changes in this many seconds
  /// (the timelapse presets, live). Remembered across sessions.
  int _sweepSeconds = 30;

  void _play() {
    if (!host.ready || _playing) return;
    if (host.position >= host.actionCount) {
      _uiIdx = 0; // replay from the start when play is hit at the end
    }
    setState(() => _playing = true);
    _sweep = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_playing) return;
      if (_seekBusy) return; // coalesce: never queue ticks behind a slow seek
      // Recomputed per tick so the duration chips retune a running sweep instantly.
      final perTick = _visibleCount / (_sweepSeconds * 30);
      _uiIdx = (_uiIdx + perTick).clamp(0, _visibleCount.toDouble());
      final idx = _uiIdx.round();
      if (idx >= _visibleCount) {
        _pause(); // stop ON the final state
      }
      unawaited(_seekAndShow(_positionOf(idx)));
      setState(() {});
    });
  }

  void _pause() {
    _sweep?.cancel();
    _sweep = null;
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _seekAndShow(int position) async {
    _seekBusy = true;
    try {
      await host.seek(position);
    } finally {
      _seekBusy = false;
    }
    // Fire-and-forget: the staleness stamp in _showCurrent keeps out-of-order decodes from
    // regressing the canvas, and the sweep must pace on SEEK cost, not decode latency.
    unawaited(_showCurrent());
  }

  Future<void> _showCurrent() async {
    if (!mounted || !host.ready) return;
    final (bytes, w, h) = host.currentFrame();
    if (w == 0 || h == 0) return;
    final gen = ++_imageGen;
    // Same synchronous-consumption contract as the editor's _redraw: premultiply, then
    // decodeImageFromPixels copies the bytes before returning.
    premultiplyRgbaInPlace(bytes);
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.rgba8888, c.complete);
    final img = await c.future;
    if (!mounted || gen != _imageGen) {
      img.dispose();
      return;
    }
    final old = _image.value;
    _image.value = img;
    old?.dispose();
  }

  @override
  void dispose() {
    _sweep?.cancel();
    _image.value?.dispose();
    _image.dispose();
    host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141518),
      appBar: AppBar(
        title: Text('Replay — ${widget.title}', overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.onShareTimelapse != null)
            IconButton(
              tooltip: 'Share timelapse',
              icon: const Icon(Icons.movie_outlined),
              onPressed: host.ready ? widget.onShareTimelapse : null,
            ),
        ],
      ),
      body: host.initError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(host.initError!, textAlign: TextAlign.center),
              ),
            )
          : !host.ready
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Preparing replay…'),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<double>(
                        valueListenable: host.initProgress,
                        builder: (_, v, _) => LinearProgressIndicator(value: v),
                      ),
                    ]),
                  ),
                )
              : Column(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      // Like the editor canvas: stretch to the largest fit, never the true
                      // pixel size. RawImage sizes itself to the image's intrinsic pixels
                      // unless given explicit dimensions, so hand it the whole box and let
                      // BoxFit.contain center the upscale (nearest-neighbor = crisp).
                      child: LayoutBuilder(
                        builder: (_, box) => ValueListenableBuilder<ui.Image?>(
                          valueListenable: _image,
                          builder: (_, img, _) => img == null
                              ? const SizedBox.shrink()
                              : RawImage(
                                  image: img,
                                  width: box.maxWidth,
                                  height: box.maxHeight,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.none,
                                ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Row(children: [
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: _playing ? 'Pause' : 'Play',
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        onPressed: () => _playing ? _pause() : _play(),
                      ),
                      // The sweep-duration chips (the timelapse presets, live): one tap
                      // retunes a running sweep from its current position.
                      ToggleButtons(
                        isSelected: [for (final s in kSweepSecondsChoices) s == _sweepSeconds],
                        onPressed: (i) => _setSweepSeconds(kSweepSecondsChoices[i]),
                        constraints: const BoxConstraints(minHeight: 30, minWidth: 36),
                        borderRadius: BorderRadius.circular(6),
                        textStyle: const TextStyle(fontSize: 11),
                        children: [for (final s in kSweepSecondsChoices) Text('${s}s')],
                      ),
                      Expanded(
                        child: Slider(
                          value: _uiIdx.clamp(0, _visibleCount.toDouble()),
                          max: _visibleCount.toDouble(),
                          onChanged: (v) {
                            _pause(); // dragging takes over from the sweep
                            _uiIdx = v;
                            unawaited(_seekAndShow(_positionOf(v.round())));
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                    ]),
                  ),
                ]),
    );
  }
}
