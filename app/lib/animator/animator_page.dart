// Makapix Animator — the scene/keyframe animation pillar. Stage-first, smartphone-first
// (design docs/animator/03): the canvas IS the editor (auto-keyed drag/pinch/twist on the
// selected Actor), the one timeline lives at the bottom with three zoom levels
// (Strip / Tracks / Focus), and the Rust SceneSession owns the document — this shell captures
// input, sends DSL, and presents composited frames. One of the app's co-equal pillars
// (lib/shell/app_shell.dart); reachable without signing in.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makapix_club/club/state/edit_bridge.dart';
import 'package:makapix_club/editor/dialogs/color_picker_dialog.dart';
import 'package:makapix_club/editor/persistence/autosave_controller.dart';
import 'package:makapix_club/editor/persistence/drawing_store.dart';
import 'package:makapix_club/editor/widgets/painters.dart' show CanvasPainter;
import 'package:makapix_club/engine_ffi.dart' show Engine, premultiplyRgbaInPlace;
import 'package:makapix_club/scene_ffi.dart';
import 'package:makapix_club/share/image_share.dart';
import 'package:makapix_club/ui/chrome_controls.dart';
import 'package:makapix_club/ui/chrome_sheets.dart';
import 'package:makapix_club/ui/layout.dart';

import 'dialogs/new_scene_dialog.dart';
import 'gallery/scene_gallery_page.dart';
import 'import/import_prop_dialog.dart';
import 'model/pin_math.dart';
import 'model/presets.dart';
import 'model/scene_rules.dart';
import 'model/scene_state.dart';
import 'model/snapping.dart';
import 'model/timeline_layout.dart';
import 'persistence/scene_meta.dart';
import 'persistence/scene_store.dart';
import 'playback/scene_frame_cache.dart';
import 'widgets/easing_chip.dart';
import 'widgets/stage_painters.dart';
import 'widgets/timeline_painters.dart';

part 'animator_page.engine.dart';
part 'animator_page.stage.dart';
part 'animator_page.timeline.dart';
part 'animator_page.playback.dart';
part 'animator_page.sheets.dart';
part 'animator_page.fileio.dart';
part 'animator_page.persistence.dart';

const double _kMinZoom = 0.25, _kMaxZoom = 32.0;
const _kCurrentScene = 'animator.currentSceneId'; // last-open scene (silent restore)
const _kTimelineZoomPref = 'animator.timelineZoom_v1';
const _kExportFormatPref = 'animator.exportFormat_v1';
const _kCycleRevealPref = 'animator.cycleRevealShown';

enum TimelineZoom { strip, tracks, focus }

/// What a one-finger Stage drag does to the selected Actor (the pill's Move | Rotate
/// toggle; auto-resets to move on selection change — 06-gesture-safety §4.3).
enum _StageMode { move, rotate }

class AnimatorPage extends ConsumerStatefulWidget {
  const AnimatorPage({super.key});
  @override
  ConsumerState<AnimatorPage> createState() => _AnimatorPageState();
}

