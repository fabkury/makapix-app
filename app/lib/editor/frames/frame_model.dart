// The Frames page's read model (ADR 0031): a typed view of the engine's `frame_detail` state,
// plus the engine constants the page pre-checks against. Pure Dart — no engine, no widgets —
// so the page's model and its tests run without the binary.

/// The engine's frame cap (`document::MAX_FRAMES`).
const int kMaxFrames = 1024;

/// The engine's per-frame layer cap (`document::MAX_LAYERS`; 64 until 2026-09-14, ADR 0032).
const int kMaxLayers = 128;

/// The engine's duration range in microseconds (`MIN_DURATION_US` … `MAX_DURATION_US`).
const int kMinDurationUs = 16667;
const int kMaxDurationUs = 1000000;

/// The duration a blank frame is born with (`DEFAULT_DURATION_US`).
const int kDefaultDurationUs = 100000;

/// One tile's payload in bytes (32 × 32 × RGBA) — the unit `present_tiles` counts.
const int kTileBytes = 4096;

int clampDurationUs(int us) => us.clamp(kMinDurationUs, kMaxDurationUs);

/// One layer of one frame, as `frame_detail` reports it.
class LayerInfo {
  const LayerInfo({required this.name, this.visible = true, this.locked = false, this.presentTiles = 0});

  final String name;
  final bool visible;
  final bool locked;

  /// Materialized 32×32 tiles — the layer's payload in [kTileBytes] units.
  final int presentTiles;
}

/// One frame, as `frame_detail` reports it. The [id] is the engine's stable frame identity:
/// the page's selection is held by id, never by index (ADR 0013 / 0031).
class FrameInfo {
  const FrameInfo({required this.id, this.durationUs = kDefaultDurationUs, this.activeLayer = 0, this.layers = const []});

  final int id;
  final int durationUs;
  final int activeLayer;
  final List<LayerInfo> layers;

  double get durationMs => durationUs / 1000.0;

  /// Bytes the frame's layers hold (present tiles × 4096).
  int get payloadBytes => layers.fold(0, (a, l) => a + l.presentTiles * kTileBytes);
}

/// Parse the engine's `frame_detail` array. Tolerant: a missing or malformed entry falls back
/// to defaults (an id of the index, the default duration) so a partial state never throws.
List<FrameInfo> parseFrameDetail(List<dynamic>? raw) {
  if (raw == null) return const [];
  final out = <FrameInfo>[];
  for (var i = 0; i < raw.length; i++) {
    final f = raw[i];
    if (f is! Map) {
      out.add(FrameInfo(id: i));
      continue;
    }
    final layersRaw = f['layers'];
    final layers = <LayerInfo>[];
    if (layersRaw is List) {
      for (final l in layersRaw) {
        if (l is! Map) continue;
        layers.add(LayerInfo(
          name: (l['name'] as String?) ?? '',
          visible: (l['visible'] as bool?) ?? true,
          locked: (l['locked'] as bool?) ?? false,
          presentTiles: ((l['present_tiles'] as num?) ?? 0).toInt(),
        ));
      }
    }
    out.add(FrameInfo(
      id: ((f['id'] as num?) ?? i).toInt(),
      durationUs: ((f['duration_us'] as num?) ?? kDefaultDurationUs).toInt(),
      activeLayer: ((f['active_layer'] as num?) ?? 0).toInt(),
      layers: layers,
    ));
  }
  return out;
}
