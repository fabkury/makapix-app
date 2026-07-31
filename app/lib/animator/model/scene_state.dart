// Parsed mkps_state_json — the UI's read model of the engine-owned Scene document. Pure Dart
// and tolerant (missing fields fall back) so it stays unit-testable without the native binary
// and survives seam evolution. The engine EVALUATES poses/bounds at the playhead; Dart never
// re-implements tween math.
library;

import 'dart:convert';

class PoseState {
  final int x, y, rotMdeg, scaleMilli, opacity;
  final bool flipH, flipV;
  final int pivotXMilli, pivotYMilli;
  final int pose;
  const PoseState({
    this.x = 0,
    this.y = 0,
    this.rotMdeg = 0,
    this.scaleMilli = 1000,
    this.opacity = 255,
    this.flipH = false,
    this.flipV = false,
    this.pivotXMilli = 0,
    this.pivotYMilli = 0,
    this.pose = 0,
  });

  static PoseState fromJson(Map<String, dynamic>? m) {
    if (m == null) return const PoseState();
    return PoseState(
      x: (m['x'] as num?)?.toInt() ?? 0,
      y: (m['y'] as num?)?.toInt() ?? 0,
      rotMdeg: (m['rot_mdeg'] as num?)?.toInt() ?? 0,
      scaleMilli: (m['scale_milli'] as num?)?.toInt() ?? 1000,
      opacity: (m['opacity'] as num?)?.toInt() ?? 255,
      flipH: m['flip_h'] == true,
      flipV: m['flip_v'] == true,
      pivotXMilli: (m['pivot_x_milli'] as num?)?.toInt() ?? 0,
      pivotYMilli: (m['pivot_y_milli'] as num?)?.toInt() ?? 0,
      pose: (m['pose'] as num?)?.toInt() ?? 0,
    );
  }
}

class KeyState {
  final int frame;
  final int v;
  final String tween;
  const KeyState(this.frame, this.v, this.tween);
}

class TrackState {
  final int base;
  final List<KeyState> keys;
  const TrackState(this.base, this.keys);
  bool get hasKeys => keys.isNotEmpty;
  bool hasKeyAt(int frame) => keys.any((k) => k.frame == frame);

  static TrackState fromJson(Map<String, dynamic>? m) {
    if (m == null) return const TrackState(0, []);
    final keys = <KeyState>[
      for (final k in (m['keys'] as List? ?? const []))
        KeyState(
          ((k as Map)['f'] as num?)?.toInt() ?? 0,
          (k['v'] as num?)?.toInt() ?? 0,
          k['tw'] as String? ?? 'linear',
        ),
    ];
    return TrackState((m['base'] as num?)?.toInt() ?? 0, keys);
  }
}

/// The ten track names, in the engine's canonical order (state_json map order).
const List<String> kTrackNames = [
  'x', 'y', 'rot', 'scale', 'flip_h', 'flip_v', 'opacity', 'pivot_x', 'pivot_y', 'pose',
];

/// The property rows the Focus zoom level shows (transform + opacity; flips/pivot/pose stay
/// sheet-managed in v0.1).
const List<String> kFocusTracks = ['x', 'y', 'rot', 'scale', 'opacity'];

class ActorState {
  final int id;
  final String name;
  final int prop;
  final int z;
  final String mode; // 'playing' | 'posing'
  final int? pinTo;
  final bool visible;
  final PoseState pose;
  final List<int> bounds; // [x, y, w, h] evaluated AABB at the playhead (scene px)
  final int srcFrame;
  final Map<String, TrackState> tracks;
  const ActorState({
    required this.id,
    required this.name,
    required this.prop,
    required this.z,
    required this.mode,
    required this.pinTo,
    required this.visible,
    required this.pose,
    required this.bounds,
    required this.srcFrame,
    required this.tracks,
  });

  bool get playing => mode == 'playing';

  /// Every frame that carries at least one Key on any track (the Tracks-lane tick set).
  Set<int> keyFrames() =>
      {for (final t in tracks.values) ...t.keys.map((k) => k.frame)};

  /// Whether any track has a key exactly at [frame].
  bool hasKeyAt(int frame) => tracks.values.any((t) => t.hasKeyAt(frame));

  static ActorState fromJson(Map<String, dynamic> m) {
    final tracks = <String, TrackState>{};
    final tj = m['tracks'] as Map<String, dynamic>? ?? const {};
    for (final name in kTrackNames) {
      tracks[name] = TrackState.fromJson(tj[name] as Map<String, dynamic>?);
    }
    return ActorState(
      id: (m['id'] as num?)?.toInt() ?? 0,
      name: m['name'] as String? ?? '',
      prop: (m['prop'] as num?)?.toInt() ?? 0,
      z: (m['z'] as num?)?.toInt() ?? 0,
      mode: m['mode'] as String? ?? 'playing',
      pinTo: (m['pin_to'] as num?)?.toInt(),
      visible: m['visible'] != false,
      pose: PoseState.fromJson(m['pose'] as Map<String, dynamic>?),
      bounds: [
        for (final b in (m['bounds'] as List? ?? const [0, 0, 1, 1]))
          (b as num).toInt(),
      ],
      srcFrame: (m['src_frame'] as num?)?.toInt() ?? 0,
      tracks: tracks,
    );
  }
}

class CastEntryState {
  final int id;
  final String name;
  final int w, h, frames;

