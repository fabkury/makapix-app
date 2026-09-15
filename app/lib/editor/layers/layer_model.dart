// The Layers page's read model and pure helpers (ADR 0033; docs/layers-page/DESIGN.md): a typed
// view of the active frame's layer entries in `frame_detail`, the wire form the batch verbs
// take (the frame set's grammar over the stack, 0-based bottom-first), the 1-based forms people
// type and read, the by-property selectors, the rename pattern, and the pre-checks the page
// shows before a tap. Pure Dart, tested without the engine; every rule here mirrors
// `crates/engine/src/session/layers.rs`.

import '../frames/frame_model.dart' show kMaxLayers, kTileBytes;
import '../frames/frame_set.dart' show formatFrameSet, formatFrameSetHuman, sanitizeLayerName;

export '../frames/frame_model.dart' show kMaxLayers;

/// One layer of the active frame, as `frame_detail` reports it. The [id] is the engine's stable
/// layer identity: the page's selection is held by id, never by index.
class LayerRow {
  const LayerRow({
    required this.id,
    required this.name,
    this.visible = true,
    this.locked = false,
    this.opacity = 255,
    this.blend = 'Normal',
    this.presentTiles = 0,
  });

  final int id;
  final String name;
  final bool visible;
  final bool locked;
  final int opacity;

  /// The engine token (`Normal`, `Multiply`, …).
  final String blend;

  /// Materialized 32×32 tiles — the layer's payload in [kTileBytes] units.
  final int presentTiles;

  bool get isEmpty => presentTiles == 0;
  int get payloadBytes => presentTiles * kTileBytes;
  bool get isDefaultState => visible && !locked && opacity == 255 && blend == 'Normal';
}

/// The active frame's stack in engine order (bottom first), parsed from `frame_detail`.
/// Tolerant: a malformed entry falls back to defaults; an entry without an `id` (an older
/// engine) takes its index, which is still unique within the frame.
List<LayerRow> parseLayerDetail(List<dynamic>? frameDetail, int activeFrame) {
  if (frameDetail == null || activeFrame < 0 || activeFrame >= frameDetail.length) return const [];
  final f = frameDetail[activeFrame];
  if (f is! Map) return const [];
  final raw = f['layers'];
  if (raw is! List) return const [];
  final out = <LayerRow>[];
  for (var i = 0; i < raw.length; i++) {
    final l = raw[i];
    if (l is! Map) {
      out.add(LayerRow(id: i, name: ''));
      continue;
    }
    out.add(LayerRow(
      id: ((l['id'] as num?) ?? i).toInt(),
      name: (l['name'] as String?) ?? '',
      visible: (l['visible'] as bool?) ?? true,
      locked: (l['locked'] as bool?) ?? false,
      opacity: ((l['opacity'] as num?) ?? 255).toInt(),
      blend: (l['blend'] as String?) ?? 'Normal',
      presentTiles: ((l['present_tiles'] as num?) ?? 0).toInt(),
    ));
  }
  return out;
}

/// The canonical 0-based wire form (`0-3 7`) — the frame set's formatter; the grammar is one.
String formatLayerSet(Iterable<int> indices) => formatFrameSet(indices);

/// The 1-based human form, counting the bottom layer as 1: `1–4, 8`.
String formatLayerSetHuman(Iterable<int> indices) => formatFrameSetHuman(indices);

/// `Verb(set[, args…])` — the batch verb line the page sends.
String layerSetDsl(String verb, Iterable<int> indices, [List<String> args = const []]) {
  final set = formatLayerSet(indices);
  return args.isEmpty ? '$verb($set)' : '$verb($set, ${args.join(', ')})';
}

