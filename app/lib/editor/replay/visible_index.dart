/// The visible-change index and the Replay timeline — pure, no engine (the Replay tick
/// semantics; CONTEXT.md "Tick", "Working time"; ADR 0029).
///
/// A replay position p is VISIBLE when the transition from p−1 to p can change what the
/// viewer shows (the composited canvas of the artist's active frame). Draft fiddling,
/// settings churn, cursor moves, selection-mask edits, palette work, and playback-preview
/// ticks are not visible; strokes, commits, applies, undo/redo, structural edits, frame
/// hops (the viewer follows the artist), and chapter-base loads are.
///
/// Every visible position is a TICK, and every tick is one of two classes:
///  * a STREAM tick — one of many near-identical steps of one gesture: a stamp-tool
///    `PointerDown`/`PointerMove`/`Tap`, a held-pen `MoveCursor`, a cursor plot/spray;
///  * an EVENT tick — everything else visible: commits, applies, fills, structural edits,
///    undo/redo, frame hops, shape/gradient `PointerUp`, chapter-base pops.
/// Each tick also carries its WORKING TIME: the recorded deltas of every journal line since
/// the previous tick (this one included), each gap clamped to [kGapCapMs] so pauses, resumes
/// days later, and playback periods count as at most one short beat. Invisible lines have no
/// tick of their own, so their time flows into the next tick — the seconds spent tuning Levels
/// land on the Apply; handle dragging lands on the shape's commit. `timelapse_plan.dart` turns
/// working time into video time (event ticks get a floor and a ceiling there; stream ticks
/// scale linearly), and the same axis drives the Replay viewer's sweep and slider.
///
/// The BURST RULE: an event tick whose verb repeats the previous tick's event verb within
/// [kBurstMs] of working time is demoted to a stream tick, so a run of held-arrow nudges, a
/// film-roll scrub of frame hops, or an undo storm flows at the speed it was performed instead
/// of claiming one event floor per repeat. The run's first event keeps its floor.
///
/// Visibility is a HEURISTIC verb triage, deliberately biased safe: an unknown or ambiguous
/// verb counts as visible (a rare dead tick is harmless; a skipped real change is not) and as
/// an event. The empirically dangerous direction — classifying a change-producing verb
/// invisible — is validated against composite hashes in the offline oracle harness.
library;

import 'dart:typed_data';

import 'journal_format.dart';

/// The per-gap clamp, ms: anything longer between two journal lines is "thinking or away" and
/// counts as exactly this much working time.
const int kGapCapMs = 2000;

/// The burst window, ms of working time: a repeat of the previous tick's event verb inside it
/// is paced as a stream step (see the library doc).
const int kBurstMs = 300;

/// The Replay timeline: the visible positions of one Journal with each tick's class and
/// working time — the shared axis of the Replay viewer and the Timelapse export. Typed arrays
/// (9 bytes per tick) so a 600k-line epic stays a few MB on the Dart heap.
class ReplayTimeline {
  ReplayTimeline(this.positions, this.isEvent, this.workMs)
      : assert(positions.length == isEvent.length && positions.length == workMs.length);

  /// Journal positions in `1..actionCount`, ascending; the final position is always the last
  /// tick (so the axis can reach the finished state even when the tail is settings churn).
  final Int32List positions;

  /// 1 = event tick, 0 = stream tick (after the burst rule).
  final Uint8List isEvent;

  /// Working time accrued to each tick, milliseconds (per-gap clamped sums).
  final Uint32List workMs;

  int get length => positions.length;
  bool get isEmpty => positions.isEmpty;

  /// A timeline of [count] uniform stream ticks at positions `1..count` — a journal with no
  /// timing (tests, synthetic scripts) paces exactly like the pre-ADR-0029 visible index.
  factory ReplayTimeline.uniform(int count) => ReplayTimeline(
        Int32List.fromList([for (var i = 1; i <= count; i++) i]),
        Uint8List(count),
        Uint32List(count)..fillRange(0, count, 1),
      );

  static final ReplayTimeline empty = ReplayTimeline(Int32List(0), Uint8List(0), Uint32List(0));
}

// Statement classes, ordered so a line's class is the max over its statements.
const int _none = 0;
const int _stream = 1;
const int _event = 2;