class _AnimatorPageState extends ConsumerState<AnimatorPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  SceneEngine? _engine;
  bool _engineFailed = false;
  bool get _engineReady => _engine != null;
  SceneEngine get engine => _engine!;

  // ---- Local persistence: the current library scene + its autosave.
  SceneStore? _store;
  SharedPreferences? _prefs;
  AutosaveController<SceneMeta>? _autosave;
  String? _sceneId;
  String _sceneTitle = 'Untitled';
  DateTime _sceneCreatedAt = DateTime.now();
  DateTime? _lastAutosaveWarn;

  // ---- The engine-owned document, as last parsed from state_json.
  SceneState _state = const SceneState();

  // ---- Stage presentation. The composited frame rides a ValueNotifier so scrub/playback
  // repaint just the canvas; overlays repaint via _overlayVN (the editor's F-9 discipline).
  final ValueNotifier<ui.Image?> _frameVN = ValueNotifier<ui.Image?>(null);
  final ValueNotifier<int> _overlayVN = ValueNotifier<int>(0);
  int _shownFrame = 0; // which scene frame _frameVN holds

  // ---- Hint strip: live gesture values / brief confirmations over the safe-area pad.
  // Null → the strip shows the computed idle hint. Same no-setState discipline as _frameVN.
  final ValueNotifier<String?> _hintVN = ValueNotifier<String?>(null);
  Timer? _hintFlashTimer;

  // View transform: zoom is relative to fit (1.0 = fit), pan in screen px.
  double _zoom = 1.0;
  Offset _pan = Offset.zero;

  // ---- Stage gestures (strict select-then-act: taps select on pointer-up, a one-finger
  // drag acts on the CURRENT selection from anywhere, two fingers are always the view).
  final Map<int, Offset> _touchPos = {};
  int? _dragPointer;
  bool _pinching = false;
  int _dragKind = 0; // 0 none · 1 move-actor · 2 pivot · 3 rotate (orbit)
  double _pinchStartDist = 0, _pinchStartZoom = 1;
  Offset _pinchStartMid = Offset.zero, _pinchStartPan = Offset.zero;
  int _dragStartX = 0, _dragStartY = 0;
  Offset _dragStartCanvas = Offset.zero;
  _StageMode _stageMode = _StageMode.move;
  int? _modeSelId; // the selection _stageMode was last reset for
  int _rotStartMdeg = 0; // rotate-orbit drag state
  double _rotAccum = 0, _rotPrevBearing = 0;
  bool _gestureOpen = false;
  bool _lastSnapEngaged = false;
  List<SnapGuide> _snapGuides = const [];

  // ---- Timeline.
  TimelineZoom _timelineZoom = TimelineZoom.strip;
  double _pxPerFrame = 8;
  double _timeScroll = 0;
  int? _focusActor;
  (int actor, String? prop, int keyFrame)? _selTween;
  // Key drag (Tracks: all props at a frame; Focus: one prop).
  (int actor, String? prop, int from)? _keyDrag;
  int? _keyDragTo;
  int? _loopDragEdge; // 0 = a, 1 = b
  bool _timelinePinching = false;
  double _tlPinchStartDist = 0, _tlPinchStartPpf = 8;
  double _tlPinchFocusFrame = 0; // continuous frame under the fingers' midpoint

  // ---- Playback (the Club clock model: Ticker + frame cache, no FFI in the hot loop).
  bool _playing = false;
  Ticker? _ticker;
  int _playStartFrame = 0;
  Duration _playStartElapsed = Duration.zero;
  Duration _lastElapsed = Duration.zero;
  final SceneFrameCache _frameCache = SceneFrameCache();
  bool _warmInFlight = false;
  int _warmEpoch = -1;

  // ---- Memory-budget UI (the editor's banner/snackbar narration).
  int _memRefusalsSeen = -1;
  bool _memBannerShown = false;

  double get _chromeScale => chromeScale(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _engine = SceneEngine(64, 64, millifps: 12500);
    } catch (_) {
      _engineFailed = true;
    }
    if (_engineReady) {
      _initPersistence();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    // Autosave the outgoing scene before freeing the engine: serialize runs SYNCHRONOUSLY
    // inside flushNow (the editor's exact ordering), then the async write proceeds safely.
    if (_engineReady) _autosave?.flushNow();
    _autosave?.stop();
    _hintFlashTimer?.cancel();
    _hintVN.dispose();
    _frameCache.dispose();
    _frameVN.value?.dispose();
    if (_engineReady) engine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_engineReady) _autosave?.flushNow();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---- Hint-strip channel (consumed by _buildHintStrip in the timeline part).

  /// Show a live value while a gesture is in flight.
  void _hintLive(String s) {
    _hintFlashTimer?.cancel();
    _hintFlashTimer = null;
    _hintVN.value = s;
  }

  /// Back to the idle hint.
  void _hintEnd() {
    _hintFlashTimer?.cancel();
    _hintFlashTimer = null;
    _hintVN.value = null;
  }

  /// A brief confirmation that fades back to the idle hint.
  void _hintFlash(String s) {
    _hintFlashTimer?.cancel();
    _hintVN.value = s;
    _hintFlashTimer = Timer(const Duration(seconds: 2), () {
      _hintFlashTimer = null;
      _hintVN.value = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Requests can arrive while this pillar is already mounted.
    ref.listen<AnimatorRequest?>(pendingAnimatorProvider, (prev, next) {
      if (next != null) _consumeAnimatorRequest(next);
    });

    if (_engineFailed) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text('The Makapix engine could not be loaded.'),
              const SizedBox(height: 8),
              const Text('Build it with: cargo build -p makapix-ffi --release',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.read(openClubProvider.notifier).state++,
                child: const Text('Back to the Club'),
              ),
            ]),
          ),
        ),
      );
    }

    final landscape = editorUsesLandscape(MediaQuery.sizeOf(context));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: landscape ? _buildLandscapeBody() : _buildPortraitBody(),
      ),
    );
  }

  // Gesture-safe stack (docs/animator/06-gesture-safety.md §4.1): drags in the middle,
  // taps at the extremes — the timeline sits above the tap-only transport dock, and the
  // passive hint strip absorbs the bottom gesture zone.
  Widget _buildPortraitBody() {
    return Column(children: [
      _buildTopBand(),
      Expanded(child: _buildStageArea()),
      const Divider(height: 1),
      _buildTimelineBand(),
      _buildTransportRow(),
      _buildHintStrip(),
    ]);
  }

  Widget _buildLandscapeBody() {
    // The timing posture: a slim side band frees vertical space so the timeline can breathe.
    return Row(children: [
      _buildSideBand(),
      const VerticalDivider(width: 1),
      Expanded(
        child: Column(children: [
          Expanded(child: _buildStageArea()),
          const Divider(height: 1),
          _buildTimelineBand(landscape: true),
          _buildTransportRow(),
          _buildHintStrip(compact: true),
        ]),
      ),
    ]);
  }
}
