import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data' show Uint32List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makapix_club/editor/widgets/painters.dart' show CanvasPainter;
import 'package:makapix_club/engine_ffi.dart' show premultiplyRgbaInPlace;

import 'journal_format.dart' show kJournalEpoch;
import 'replay_host.dart';
import 'timelapse_plan.dart' show kProgressFrameUs, paceTimeline, progressDurationUs, tickIndexAt;

/// The remembered sweep-duration choice (15/30/60 s), shared across replay sessions.
const String _kSweepSecondsPref = 'replay.sweepSeconds_v1';

/// The selectable sweep durations — the whole journal in this many seconds, mirroring the
/// timelapse export's presets.
const List<int> kSweepSecondsChoices = [15, 30, 60];

/// The Replay viewer (CONTEXT.md "Replay"): a read-only, scrubbable "making-of" of one
/// drawing, backed by its own engine via [ReplayHost] — the live editing session is never
/// touched. The time axis is VIDEO time: the Journal's timeline paced by working time into
/// the chosen 15/30/60 s (ADR 0029, `timelapse_plan.dart`), so the sweep and the slider match
/// the exported Timelapse frame for frame — an apply holds, a scribble compresses, a pause
/// costs one short beat. No HUD — the drawing is the star; the canvas follows the frame the
/// artist was editing.
class ReplayPage extends StatefulWidget {
  const ReplayPage({super.key, required this.host, required this.title, this.onShareTimelapse});

  final ReplayHost host;
  final String title;

  /// "Share timelapse" (the export flow) — a labeled AppBar button (the label is the tap
  /// target: an icon alone hid the export from lay users, 2026-09-18); hidden when null.
  final VoidCallback? onShareTimelapse;

  /// The share button's label. Mobile hands the Timelapse to the OS share sheet ("Share");
  /// desktop writes a file ("Export") — the same split as the export dialog's confirm button.
  static String shareLabel(TargetPlatform platform) => switch (platform) {
        TargetPlatform.android || TargetPlatform.iOS => 'Share timelapse',
        _ => 'Export timelapse',
      };