/// Parse the Range entry: 1-based layer numbers (bottom = 1) and ranges, separated by commas
/// or spaces (`1-4, 9, 20-25`; an en dash works too). A reversed range is swapped, not
/// rejected. Out of range, empty, or unparsable input yields an error instead of indices.
({List<int>? indices, String? error}) parseLayerRangeEntry(String text, {required int layerCount}) {
  final tokens = text.replaceAll('–', '-').split(RegExp(r'[,\s]+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return (indices: null, error: 'Enter layer numbers, like 1-4, 9');
  final out = <int>{};
  for (final tok in tokens) {
    final m = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(tok);
    if (m == null) return (indices: null, error: 'Use layer numbers and ranges, like 1-4, 9');
    var lo = int.parse(m.group(1)!);
    var hi = m.group(2) == null ? lo : int.parse(m.group(2)!);
    if (lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    if (lo < 1) return (indices: null, error: 'Layers start at 1 (the bottom layer)');
    if (hi > layerCount) return (indices: null, error: 'Layer $hi is beyond the top layer ($layerCount)');
    for (var k = lo; k <= hi; k++) {
      out.add(k - 1);
    }
  }
  return (indices: out.toList()..sort(), error: null);
}

/// The rigid shift the engine will actually apply: [delta] (positive = toward the top) clamped
/// so no member of the ascending [indices] leaves the stack. Zero means a no-op.
int clampLayerShift(List<int> indices, int delta, int layerCount) {
  if (indices.isEmpty || layerCount <= 0) return 0;
  return delta.clamp(-indices.first, layerCount - 1 - indices.last);
}

/// Whether the ascending [indices] form one unbroken run — what Merge needs.
bool isContiguous(List<int> sorted) => sorted.isNotEmpty && sorted.last - sorted.first + 1 == sorted.length;

/// Where the copies land after `DuplicateLayers`: the member ranked `r` (ascending) at index
/// `i` gets its copy at `i + r + 1`.
List<int> duplicateLayerResultIndices(List<int> sorted) => [for (var r = 0; r < sorted.length; r++) sorted[r] + r + 1];

/// How many of [indices] are locked — the count the Content section's note shows, and the
/// reason a content batch or Merge would refuse.
int lockedCount(List<LayerRow> rows, List<int> indices) {
  var n = 0;
  for (final i in indices) {
    if (i >= 0 && i < rows.length && rows[i].locked) n++;
  }
  return n;
}

/// The payload a content batch over [indices] retains in its undo record (present tiles ×
/// 4096 B, alive until the record is evicted).
int retainedLayerPayloadBytes(List<LayerRow> rows, List<int> indices) {
  var bytes = 0;
  for (final i in indices) {
    if (i >= 0 && i < rows.length) bytes += rows[i].payloadBytes;
  }
  return bytes;
}

/// The by-property selectors of the Select sheet (v1).
enum LayerPick { empty, hidden, visible, locked, unlocked, nonNormal, translucent }

String layerPickLabel(LayerPick p) => switch (p) {
      LayerPick.empty => 'Empty',
      LayerPick.hidden => 'Hidden',
      LayerPick.visible => 'Visible',
      LayerPick.locked => 'Locked',
      LayerPick.unlocked => 'Unlocked',
      LayerPick.nonNormal => 'Non-Normal blend',
      LayerPick.translucent => 'Translucent',
    };

/// The indices (engine order) of the rows a selector matches.
List<int> pickLayers(List<LayerRow> rows, LayerPick pick) {
  bool hit(LayerRow l) => switch (pick) {
        LayerPick.empty => l.isEmpty,
        LayerPick.hidden => !l.visible,
        LayerPick.visible => l.visible,
        LayerPick.locked => l.locked,
        LayerPick.unlocked => !l.locked,
        LayerPick.nonNormal => l.blend != 'Normal',
        LayerPick.translucent => l.opacity < 255,
      };
  return [for (var i = 0; i < rows.length; i++) if (hit(rows[i])) i];
}

/// `{n}` in a rename pattern expands to the member's 1-based rank, TOP first (the engine's
/// rule): [rankFromTop] 1 is the topmost member.
String expandRenamePattern(String pattern, int rankFromTop) => pattern.replaceAll('{n}', '$rankFromTop');

/// The names a rename over [count] members will produce, top first — the dialog's preview.
List<String> renamePreview(String pattern, int count) => [for (var r = 1; r <= count; r++) expandRenamePattern(pattern, r)];

/// The layer name cap the editor's rename dialogs enforce.
const int kLayerNameMaxLength = 64;

/// Strip what would split a DSL statement; the name is the verb's trailing free text.
String sanitizeName(String s) => sanitizeLayerName(s);

/// Whether the stack could take [added] more layers.
bool underLayerCap(int layerCount, int added) => layerCount + added <= kMaxLayers;
