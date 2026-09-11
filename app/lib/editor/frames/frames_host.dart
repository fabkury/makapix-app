// What the Frames page needs from the editor (ADR 0031), behind an interface so the page and
// its tests run without the engine: the frame snapshot, the active target, the batch-verb
// runner, undo/redo, thumbnails, and the single-frame sheet. The editor implements it in
// `editor_page.frames.dart`; `app/test/frames_test_support.dart` fakes it.

import 'dart:typed_data';

import 'frame_model.dart';

abstract class FramesHost {
  /// The current `frame_detail`, re-read after every [run], [undo], [redo], and sheet.
  List<FrameInfo> get frames;

  int get activeFrameIndex;

  int get frameCount => frames.length;

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

  /// Straight-RGBA thumbnail bytes of frame [index] (`tw × th × 4`), empty on failure.
  Uint8List thumbBytes(int index, int tw, int th);

  /// The frame's content hash (memoized engine-side, cheap to ask per visible tile).
  int frameHash(int index);

  /// Open the editor's single-frame sheet for [index]; completes when it closes.
  Future<void> openFrameSheet(int index);
}