/// Verbs that always change the followed composite (or what the viewer points at) — event
/// ticks.
const Set<String> _kAlwaysEvent = {
  // Document / frame structure (the viewer follows the artist's active frame).
  'NewDocument', 'AddFrame', 'AddFrameAt', 'DuplicateFrame', 'RemoveFrame', 'ReorderFrame',
  'SetActiveFrame',
  // Layer structure & properties that composite.
  'RemoveLayer', 'DuplicateLayer', 'DuplicateLayerToFrames', 'MergeDown', 'ReorderLayer',
  'SetLayerOpacity', 'SetLayerVisible', 'SetLayerBlend', 'PreviewLayerBlend',
  'NudgeLayers', 'NudgeMove',
  // Whole-canvas / frame / layer transforms.
  'FlipCanvasH', 'FlipCanvasV', 'FlipFrameH', 'FlipFrameV', 'FlipH', 'FlipV',
  'Invert', 'InvertFrame', 'ResizeCanvas', 'CropToSelection', 'CropCanvas',
  'Rotate', 'RotateFrame', 'RotateLayer', 'ScaleFrame', 'ScaleLayer',
  // Draft commits + adjustment applies (the moment pixels land).
  'ShapeCommit', 'PasteCommit', 'MoveDraftCommit', 'RotateDraftCommit', 'ScaleDraftCommit',
  'ApplyHsvShift', 'ApplyBrightnessContrast', 'ApplyLevels',
  // Clipboard / selected-pixel operations.
  'Cut', 'Paste', 'PasteToFrame', 'FillSelection', 'ClearSelection',
  // History.
  'Undo', 'Redo',
  // Direct painting verbs that land a whole region at once.
  'FillNoise', 'FillCursor',
  // Aborting a stroke restores pre-stroke pixels (visible when anything was painted).
  'CancelStroke',
};

/// Verbs that stamp one step of a gesture at the cursor — stream ticks. The precision pen's
/// pen-down stamps its first pixel; a plot or spray at the cursor is one step of a stroke.
const Set<String> _kStreamVerbs = {'CursorPenDown', 'PlotCursor', 'AirbrushCursor'};

/// Engine tools whose pointer contact paints immediately (down + every move visible).
const Set<String> _kStampTools = {
  'Pencil', 'Brush', 'Airbrush', 'AirbrushSoft', 'AirbrushMist', 'Eraser', 'Bucket', 'Dodge', 'Burn', 'Move',
};

/// Stamp tools whose every contact is a whole-region change (a fill), not a stroke step.
const Set<String> _kEventContactTools = {'Bucket'};

/// Engine tools that rasterize on pointer-UP (the direct-gesture path scripts use).
const Set<String> _kUpTools = {'Line', 'Rectangle', 'Ellipse', 'Triangle', 'Gradient', 'Move'};

String _resolveTool(String name) => switch (name) {
      'PrecisionPencil' => 'Pencil', // the parser's legacy aliases
      'MoveLayer' => 'Move',
      _ => name,
    };

/// Build the timeline of [flat]: the visible positions with tick classes and working time.
/// One pass over the lines; the state tracking (active tool, pen held) is the same triage
/// [visiblePositions] has always applied.
ReplayTimeline buildTimeline(FlatJournal flat, {int gapCapMs = kGapCapMs, int burstMs = kBurstMs}) {
  final n = flat.actions.length;
  if (n == 0) return ReplayTimeline.empty;
  final positions = <int>[];
  final classes = <int>[];
  final works = <int>[];
  var tool = 'Pencil'; // Session::new's default
  var penHeld = false;
  var acc = 0; // working time since the previous tick, ms
  String? prevEventVerb; // the previous tick's event verb; null after a stream tick
  for (var i = 0; i < n; i++) {
    final d = flat.deltasMs[i];
    acc += d > gapCapMs ? gapCapMs : (d < 0 ? 0 : d);
    var cls = _none;
    String? eventVerb;
    if (i > 0 && flat.chapterBaseAt.containsKey(i)) {
      cls = _event; // the base-load pop
      eventVerb = '#base';
    }
    for (final raw in flat.actions[i].split(';')) {
      final stmt = raw.trim();
      if (stmt.isEmpty || stmt.startsWith('#') || stmt.startsWith('//')) continue;
      final paren = stmt.indexOf('(');
      final verb = paren <= 0 ? stmt : stmt.substring(0, paren);
      final c = _classify(verb, tool, penHeld);
      if (c > cls) cls = c;
      if (c == _event) eventVerb ??= verb;
      // State tracking AFTER classification (the statement acts with the prior state).
      switch (verb) {
        case 'SelectTool':
          final inner = paren <= 0 ? '' : stmt.substring(paren + 1, stmt.lastIndexOf(')'));
          tool = _resolveTool(inner.trim());
        case 'CursorPenDown':
          penHeld = true;
        case 'CursorPenUp':
          penHeld = false;
        case 'NewDocument':
          tool = 'Pencil'; // the whole-session reset restores defaults
          penHeld = false;
      }
    }
    if (cls == _none) continue;
    var isEvent = cls == _event;
    if (isEvent && eventVerb == prevEventVerb && acc < burstMs) isEvent = false; // the burst rule
    prevEventVerb = cls == _event ? eventVerb : null;
    positions.add(i + 1);
    classes.add(isEvent ? 1 : 0);
    works.add(acc);
    acc = 0;
  }
  if (positions.isEmpty || positions.last != n) {
    // The always-kept final position: nothing visible happens there, so it is a stream tick
    // (no event floor) that merely extends the last state by the trailing churn's time.
    positions.add(n);
    classes.add(0);
    works.add(acc);
  }
  final len = positions.length;
  final pos = Int32List(len), ev = Uint8List(len), work = Uint32List(len);
  for (var k = 0; k < len; k++) {
    pos[k] = positions[k];
    ev[k] = classes[k];
    final w = works[k];
    work[k] = w > 0xFFFFFFFF ? 0xFFFFFFFF : w;
  }
  return ReplayTimeline(pos, ev, work);
}