  /// Raw per-prop-frame step list (scene frames each prop frame holds for).
  final List<int> cycle;
  final int cycleLen;
  final String style; // 'nearest' | 'cleanedge'
  final bool hasSemiAlpha;
  final int artEpoch;
  const CastEntryState({
    required this.id,
    required this.name,
    required this.w,
    required this.h,
    required this.frames,
    this.cycle = const [],
    required this.cycleLen,
    required this.style,
    required this.hasSemiAlpha,
    required this.artEpoch,
  });

  /// The uniform step when every entry agrees; null for mixed/empty maps.
  int? get uniformStep {
    if (cycle.isEmpty) return null;
    final s = cycle.first;
    return cycle.every((e) => e == s) ? s : null;
  }

  static CastEntryState fromJson(Map<String, dynamic> m) => CastEntryState(
        id: (m['id'] as num?)?.toInt() ?? 0,
        name: m['name'] as String? ?? '',
        w: (m['w'] as num?)?.toInt() ?? 1,
        h: (m['h'] as num?)?.toInt() ?? 1,
        frames: (m['frames'] as num?)?.toInt() ?? 1,
        cycle: [
          for (final v in (m['cycle'] as List?) ?? const [])
            if (v is num) v.toInt(),
        ],
        cycleLen: (m['cycle_len'] as num?)?.toInt() ?? 1,
        style: m['style'] as String? ?? 'nearest',
        hasSemiAlpha: m['has_semi_alpha'] == true,
        artEpoch: (m['art_epoch'] as num?)?.toInt() ?? 0,
      );
}

class SceneState {
  final int w, h;
  final int millifps;
  final int frameCs;
  final int frameCount;
  final String background;
  final int playhead;
  final int loopA, loopB;
  final bool playing;
  final bool autoKey;
  final int? selectedActor;
  final bool canUndo, canRedo;
  final int cacheEpoch;
  final bool usesAlpha;
  final List<CastEntryState> cast;
  final List<ActorState> actors;
  final int memBudgetedBytes, memSoftBudget, memHardBudget;
  final bool memSoftExceeded;
  final int memRefusals;
  final String? memLastRefusal;

  const SceneState({
    this.w = 64,
    this.h = 64,
    this.millifps = 12500,
    this.frameCs = 8,
    this.frameCount = 25,
    this.background = '#00000000',
    this.playhead = 0,
    this.loopA = 0,
    this.loopB = 24,
    this.playing = false,
    this.autoKey = true,
    this.selectedActor,
    this.canUndo = false,
    this.canRedo = false,
    this.cacheEpoch = 0,
    this.usesAlpha = false,
    this.cast = const [],
    this.actors = const [],
    this.memBudgetedBytes = 0,
    this.memSoftBudget = 0,
    this.memHardBudget = 0,
    this.memSoftExceeded = false,
    this.memRefusals = 0,
    this.memLastRefusal,
  });

  ActorState? actor(int? id) {
    if (id == null) return null;
    for (final a in actors) {
      if (a.id == id) return a;
    }
    return null;
  }

  CastEntryState? prop(int id) {
    for (final p in cast) {
      if (p.id == id) return p;
    }
    return null;
  }

  ActorState? get selected => actor(selectedActor);

  /// Merged key-frame set across every actor (the Strip's aggregated ticks).
  Set<int> allKeyFrames() => {for (final a in actors) ...a.keyFrames()};

  static SceneState parse(String json) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return const SceneState();
    }
    final loop = (m['loop'] as List?) ?? const [0, 0];
    return SceneState(
      w: (m['w'] as num?)?.toInt() ?? 64,
      h: (m['h'] as num?)?.toInt() ?? 64,
      millifps: (m['millifps'] as num?)?.toInt() ?? 12500,
      frameCs: (m['frame_cs'] as num?)?.toInt() ?? 8,
      frameCount: (m['frame_count'] as num?)?.toInt() ?? 1,
      background: m['background'] as String? ?? '#00000000',
      playhead: (m['playhead'] as num?)?.toInt() ?? 0,
      loopA: (loop.isNotEmpty ? (loop[0] as num).toInt() : 0),
      loopB: (loop.length > 1 ? (loop[1] as num).toInt() : 0),
      playing: m['playing'] == true,
      autoKey: m['auto_key'] != false,
      selectedActor: (m['selected_actor'] as num?)?.toInt(),
      canUndo: m['can_undo'] == true,
      canRedo: m['can_redo'] == true,
      cacheEpoch: (m['cache_epoch'] as num?)?.toInt() ?? 0,
      usesAlpha: m['uses_alpha'] == true,
      cast: [
        for (final p in (m['cast'] as List? ?? const []))
          CastEntryState.fromJson(p as Map<String, dynamic>),
      ],
      actors: [
        for (final a in (m['actors'] as List? ?? const []))
          ActorState.fromJson(a as Map<String, dynamic>),
      ],
      memBudgetedBytes: (m['mem_budgeted_bytes'] as num?)?.toInt() ?? 0,
      memSoftBudget: (m['mem_soft_budget'] as num?)?.toInt() ?? 0,
      memHardBudget: (m['mem_hard_budget'] as num?)?.toInt() ?? 0,
      memSoftExceeded: m['mem_soft_exceeded'] == true,
      memRefusals: (m['mem_refusals'] as num?)?.toInt() ?? 0,
      memLastRefusal: m['mem_last_refusal'] as String?,
    );
  }
}