  @override
  State<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends State<ReplayPage> with WidgetsBindingObserver {
  final ValueNotifier<ui.Image?> _image = ValueNotifier(null);
  int _imageGen = 0; // staleness stamp: decodes can land out of order (the editor's idiom)
  // The slider thumb in VIDEO time (µs, 0.._totalUs): the paced axis of the timeline, the
  // same one the Timelapse export samples. Advanced one frame per sweep tick.
  double _uiUs = 0;
  // The paced axis for the current preset: cumulative video µs at the end of each tick.
  Uint32List _cum = Uint32List(0);
  bool _playing = false;
  Timer? _sweep;
  bool _seekBusy = false;

  ReplayHost get host => widget.host;

  /// The progress portion's length for the chosen preset, µs.
  int get _totalUs => progressDurationUs(_sweepSeconds);

  /// The journal position on screen at video instant [us] (0 = the starting state).
  int _positionAt(double us) {
    final tl = host.timeline;
    if (tl.isEmpty) return 0;
    final k = tickIndexAt(_cum, us.round());
    return k < 0 ? 0 : tl.positions[k];
  }

  void _repace() => _cum = paceTimeline(host.timeline, _sweepSeconds);

  /// Adopt a preset. Once the host is ready this re-paces the axis and keeps the SAME tick on
  /// screen (re-entering the new axis at the end of that tick), so a mid-sweep switch neither
  /// jumps nor restarts.
  void _adoptSweepSeconds(int seconds) {
    if (!host.ready) {
      _sweepSeconds = seconds;
      return;
    }
    final k = tickIndexAt(_cum, _uiUs.round());
    _sweepSeconds = seconds;
    _repace();
    _uiUs = k < 0 ? 0 : _cum[k].toDouble();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // pause the sweep on background [battery F7]
    _loadSweepPref();
    _start();
  }

  // The 30 Hz sweep is a Timer (journal replay through a second Engine + composite + decode
  // per tick), so unlike a muted Ticker it keeps burning while the app is backgrounded —
  // pause it. `inactive` stays running (desktop focus loss, the house style —
  // notifications_sse.dart). The user resumes by pressing play. [battery F7]
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_playing &&
        (state == AppLifecycleState.paused || state == AppLifecycleState.hidden)) {
      _pause();
    }
  }

  Future<void> _loadSweepPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_kSweepSecondsPref);
      if (mounted && saved != null && kSweepSecondsChoices.contains(saved)) {
        setState(() => _adoptSweepSeconds(saved));
      }
    } catch (_) {/* prefs unavailable → keep the default */}
  }

  void _setSweepSeconds(int seconds) {
    // A mid-replay switch re-paces the axis in place (O(events)); the tick on screen is kept
    // and the sweep keeps running at one video frame per tick over the new axis.
    setState(() => _adoptSweepSeconds(seconds));
    unawaited(SharedPreferences.getInstance()
        .then((p) => p.setInt(_kSweepSecondsPref, seconds))
        .catchError((_) => true));
  }

  Future<void> _start() async {
    await host.init();
    if (!mounted) return;
    if (host.ready) _repace();
    setState(() {});
    if (host.ready) {
      unawaited(_showCurrent());
      _play(); // the demo moment: the making-of starts sweeping on open
    }
  }

  /// The chosen sweep duration: the whole journal's timeline paced into this many seconds
  /// (the timelapse presets, live). Remembered across sessions.
  int _sweepSeconds = 30;

  void _play() {
    if (!host.ready || _playing) return;
    if (host.position >= host.actionCount) {
      _uiUs = 0; // replay from the start when play is hit at the end
    }
    setState(() => _playing = true);
    _sweep = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_playing) return;
      if (_seekBusy) return; // coalesce: never queue ticks behind a slow seek
      // One video frame per tick: the duration chips change the AXIS (_cum), never the rate.
      _uiUs = (_uiUs + kProgressFrameUs).clamp(0, _totalUs.toDouble());
      if (_uiUs >= _totalUs) {
        _pause(); // stop ON the final state
      }
      unawaited(_seekAndShow(_positionAt(_uiUs)));
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
    WidgetsBinding.instance.removeObserver(this);
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
        title: Row(children: [
          Flexible(child: Text('Replay — ${widget.title}', overflow: TextOverflow.ellipsis)),
          // Pre-epoch journals replay under today's engine semantics, which may differ from the
          // session that recorded them (ADR 0015). Quiet chip, tap for the why.
          if (host.journalEpoch < kJournalEpoch) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Recorded before an editor update — playback may differ from the '
                  'original session.',
              triggerMode: TooltipTriggerMode.tap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Older recording', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ]),
        actions: [
          // Labeled, not icon-only: the export has to read as an action at a glance — a
          // film-clapper glyph with a long-press tooltip did not (2026-09-18). The platform
          // share icon says "this leaves the app"; the label names what leaves.
          if (widget.onShareTimelapse != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                icon: Icon(Icons.adaptive.share, size: 18),
                label: Text(ReplayPage.shareLabel(defaultTargetPlatform)),
                onPressed: host.ready ? widget.onShareTimelapse : null,
              ),
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
                      // pixel size — a hand-rolled BoxFit.contain feeding the editor's
                      // CanvasPainter, which draws the transparency checker under the
                      // artwork (a RawImage would let transparent pixels fall through to
                      // the page background) and the image NN-scaled on top.
                      child: LayoutBuilder(
                        builder: (_, box) => ValueListenableBuilder<ui.Image?>(
                          valueListenable: _image,
                          builder: (_, img, _) {
                            if (img == null) return const SizedBox.shrink();
                            final scale = math.min(
                                box.maxWidth / img.width, box.maxHeight / img.height);
                            final off = Offset(
                                (box.maxWidth - img.width * scale) / 2,
                                (box.maxHeight - img.height * scale) / 2);
                            return CustomPaint(
                              size: Size(box.maxWidth, box.maxHeight),
                              painter: CanvasPainter(img, scale, off),
                            );
                          },
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
                          value: _uiUs.clamp(0, _totalUs.toDouble()),
                          max: _totalUs.toDouble(),
                          onChanged: (v) {
                            _pause(); // dragging takes over from the sweep
                            _uiUs = v;
                            unawaited(_seekAndShow(_positionAt(v)));
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
