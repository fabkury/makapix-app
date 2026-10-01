// The Layers page (ADR 0033; docs/layers-page/DESIGN.md): the active frame's stack as a list,
// top first, a selection of layer IDS, and one batch verb per operation on the whole set.
// Talks to the editor only through [LayersHost]; pops with a [LayersPageResult] (Make active /
// Use as Move group) or nothing.
//
// Rules the page enforces on its side of the seam: a refused batch leaves the selection alone
// and shows the reason on the status line; Duplicate selects the copies; Merge selects the
// survivor; content batches drop the members' thumbnails; undo/redo re-validate the visible
// rows by hash; the selection is discarded with the page; a sweep paints its first row's new
// state onto every row it crosses; the keyboard is handled here because the editor's
// dispatcher is muted under a pushed route.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:makapix_club/l10n/l10n.dart';

import 'package:makapix_club/ui/layout.dart';

import '../frames/frame_selection.dart';
import '../frames/frame_thumb_cache.dart';
import '../keyboard/chords.dart';
import '../tap_again.dart';
import '../thumbnail.dart';
import 'layer_list.dart';
import 'layer_model.dart';
import 'layer_names.dart';
import 'layer_row.dart';
import 'layers_action_bar.dart';
import 'layers_dialogs.dart';
import 'layers_host.dart';
import 'layers_more_sheet.dart';
import 'layers_select_sheet.dart';

const Color _kPageBg = Color(0xFF15171A);
const int _kThumbCapacity = 160;
const int _kThumbsPerFrame = 4;
const int _kThumbMaxSide = 64;

enum _BatchKind { structural, duplicate, merge, content, property }

class LayersPage extends StatefulWidget {
  const LayersPage({super.key, required this.host, this.roomyRows = false, this.onRoomyRowsChanged});

  final LayersHost host;

  /// Row density (persisted editor-wide by the editor).
  final bool roomyRows;
  final ValueChanged<bool>? onRoomyRowsChanged;

  @override
  State<LayersPage> createState() => _LayersPageState();
}

class _LayersPageState extends State<LayersPage> {
  LayersHost get host => widget.host;

  List<LayerRow> _rows = const [];
  List<int> _ids = const [];
  Map<int, int> _indexOf = const {};
  FrameSelection _sel = FrameSelection.empty;
  late bool _roomy = widget.roomyRows;
  bool _addToSelection = false;

  final ScrollController _scroll = ScrollController();
  final GlobalKey<LayerListState> _listKey = GlobalKey<LayerListState>();
  final FocusNode _focus = FocusNode(debugLabel: 'LayersPage', skipTraversal: true);
  late final TapAgainArm _deleteArm = TapAgainArm(onChanged: () {
    if (mounted) setState(() {});
  });

  late final FrameThumbCache _thumbs = LruById(capacity: _kThumbCapacity, onEvict: (t) => t.img.dispose());
  final Set<int> _thumbInFlight = {};
  final Set<int> _thumbFailed = {};
  final List<(int id, int index)> _thumbQueue = [];
  bool _pumpBooked = false;

  ({bool warn, String text})? _status;

  bool _sweepSelects = true;
  FrameSelection? _sweepBase;

  @override
  void initState() {
    super.initState();
    _syncFromHost();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listKey.currentState?.revealIndex(host.activeLayerIndex);
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
    _rows = host.layers;
    _ids = [for (final l in _rows) l.id];
    _indexOf = {for (var i = 0; i < _ids.length; i++) _ids[i]: i};
    _sel = _sel.retain(_ids.toSet());
  }

  /// Ascending engine indices of the selection.
  List<int> get _indices => _sel.toIndices(_indexOf);

  Object get _armKey => (_sel.signature, host.sendSeq);

  void _setSel(FrameSelection s) => setState(() {
        _sel = s;
        _status = null;
      });

  double get _scale => isTabletish(context) ? 1.2 : 1.0;

