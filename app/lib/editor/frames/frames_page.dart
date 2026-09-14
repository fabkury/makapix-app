// The Frames page (ADR 0031; docs/frames-page/DESIGN.md): every frame of the animation as a
// grid, a selection of frame IDS, and one batch verb per operation on the whole set. Talks to
// the editor only through [FramesHost]; pops with the index to activate (Go to) or nothing.
//
// Rules the page enforces on its side of the seam: a refused batch leaves the selection alone
// and shows the reason; Duplicate/Repeat select the copies; content batches drop the affected
// thumbnails; undo/redo re-validate the visible tiles by hash; the selection is discarded with
// the page; a sweep paints its first tile's new state (select or deselect) onto every tile it
// crosses; the keyboard is handled here because the editor's dispatcher is muted under a
// pushed route.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:makapix_club/ui/layout.dart';

import '../dialogs/duration_dialog.dart';
import '../keyboard/chords.dart';
import '../tap_again.dart';
import '../thumbnail.dart';
import 'frame_grid.dart';
import 'frame_grid_geometry.dart';
import 'frame_model.dart';
import 'frame_selection.dart';
import 'frame_set.dart';
import 'frame_thumb_cache.dart';
import 'frames_action_bar.dart';
import 'frames_dialogs.dart';
import 'frames_host.dart';
import 'frames_more_sheet.dart';
import 'layer_name_picker.dart';

const Color _kPageBg = Color(0xFF15171A);
const int _kThumbCapacity = 300;
const int _kThumbsPerFrame = 4;
const int _kThumbMaxSide = 96;

enum _BatchKind { structural, duplicate, repeat, content, durations }

class FramesPage extends StatefulWidget {
  const FramesPage({super.key, required this.host, this.columns = kFramesDefaultColumns, this.onColumnsChanged});

  final FramesHost host;
  final int columns;
  final ValueChanged<int>? onColumnsChanged;

  @override
  State<FramesPage> createState() => _FramesPageState();
}

class _FramesPageState extends State<FramesPage> {
  FramesHost get host => widget.host;

  List<FrameInfo> _frames = const [];
  List<int> _ids = const [];
  Map<int, int> _indexOf = const {};
  FrameSelection _sel = FrameSelection.empty;
  late int _columns = widget.columns.clamp(kFramesMinColumns, kFramesMaxColumns);

  final ScrollController _scroll = ScrollController();
  final GlobalKey<FrameGridState> _gridKey = GlobalKey<FrameGridState>();
  final FocusNode _focus = FocusNode(debugLabel: 'FramesPage', skipTraversal: true);
  late final TapAgainArm _deleteArm = TapAgainArm(onChanged: () {
    if (mounted) setState(() {});
  });

  late final FrameThumbCache _thumbs = LruById(capacity: _kThumbCapacity, onEvict: (t) => t.img.dispose());
  final Set<int> _thumbInFlight = {};
  final Set<int> _thumbFailed = {};
  final List<(int id, int index)> _thumbQueue = [];
  bool _pumpBooked = false;

  ({bool warn, String text})? _status;

  /// What the running sweep paints: the first tile's state after its flip.
  bool _sweepSelects = true;

  /// The selection as it was before the running sweep, restored when a second finger turns
  /// the touch into a pinch.
  FrameSelection? _sweepBase;

