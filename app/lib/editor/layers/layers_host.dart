// What the Layers page needs from the editor (ADR 0033), behind an interface so the page and
// its tests run without the engine: the active frame's stack, the active target, the batch-verb
// runner, undo/redo, per-layer thumbnails and hashes, and the single-layer sheet. The editor
// implements it in `editor_page.layers.dart`; `app/test/layers_test_support.dart` fakes it.

import 'dart:typed_data';

import 'layer_model.dart';

abstract class LayersHost {
  /// The active frame's layers in engine order (bottom first), re-read after every [run],
  /// [undo], [redo], and sheet.
  List<LayerRow> get layers;

  int get activeLayerIndex;

  int get activeFrameIndex;

  int get frameCount;

  ({int w, int h}) get canvasSize;

  bool get canUndo;
  bool get canRedo;

  /// The editor's engine-traffic stamp: any verb bumps it, which disarms a pending Delete.
  int get sendSeq;

  /// Send one batch verb through the editor (drafts die, playback pauses, journal, autosave,
  /// state refresh). Returns the engine's refusal text when the verb was refused, else `null`.
  String? run(String dsl);

  void undo();
  void redo();

  /// Straight-RGBA thumbnail bytes of layer [index] of the active frame (`tw × th × 4`), empty
  /// on failure. The engine samples the layer alone — no composite.
  Uint8List thumbBytes(int index, int tw, int th);

  /// The layer's pixel hash (memoized engine-side, cheap to ask per visible row).
  int layerHash(int index);

  /// Open the editor's single-layer sheet for [index]; completes when it closes.
  Future<void> openLayerSheet(int index);
}

/// What the page pops with: activate one layer (double-tap / Enter / the row menu), or hand the
/// selection to the Move group; `null` for a plain close.
class LayersPageResult {
  const LayersPageResult.activate(int index)
      : activateIndex = index,
        moveGroup = null;
  const LayersPageResult.moveGroup(List<int> indices)
      : activateIndex = null,
        moveGroup = indices;

  final int? activateIndex;

  /// Ascending engine indices of the layers to move together (the first becomes active).
  final List<int>? moveGroup;
}
