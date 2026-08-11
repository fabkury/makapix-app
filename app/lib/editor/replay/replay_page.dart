import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:makapix_club/engine_ffi.dart' show premultiplyRgbaInPlace;

import 'replay_host.dart';

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
    _start();
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

  /// Sweep duration: the whole journal's VISIBLE changes in ~30–60 s (a fiddle-heavy
  /// session earns no extra sweep time for invisible work).
  double get _sweepSeconds => (_visibleCount / 2500).clamp(30, 60).toDouble();

  void _play() {
    if (!host.ready || _playing) return;
    if (host.position >= host.actionCount) {
      _uiIdx = 0; // replay from the start when play is hit at the end
    }
    setState(() => _playing = true);
    final perTick = _visibleCount / (_sweepSeconds * 30);
    _sweep = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_playing) return;
      if (_seekBusy) return; // coalesce: never queue ticks behind a slow seek
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