  double get _rowHeight => (_roomy ? kLayerRowHeightRoomy : kLayerRowHeightCompact) * _scale;

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
      final (id, _) = _thumbQueue.removeLast();
      final i = _indexOf[id];
      if (i == null || i >= _rows.length) continue;
      if (_thumbs.contains(id) || _thumbInFlight.contains(id)) continue;
      _thumbInFlight.add(id);
      n++;
      final hash = host.layerHash(i);
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

  /// After undo/redo or the single-layer sheet: drop the visible thumbs whose hash moved.
  void _revalidateVisible() {
    final (first, last) = _listKey.currentState?.visibleRange() ?? (0, -1);
    final stale = <int>[];
    for (var i = first; i <= last && i < _ids.length; i++) {
      if (i < 0) continue;
      final id = _ids[i];
      final cached = _thumbs.peek(id);
      if (cached != null && host.layerHash(i) != cached.hash) stale.add(id);
    }
    _thumbs.invalidate(stale);
    _thumbFailed.clear();
  }

  // ---- batches ----

  void _runBatch(String dsl, _BatchKind kind, {String? report}) {
    final before = _indices;
    final oldIds = Set.of(_sel.ids);
    final oldCount = _rows.length;
    final refusal = host.run(dsl);
    _syncFromHost();
    if (refusal != null) {
      setState(() => _status = (warn: true, text: refusal));
      return;
    }
    switch (kind) {
      case _BatchKind.duplicate:
        if (_rows.length == oldCount + before.length) {
          _sel = _sel.replaceWith(duplicateLayerResultIndices(before).map((i) => _ids[i]));
        }
      case _BatchKind.merge:
        if (before.isNotEmpty && before.first < _ids.length) {
          _sel = _sel.replaceWith([_ids[before.first]]);
        }
      case _BatchKind.content:
        _thumbs.invalidate(oldIds);
        _thumbFailed.clear();
      case _BatchKind.property:
      case _BatchKind.structural:
        break;
    }
    setState(() => _status = report == null ? null : (warn: false, text: report));
  }

  void _delete() {
    final idx = _indices;
    if (idx.isEmpty) return;
    final all = idx.length >= _rows.length;
    _runBatch(layerSetDsl('RemoveLayers', idx), _BatchKind.structural,
        report: all ? context.l10n.layersAllRemoved : null);
  }

  bool get _canMerge => _sel.length >= 2;

  void _merge() {
    final idx = _indices;
    if (idx.length < 2) return;
    if (!isContiguous(idx)) {
      setState(() => _status = (warn: true, text: context.l10n.layersMergeGap));
      return;
    }
    final locked = lockedCount(_rows, idx);
    if (locked > 0) {
      setState(() => _status = (warn: true, text: context.l10n.layersLockedFirst(locked)));
      return;
    }
    final survivor = _rows[idx.first].name;
    _runBatch(layerSetDsl('MergeLayers', idx), _BatchKind.merge, report: context.l10n.layersMerged(idx.length, shownLayerName(context.l10n, survivor)));
  }

  void _shift(int delta) {
    final idx = _indices;
    if (idx.isEmpty) return;
    final k = clampLayerShift(idx, delta, _rows.length);
    if (k == 0) return;
    _runBatch(layerSetDsl('ShiftLayers', idx, ['$k']), _BatchKind.structural);
  }

  bool get _canShiftUp => _indices.isNotEmpty && clampLayerShift(_indices, 1, _rows.length) != 0;
  bool get _canShiftDown => _indices.isNotEmpty && clampLayerShift(_indices, -1, _rows.length) != 0;

  Future<void> _more() async {
    final idx = _indices;
    if (idx.isEmpty) return;
    final c = host.canvasSize;
    final op = await showLayersMoreSheet(
      context,
      selectedCount: idx.length,
      lockedSelected: lockedCount(_rows, idx),
      canvasSquare: c.w == c.h,
      retainedBytes: retainedLayerPayloadBytes(_rows, idx),
      underCap: underLayerCap(_rows.length, idx.length),
      canShiftUp: _canShiftUp,
      canShiftDown: _canShiftDown,
      frameCount: host.frameCount,
    );
    if (op == null || !mounted) return;
    await _applyOp(op, idx);
  }