/// Ascending positions in `1..actions.length` whose transition is visible — the timeline's
/// positions (kept as the oracle harness's and the tests' entry point).
List<int> visiblePositions(FlatJournal flat) => buildTimeline(flat).positions;

int _classify(String verb, String tool, bool penHeld) {
  if (_kAlwaysEvent.contains(verb)) return _event;
  if (_kStreamVerbs.contains(verb)) return _stream;
  switch (verb) {
    case 'PointerDown' || 'PointerMove':
      if (!_kStampTools.contains(tool)) return _none;
      return _kEventContactTools.contains(tool) ? _event : _stream;
    case 'PointerUp':
      return _kUpTools.contains(tool) ? _event : _none;
    case 'Tap':
      if (_kUpTools.contains(tool) || _kEventContactTools.contains(tool)) return _event;
      return _kStampTools.contains(tool) ? _stream : _none;
    case 'Stroke': // a scripted whole stroke lands at once
      return _kStampTools.contains(tool) || _kUpTools.contains(tool) ? _event : _none;
    case 'MoveCursor':
      return penHeld ? _stream : _none; // the precision pen paints while held
  }
  // Known-invisible families: every Set*, SelectTool, selection-mask ops, draft
  // lifecycle non-commits, palette work, Copy, cursor bracketing, clock/playback,
  // ClearHistory, renames/locks/durations. Everything unknown defaults VISIBLE.
  const invisible = {
    'SelectTool', 'SetCursor',
    'SelectAll', 'SelectNone', 'InvertSelection', 'SelectByAlpha',
    'MoveSelection', 'MoveSelectionBegin', 'MoveSelectionCommit',
    'ShapeSet', 'ShapeCancel',
    'PasteDraft', 'PasteMove', 'PasteCancel', 'Copy',
    'MoveDraftBegin', 'MoveDraftMove', 'MoveDraftCancel',
    'RotateDraftBegin', 'RotateDraftBeginFrame', 'RotateDraftSetAngle', 'RotateDraftMove',
    'RotateDraftCancel',
    'ScaleDraftBegin', 'ScaleDraftBeginFrame', 'ScaleDraftSet', 'ScaleDraftMove',
    'ScaleDraftCancel',
    'CursorPenUp', 'CursorStrokeBegin', 'CursorStrokeEnd',
    'EyedropCursor', 'SelectColorCursor',
    'AdvanceClock', 'Play', 'Pause', 'ClearHistory',
    'RenameLayer', 'SetLayerLocked', 'SetActiveLayer', 'SetActiveLayers', 'SetMoveGroup',
    'SetFrameDuration', 'SetAllDurations', 'SetLoopMode',
    'NewPalette', 'DeletePalette', 'DuplicatePalette', 'RenamePalette', 'RenamePaletteAt',
    'MovePalette', 'SetActivePalette', 'AddPaletteColor', 'RemovePaletteColor',
    'EditPaletteColor', 'DuplicatePaletteColor', 'SwapPaletteColors', 'SortPalette',
    'SortPaletteAt', 'ClearPalette', 'ClearPaletteAt', 'NamePaletteColor',
    // The settings family — enumerated (not a Set* catch-all) so a FUTURE visible Set
    // verb still gets the safe default below.
    'SetAA', 'SetAlphaCutoff', 'SetBcScope', 'SetBrightnessContrast', 'SetBrushShape', 'SetBrushSize',
    'SetCleanEdge', 'SetCleanEdgeWidth', 'SetContiguous', 'SetEyedropSource',
    'SetFillAllLayers', 'SetGradientDither', 'SetGradientSmoothstep', 'SetGradientStops', 'SetGradientType',
    'SetHsvScope', 'SetHsvShift', 'SetIntensity', 'SetLevels', 'SetLevelsScope',
    'SetLineWidth', 'SetMemBudget', 'SetOverscanView', 'SetPattern', 'SetPixelPerfect', 'SetPrimaryColor',
    'SetProtectPixels', 'SetScaleCleanEdge', 'SetScaleCleanEdgeWidth', 'SetSecondaryColor',
    'SetSeed', 'SetSelectColorSource', 'SetSelectionMode', 'SetShapeFill', 'SetSymmetry',
    'SetShapeRotation', 'SetSpacing', 'SetThreshold', 'SetTriangleTip', 'SetWrap',
  };
  if (invisible.contains(verb)) return _none;
  return _event; // unknown → visible event: a dead tick beats a skipped change
}