  @override
  void initState() {
    super.initState();
    _syncFromHost();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _gridKey.currentState?.revealIndex(host.activeFrameIndex);
    });
  }

  @override
  void dispose() {
    _deleteArm.dispose();
    _thumbs.clear();
    _thumbQueue.clear();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---- state ----

  void _syncFromHost() {
    _frames = host.frames;
    _ids = [for (final f in _frames) f.id];
    _indexOf = {for (var i = 0; i < _ids.length; i++) _ids[i]: i};
    _sel = _sel.retain(_ids.toSet());
  }

  List<int> get _indices => _sel.toIndices(_indexOf);

  Object get _armKey => (_sel.signature, host.sendSeq);

  void _setSel(FrameSelection s) => setState(() {
        _sel = s;
        _status = null;
      });

  double get _scale => isTabletish(context) ? 1.2 : 1.0;

  double get _thumbAspect {
    final c = host.canvasSize;
    return c.h > 0 ? c.w / c.h : 1;
  }

  // ---- thumbnails ----

  ui.Image? _thumbFor(int id) => _thumbs.get(id)?.img;

  void _requestThumb(int id, int index) {
    if (_thumbs.contains(id) || _thumbInFlight.contains(id) || _thumbFailed.contains(id)) return;
    if (_thumbQueue.any((e) => e.$1 == id)) return;
    _thumbQueue.add((id, index));
    if (!_pumpBooked) {
      _pumpBooked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pumpThumbs());
    }
  }

  Future<void> _pumpThumbs() async {
    _pumpBooked = false;
    if (!mounted) return;
    final c = host.canvasSize;
    final (tw, th) = thumbSizeFor(c.w, c.h, maxSide: _kThumbMaxSide);
    var n = 0;
    while (_thumbQueue.isNotEmpty && n < _kThumbsPerFrame) {
      final (id, index) = _thumbQueue.removeLast(); // most recently built = on screen now
      final live = _indexOf[id];
      if (live == null || live != index && live >= _frames.length) continue;
      final i = live;
      if (_thumbs.contains(id) || _thumbInFlight.contains(id)) continue;
      _thumbInFlight.add(id);
      n++;
      final hash = host.frameHash(i);
      final bytes = host.thumbBytes(i, tw, th);
      if (bytes.length < tw * th * 4) {
        _thumbInFlight.remove(id);
        _thumbFailed.add(id);
        continue;
      }
      final img = await decodeRgbaImage(bytes, tw, th);
      _thumbInFlight.remove(id);
      if (!mounted) {
        img.dispose();
        return;
      }
      _thumbs.put(id, ThumbCache(hash, img));
    }
    if (!mounted) return;
    setState(() {});
    if (_thumbQueue.isNotEmpty && !_pumpBooked) {
      _pumpBooked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pumpThumbs());
    }
  }

  /// After undo/redo or the single-frame sheet: drop the visible thumbs whose hash moved.
  void _revalidateVisible() {
    final (first, last) = _gridKey.currentState?.visibleRange() ?? (0, -1);
    final stale = <int>[];
    for (var i = first; i <= last && i < _ids.length; i++) {
      final id = _ids[i];
      final cached = _thumbs.peek(id);
      if (cached != null && host.frameHash(i) != cached.hash) stale.add(id);
    }
    _thumbs.invalidate(stale);
    _thumbFailed.clear();
  }

  // ---- batches ----

  void _runBatch(String dsl, _BatchKind kind, {String? report}) {
    final before = _indices;
    final oldIds = Set.of(_sel.ids);
    final oldCount = _frames.length;
    final refusal = host.run(dsl);
    _syncFromHost();
    if (refusal != null) {
      setState(() => _status = (warn: true, text: refusal));
      return;
    }
    switch (kind) {
      case _BatchKind.duplicate:
        if (_frames.length == oldCount + before.length) {
          _sel = _sel.replaceWith(duplicateResultIndices(before).map((i) => _ids[i]));
        }
      case _BatchKind.repeat:
        if (_frames.length == oldCount + before.length) {
          _sel = _sel.replaceWith(repeatResultIndices(before).map((i) => _ids[i]));
        }
      case _BatchKind.content:
        _thumbs.invalidate(oldIds);
        _thumbFailed.clear();
      case _BatchKind.durations:
      case _BatchKind.structural:
        break;
    }
    setState(() => _status = report == null ? null : (warn: false, text: report));
  }

  bool get _canDelete => _sel.isNotEmpty && _sel.length < _frames.length;

  void _delete() {
    if (!_canDelete) return;
    _runBatch(frameSetDsl('RemoveFrames', _indices), _BatchKind.structural);
  }

  void _duplicate() {
    final idx = _indices;
    if (idx.isEmpty) return;
    _runBatch(frameSetDsl('DuplicateFrames', idx), _BatchKind.duplicate);
  }

  Future<void> _duration(List<int> idx) async {
    if (idx.isEmpty) return;
    final n = idx.length;
    final r = await showDurationDialog(
      context,
      title: '$n ${n == 1 ? 'frame' : 'frames'} — duration',
      initialMs: _frames[idx.first].durationMs,
      actions: ['Apply to $n ${n == 1 ? 'frame' : 'frames'}'],
    );
    if (r == null || !mounted) return;
    final requestedUs = (r.ms * 1000).round();
    final pinned = pinnedCountForSet(idx, requestedUs);
    _runBatch(
      dslForOp(const SetDurationOp(), idx, ms: r.ms),
      _BatchKind.durations,
      report: pinned > 0 ? '$pinned ${pinned == 1 ? 'frame' : 'frames'} pinned at ${_pinLabel(requestedUs)}' : null,
    );
  }

  String _pinLabel(int requestedUs) => requestedUs < kMinDurationUs ? '16.7 ms' : '1000 ms';

  void _nudge(int delta) {
    final idx = _indices;
    if (idx.isEmpty) return;
    final k = clampShift(idx, delta, _frames.length);
    if (k == 0) return;
    _runBatch(frameSetDsl('ShiftFrames', idx, ['$k']), _BatchKind.structural);
  }

  bool get _canNudgeLeft => _indices.isNotEmpty && clampShift(_indices, -1, _frames.length) != 0;
  bool get _canNudgeRight => _indices.isNotEmpty && clampShift(_indices, 1, _frames.length) != 0;

  Future<void> _more() async {
    final idx = _indices;
    if (idx.isEmpty) return;
    final c = host.canvasSize;
    final op = await showFramesMoreSheet(
      context,
      selectedCount: idx.length,
      canvasSquare: c.w == c.h,
      retainedBytes: retainedPayloadBytes(_frames, idx),
      anyTargetAtLayerCap: idx.any((i) => _frames[i].layers.length >= kMaxLayers),
      hasLayerNames: layerNameHits(_frames, idx).isNotEmpty,
    );
    if (op == null || !mounted) return;
    await _applyOp(op, idx);
  }

  Future<void> _applyOp(FramesOp op, List<int> idx) async {
    switch (op) {
      case ShiftByOp():
        final k = await showShiftByDialog(context, indices: idx, frameCount: _frames.length);
        if (k == null || k == 0 || !mounted) return;
        _runBatch(dslForOp(op, idx, delta: k), _BatchKind.structural);
      case SetDurationOp():
        await _duration(idx);
      case ScaleOp(permille: final p):
        var permille = p;
        if (permille == null) {
          permille = await showScaleFactorDialog(context);
          if (permille == null || !mounted) return;
        }
        final pinned = pinnedCountForScale(_frames, idx, permille);
        _runBatch(
          dslForOp(op, idx, permille: permille),
          _BatchKind.durations,
          report: pinned > 0 ? '$pinned ${pinned == 1 ? 'frame' : 'frames'} pinned at the ${permille < 1000 ? '16.7 ms floor' : '1000 ms ceiling'}' : null,
        );
      case RepeatAfterOp():
        _runBatch(dslForOp(op, idx), _BatchKind.repeat);
      case InsertBlankOp() || ReverseOp():
        _runBatch(dslForOp(op, idx), _BatchKind.structural);
      case FlipOp() || RotateOp() || InvertOp() || CopyLayerOp():
        _runBatch(dslForOp(op, idx), _BatchKind.content);
      case RemoveLayerNamedOp() || SetLayersVisibleOp() || SetLayersLockedOp():
        final title = switch (op) {
          RemoveLayerNamedOp() => 'Remove layer named…',
          SetLayersVisibleOp(:final visible) => visible ? 'Show layer named…' : 'Hide layer named…',
          SetLayersLockedOp(:final locked) => locked ? 'Lock layer named…' : 'Unlock layer named…',
          _ => '',
        };
        final name = await showLayerNamePicker(context, title: title, names: layerNameHits(_frames, idx), selectedCount: idx.length);
        if (name == null || !mounted) return;
        _runBatch(dslForOp(op, idx, layerName: name), opChangesContent(op) ? _BatchKind.content : _BatchKind.structural);
    }
  }

  void _undo() {
    if (!host.canUndo) return;
    host.undo();
    _syncFromHost();
    _revalidateVisible();
    setState(() => _status = null);
  }

  void _redo() {
    if (!host.canRedo) return;
    host.redo();
    _syncFromHost();
    _revalidateVisible();
    setState(() => _status = null);
  }

  // ---- selection helpers ----

  Future<void> _rangeDialog() async {
    final picked = await showFrameRangeDialog(context, frameCount: _frames.length, initialText: formatFrameSetHuman(_indices));
    if (picked == null || !mounted) return;
    _setSel(_sel.replaceWith(picked.map((i) => _ids[i])));
  }

  Future<void> _everyNthDialog() async {
    final r = await showEveryNthDialog(context, hasSelection: _sel.isNotEmpty);
    if (r == null || !mounted) return;
    final base = r.withinSelection && _sel.isNotEmpty ? _indices : [for (var i = 0; i < _ids.length; i++) i];
    _setSel(_sel.replaceWith(everyNth(base, n: r.n, offset: r.offset).map((i) => _ids[i])));
  }

  void _setColumns(int c) {
    final next = c.clamp(kFramesMinColumns, kFramesMaxColumns);
    if (next == _columns) return;
    setState(() => _columns = next);
    widget.onColumnsChanged?.call(next);
  }

  // ---- tile menu ----

  Future<void> _tileMenu(int index) async {
    if (index < 0 || index >= _frames.length) return;
    final id = _ids[index];
    final anchorOk = _sel.anchorId != null && _sel.anchorId != id && _indexOf.containsKey(_sel.anchorId);
    final choice = await showAppSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(dense: true, title: Text('Frame ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.login), title: Text('Go to frame ${index + 1}'), onTap: () => Navigator.pop(ctx, 'goto')),
          ListTile(
            leading: const Icon(Icons.linear_scale),
            title: const Text('Select to here'),
            enabled: anchorOk,
            onTap: anchorOk ? () => Navigator.pop(ctx, 'range') : null,
          ),
          ListTile(leading: const Icon(Icons.tune), title: const Text('Frame options…'), onTap: () => Navigator.pop(ctx, 'sheet')),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'goto':
        Navigator.pop(context, index);
      case 'range':
        _setSel(_sel.rangeTo(id, _ids));
      case 'sheet':
        await host.openFrameSheet(index);
        if (!mounted) return;
        _syncFromHost();
        _revalidateVisible();
        setState(() {});
    }
  }

  // ---- keyboard ----

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final chord = Chord.fromEvent(event);
    if (chord == null) return KeyEventResult.ignored;
    final repeat = event is KeyRepeatEvent;
    if (chord == const Chord(LogicalKeyboardKey.keyA, primary: true)) {
      if (!repeat) _setSel(_sel.selectAll(_ids));
      return KeyEventResult.handled;
    }
    if (chord == const Chord(LogicalKeyboardKey.escape)) {
      if (repeat) return KeyEventResult.handled;
      if (_sel.isNotEmpty) {
        _setSel(_sel.cleared());
      } else {
        Navigator.pop(context);
      }
      return KeyEventResult.handled;
    }
    if (chord == const Chord(LogicalKeyboardKey.delete) || chord == const Chord(LogicalKeyboardKey.backspace)) {
      if (repeat || !_canDelete) return KeyEventResult.handled;
      if (_deleteArm.tap(_armKey)) {
        _delete();
      } else {
        setState(() => _status = (warn: false, text: 'Press Delete again to delete ${_sel.length} ${_sel.length == 1 ? 'frame' : 'frames'}'));
      }
      return KeyEventResult.handled;
    }
    if (chord == const Chord(LogicalKeyboardKey.arrowLeft)) {
      _nudge(-1);
      return KeyEventResult.handled;
    }
    if (chord == const Chord(LogicalKeyboardKey.arrowRight)) {
      _nudge(1);
      return KeyEventResult.handled;
    }
    if (chord == const Chord(LogicalKeyboardKey.keyZ, primary: true)) {
      _undo();
      return KeyEventResult.handled;
    }
    if (chord == const Chord(LogicalKeyboardKey.keyZ, primary: true, shift: true) ||
        chord == const Chord(LogicalKeyboardKey.keyY, primary: true)) {
      _redo();
      return KeyEventResult.handled;
    }
    if (chord == const Chord(LogicalKeyboardKey.enter) || chord == const Chord(LogicalKeyboardKey.numpadEnter)) {
      if (!repeat && _sel.length == 1) {
        final i = _indices.first;
        Navigator.pop(context, i);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- build ----

  Widget _statusLine() {
    final s = _status;
    final n = _sel.length;
    final idle = n == 0 ? 'Tap or slide to select · hold for options · double-tap to go to' : '$n selected · ${formatFrameSetHuman(_indices)}';
    final text = s?.text ?? idle;
    final color = s == null ? Colors.white38 : (s.warn ? Colors.amber : Colors.white70);
    final icon = s == null ? null : (s.warn ? Icons.warning_amber_rounded : Icons.info_outline);
    return SizedBox(
      height: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 6)],
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: color))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: _kPageBg,
        title: Text('Frames · ${_frames.length}'),
        actions: [
          IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo), onPressed: host.canUndo ? _undo : null),
          IconButton(tooltip: 'Redo', icon: const Icon(Icons.redo), onPressed: host.canRedo ? _redo : null),
          PopupMenuButton<String>(
            tooltip: 'Select',
            onSelected: (v) {
              switch (v) {
                case 'all':
                  _setSel(_sel.selectAll(_ids));
                case 'none':
                  _setSel(_sel.cleared());
                case 'invert':
                  _setSel(_sel.invert(_ids));
                case 'range':
                  _rangeDialog();
                case 'nth':
                  _everyNthDialog();
                case 'fewer':
                  _setColumns(_columns - 1);
                case 'more':
                  _setColumns(_columns + 1);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'all', child: Text('Select all')),
              const PopupMenuItem(value: 'none', child: Text('Select none')),
              const PopupMenuItem(value: 'invert', child: Text('Invert selection')),
              const PopupMenuItem(value: 'range', child: Text('Select frames…')),
              const PopupMenuItem(value: 'nth', child: Text('Every Nth frame…')),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'fewer', enabled: _columns > kFramesMinColumns, child: const Text('Bigger tiles')),
              PopupMenuItem(value: 'more', enabled: _columns < kFramesMaxColumns, child: const Text('Smaller tiles')),
            ],
          ),
        ],
      ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!_focus.hasFocus && (ModalRoute.of(context)?.isCurrent ?? true)) _focus.requestFocus();
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Column(children: [
            Expanded(
              child: FrameGrid(
                key: _gridKey,
                frames: _frames,
                selection: _sel,
                activeIndex: host.activeFrameIndex,
                columns: _columns,
                thumbAspect: _thumbAspect,
                scale: scale,
                controller: _scroll,
                thumbFor: _thumbFor,
                requestThumb: _requestThumb,
                onTap: (id, {required range}) => _setSel(range ? _sel.rangeTo(id, _ids) : _sel.toggle(id)),
                onSweepStart: (id) {
                  _sweepBase = _sel;
                  _sweepSelects = !_sel.contains(id);
                  _setSel(_sweepSelects ? _sel.addAll([id], anchor: id) : _sel.removeAll([id], anchor: id));
                },
                onSweepAdd: (ids) => _setSel(_sweepSelects ? _sel.addAll(ids) : _sel.removeAll(ids)),
                onSweepCancel: () {
                  final base = _sweepBase;
                  _sweepBase = null;
                  if (base != null) _setSel(base.retain(_ids.toSet()));
                },
                onGoTo: (index) => Navigator.pop(context, index),
                onTileMenu: _tileMenu,
                onBand: (ids, {required additive, required done}) {
                  _bandBase ??= _sel;
                  final base = additive ? _bandBase! : FrameSelection.empty;
                  _setSel(base.addAll(ids));
                  if (done) _bandBase = null;
                },
                onColumnsChanged: _setColumns,
              ),
            ),
            _statusLine(),
            FramesActionBar(
              scale: scale,
              selectedCount: _sel.length,
              canDelete: _canDelete,
              canNudgeLeft: _canNudgeLeft,
              canNudgeRight: _canNudgeRight,
              deleteArm: _deleteArm,
              armKey: _armKey,
              onDelete: _delete,
              onDuplicate: _duplicate,
              onNudge: _nudge,
              onMore: _more,
            ),
          ]),
        ),
      ),
    );
  }

  FrameSelection? _bandBase;
}
