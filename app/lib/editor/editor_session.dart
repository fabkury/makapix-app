import 'dart:typed_data';

/// Session-scoped holder that lets the editor's in-progress artwork survive being
/// unmounted and remounted.
///
/// The app shell mounts only one pillar at a time (mounting both pillar `Scaffold`s at
/// once crashes the Windows accessibility bridge — see `lib/shell/app_shell.dart`), so
/// leaving the editor for Club and returning destroys and recreates `EditorPage`'s state.
/// To avoid losing work, `EditorPage` snapshots its document here as lossless `.mkpx`
/// bytes on dispose and restores it on the next init. Club needs no equivalent — its
/// state lives in long-lived Riverpod providers.
class EditorSession {
  EditorSession._();

  /// The most recent editor document as `.mkpx` bytes, or null if the editor has never
  /// been left (or the snapshot failed). Held statically because the engine/document is
  /// effectively a single per-process session.
  static Uint8List? docSnapshot;
}