  Future<void> _applyOp(LayersOp op, List<int> idx) async {
    switch (op) {
      case DuplicateLayersOp():
        _runBatch(dslForLayerOp(op, idx), _BatchKind.duplicate);
      case ToEdgeOp(:final top):
        final k = clampLayerShift(idx, top ? kMaxLayers : -kMaxLayers, _rows.length);
        if (k == 0) return;
        _runBatch(dslForLayerOp(op, idx, delta: k), _BatchKind.structural);
      case ReverseLayersOp() || InsertBlankLayersOp():
        _runBatch(dslForLayerOp(op, idx), _BatchKind.structural);
      case SetVisibleOp() || SetLockedOp() || ResetLayersOp():
        _runBatch(dslForLayerOp(op, idx), _BatchKind.property);
      case OpacityOp():
        final v = await showLayersOpacityDialog(context, selectedCount: idx.length, initial: _rows[idx.first].opacity);
        if (v == null || !mounted) return;
        _runBatch(dslForLayerOp(op, idx, opacity: v), _BatchKind.property);
      case BlendOp():
        final blends = idx.map((i) => _rows[i].blend).toSet();
        final m = await showLayersBlendPicker(context, selectedCount: idx.length, current: blends.length == 1 ? blends.first : null);
        if (m == null || !mounted) return;
        _runBatch(dslForLayerOp(op, idx, blend: m), _BatchKind.property);
      case RenameLayersOp():
        final pattern = await showLayersRenameDialog(context, selectedCount: idx.length, initialText: idx.length == 1 && _rows[idx.first].name.isNotEmpty ? shownLayerName(context.l10n, _rows[idx.first].name) : '');
        if (pattern == null || !mounted) return;
        _runBatch(dslForLayerOp(op, idx, name: pattern), _BatchKind.property);
      case FlipLayersOp() || RotateLayersOp() || InvertLayersOp() || ClearLayersOp():
        final locked = lockedCount(_rows, idx);
        if (locked > 0) {
          setState(() => _status = (warn: true, text: context.l10n.layersLockedFirst(locked)));
          return;
        }
        _runBatch(dslForLayerOp(op, idx), _BatchKind.content);
      case CopyToFramesOp():
        final frames = await showCopyToFramesDialog(context, frameCount: host.frameCount, activeFrameIndex: host.activeFrameIndex, selectedCount: idx.length);
        if (frames == null || frames.isEmpty || !mounted) return;
        _runBatch(dslForLayerOp(op, idx, frames: frames), _BatchKind.structural,
            report: context.l10n.layersCopiedToFrames(frames.length));
      case UseAsMoveGroupOp():
        Navigator.pop(context, LayersPageResult.moveGroup(idx));
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
    final picked = await showLayerRangeDialog(context, layerCount: _rows.length, initialText: formatLayerSetHuman(_indices));
    if (picked == null || !mounted) return;
    _setSel(_sel.replaceWith(picked.map((i) => _ids[i])));
  }

  Future<void> _selectBy() async {
    final pick = await showLayersSelectSheet(
      context,
      rows: _rows,
      addToSelection: _addToSelection,
      onAddToSelectionChanged: (v) => _addToSelection = v,
    );
    if (pick == null || !mounted) return;
    final ids = pickLayers(_rows, pick).map((i) => _ids[i]);
    _setSel(_addToSelection ? _sel.addAll(ids) : _sel.replaceWith(ids));
  }

  void _setRoomy(bool v) {
    if (v == _roomy) return;
    setState(() => _roomy = v);
    widget.onRoomyRowsChanged?.call(v);
  }

  // ---- row menu ----

  Future<void> _rowMenu(int index) async {
    if (index < 0 || index >= _rows.length) return;
    final id = _ids[index];
    final anchorOk = _sel.anchorId != null && _sel.anchorId != id && _indexOf.containsKey(_sel.anchorId);
    final name = shownLayerName(context.l10n, _rows[index].name);
    final choice = await showAppSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1A1C1F),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(dense: true, title: Text('${ctx.l10n.layerDefaultName(index + 1)} · $name', style: const TextStyle(fontWeight: FontWeight.bold))),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.login), title: Text(ctx.l10n.layersMakeActive), onTap: () => Navigator.pop(ctx, 'activate')),
          ListTile(
            leading: const Icon(Icons.linear_scale),
            title: Text(ctx.l10n.batchSelectToHere),
            enabled: anchorOk,
            onTap: anchorOk ? () => Navigator.pop(ctx, 'range') : null,
          ),
          ListTile(leading: const Icon(Icons.tune), title: Text(ctx.l10n.layersLayerOptions), onTap: () => Navigator.pop(ctx, 'sheet')),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'activate':
        Navigator.pop(context, LayersPageResult.activate(index));
      case 'range':
        _setSel(_sel.rangeTo(id, _ids));
      case 'sheet':
        await host.openLayerSheet(index);
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
      if (repeat || _sel.isEmpty) return KeyEventResult.handled;
      if (_deleteArm.tap(_armKey)) {
        _delete();
      } else {
        setState(() => _status = (warn: false, text: context.l10n.layersDeleteAgain(_sel.length)));
      }
      return KeyEventResult.handled;
    }
    if (chord == const Chord(LogicalKeyboardKey.arrowUp)) {
      _shift(1);
      return KeyEventResult.handled;
    }
    if (chord == const Chord(LogicalKeyboardKey.arrowDown)) {
      _shift(-1);
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
        Navigator.pop(context, LayersPageResult.activate(_indices.first));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- build ----

  Widget _statusLine() {
    final s = _status;
    final n = _sel.length;
    final idle = n == 0 ? context.l10n.layersIdleHint : context.l10n.batchSelSummary(n, formatLayerSetHuman(_indices));
    final text = s?.text ?? idle;
    final color = s == null ? Colors.white38 : (s.warn ? Colors.amber : Colors.white70);
    final icon = s == null ? null : (s.warn ? Icons.warning_amber_rounded : Icons.info_outline);
    // Two lines, fixed height (no reflow when the text changes): on one line the idle hint was
    // cut off on a 360 px phone, in English too.
    return SizedBox(
      height: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 6)],
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.25, color: color))),
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
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(context.l10n.layersPageTitle(_rows.length)),
        ),
        actions: [
          IconButton(tooltip: context.l10n.toolUndo, icon: const Icon(Icons.undo), onPressed: host.canUndo ? _undo : null),
          IconButton(tooltip: context.l10n.toolRedo, icon: const Icon(Icons.redo), onPressed: host.canRedo ? _redo : null),
          PopupMenuButton<String>(
            tooltip: context.l10n.optSelect,
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
                case 'by':
                  _selectBy();
                case 'roomy':
                  _setRoomy(true);
                case 'compact':
                  _setRoomy(false);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'all', child: Text(ctx.l10n.selectAll)),
              PopupMenuItem(value: 'none', child: Text(ctx.l10n.selectNone)),
              PopupMenuItem(value: 'invert', child: Text(ctx.l10n.selectInvert)),
              PopupMenuItem(value: 'range', child: Text(ctx.l10n.layersSelectRangeMenu)),
              PopupMenuItem(value: 'by', child: Text(ctx.l10n.layersSelectByMenu)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'roomy', enabled: !_roomy, child: Text(ctx.l10n.layersBiggerRows)),
              PopupMenuItem(value: 'compact', enabled: _roomy, child: Text(ctx.l10n.layersSmallerRows)),
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
              child: LayerList(
                key: _listKey,
                rows: _rows,
                selection: _sel,
                activeIndex: host.activeLayerIndex,
                rowHeight: _rowHeight,
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
                onActivate: (index) => Navigator.pop(context, LayersPageResult.activate(index)),
                onRowMenu: _rowMenu,
              ),
            ),
            _statusLine(),
            LayersActionBar(
              scale: scale,
              selectedCount: _sel.length,
              canMerge: _canMerge,
              canShiftUp: _canShiftUp,
              canShiftDown: _canShiftDown,
              deleteArm: _deleteArm,
              armKey: _armKey,
              onDelete: _delete,
              onMerge: _merge,
              onShift: _shift,
              onMore: _more,
            ),
          ]),
        ),
      ),
    );
  }
}
