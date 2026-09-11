// Frame-set helpers (ADR 0031): the wire form the batch verbs take, the 1-based forms people
// type and read, the selection helpers (Every Nth), the shift clamp, the post-batch selection
// formulas, and the pre-checks the page shows before a tap. Pure Dart, tested without the
// engine; every rule here mirrors `crates/engine/src/session/frames.rs`.

import 'frame_model.dart';

/// The canonical 0-based wire form: sorted, deduplicated, coalesced into maximal inclusive
/// ranges, space-separated — `12-32 40`. The engine accepts any order; the shell always emits
/// this one so journals read the same everywhere.
String formatFrameSet(Iterable<int> indices) {
  final sorted = indices.toSet().toList()..sort();
  final parts = <String>[];
  var i = 0;
  while (i < sorted.length) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    parts.add(j == i ? '${sorted[i]}' : '${sorted[i]}-${sorted[j]}');
    i = j + 1;
  }
  return parts.join(' ');
}

/// The 1-based human form for labels: `13–33, 41`.
String formatFrameSetHuman(Iterable<int> indices) {
  final sorted = indices.toSet().toList()..sort();
  final parts = <String>[];
  var i = 0;
  while (i < sorted.length) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    parts.add(j == i ? '${sorted[i] + 1}' : '${sorted[i] + 1}–${sorted[j] + 1}');
    i = j + 1;
  }
  return parts.join(', ');
}

/// Parse the Range entry: 1-based frame numbers and ranges, separated by commas or spaces
/// (`1-12, 20, 30-40`; an en dash works too). A reversed range is swapped, not rejected. Out of
/// range, empty, or unparsable input yields an error message instead of indices.
({List<int>? indices, String? error}) parseFrameRangeEntry(String text, {required int frameCount}) {
  final tokens = text.replaceAll('–', '-').split(RegExp(r'[,\s]+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return (indices: null, error: 'Enter frame numbers, like 1-12, 20');
  final out = <int>{};
  for (final tok in tokens) {
    final m = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(tok);
    if (m == null) return (indices: null, error: 'Use frame numbers and ranges, like 1-12, 20');
    var lo = int.parse(m.group(1)!);
    var hi = m.group(2) == null ? lo : int.parse(m.group(2)!);
    if (lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    if (lo < 1) return (indices: null, error: 'Frames start at 1');
    if (hi > frameCount) return (indices: null, error: 'Frame $hi is beyond the last frame ($frameCount)');
    for (var k = lo; k <= hi; k++) {
      out.add(k - 1);
    }
  }
  return (indices: out.toList()..sort(), error: null);
}

/// Every Nth member of [base] (in roll order), starting at [offset] (0-based within the base):
/// keeps `base[i]` where `i >= offset` and `(i - offset) % n == 0`.
List<int> everyNth(List<int> base, {required int n, required int offset}) {
  if (n < 1) n = 1;
  final off = offset.clamp(0, n - 1);
  final out = <int>[];
  for (var i = off; i < base.length; i += n) {
    out.add(base[i]);
  }
  return out;
}

/// The rigid shift the engine will actually apply: [delta] clamped so no member of the
/// (ascending) [indices] leaves the roll. Zero means the nudge is a no-op.
int clampShift(List<int> indices, int delta, int frameCount) {
  if (indices.isEmpty || frameCount <= 0) return 0;
  final first = indices.first;
  final last = indices.last;
  return delta.clamp(-first, frameCount - 1 - last);
}

/// Where the copies land after `DuplicateFrames`: the member ranked `r` (ascending) at index
/// `i` gets its copy at `i + r + 1`.
List<int> duplicateResultIndices(List<int> sorted) => [for (var r = 0; r < sorted.length; r++) sorted[r] + r + 1];

/// Where the block lands after `RepeatFramesAfter`: right after the last member.
List<int> repeatResultIndices(List<int> sorted) {
  if (sorted.isEmpty) return const [];
  final start = sorted.last + 1;
  return [for (var r = 0; r < sorted.length; r++) start + r];
}

/// How many members `SetFrameDurations(S, requested)` pins at the floor or ceiling: all of them
/// when the request itself clamps, else none.
int pinnedCountForSet(List<int> indices, int requestedUs) =>
    clampDurationUs(requestedUs) == requestedUs ? 0 : indices.length;

/// How many members `ScaleFrameDurations(S, permille)` pins — the engine's own integer math.
int pinnedCountForScale(List<FrameInfo> frames, List<int> indices, int permille) {
  var pinned = 0;
  for (final i in indices) {
    if (i < 0 || i >= frames.length) continue;
    final us = frames[i].durationUs;
    final scaled = (us * permille + 500) ~/ 1000;
    if (clampDurationUs(scaled) != scaled) pinned++;
  }
  return pinned;
}

/// The payload a content batch over [indices] retains in its undo record: every member's
/// present tiles × 4096 B (the old tiles stay alive in the record until it is evicted).
int retainedPayloadBytes(List<FrameInfo> frames, List<int> indices) {
  var bytes = 0;
  for (final i in indices) {
    if (i >= 0 && i < frames.length) bytes += frames[i].payloadBytes;
  }
  return bytes;
}

/// The layer names present in the selected frames with their hit counts (one hit per frame
/// — the engine acts on the topmost layer of that name), most common first, then by name.
List<({String name, int hits})> layerNameHits(List<FrameInfo> frames, List<int> indices) {
  final counts = <String, int>{};
  for (final i in indices) {
    if (i < 0 || i >= frames.length) continue;
    final names = frames[i].layers.map((l) => l.name).toSet();
    for (final n in names) {
      counts[n] = (counts[n] ?? 0) + 1;
    }
  }
  final out = [for (final e in counts.entries) (name: e.key, hits: e.value)];
  out.sort((a, b) {
    final byHits = b.hits.compareTo(a.hits);
    return byHits != 0 ? byHits : a.name.compareTo(b.name);
  });
  return out;
}

/// `Verb(set[, args…])` — the batch verb line the page sends.
String frameSetDsl(String verb, Iterable<int> indices, [List<String> args = const []]) {
  final set = formatFrameSet(indices);
  return args.isEmpty ? '$verb($set)' : '$verb($set, ${args.join(', ')})';
}

/// Strip what would split a DSL statement (newlines, `;`); commas survive because the name is
/// the trailing free text of its verb.
String sanitizeLayerName(String s) => s.replaceAll(RegExp(r'[\r\n;]'), ' ').trim();
