// The neutral top-level shell hosting the app's two co-equal pillars: the **Club**
// social layer (the launch experience) and the **Editor** (the animated pixel-art
// editor). Neither pillar is "the app" — this shell hosts both as peers.
//
// The app opens on the Club pillar (signed-out users land on Club's own welcome /
// sign-in funnel). There is no persistent pillar-switching chrome (no bottom bar / rail):
// navigation is in-content — the Club's top-bar "Contribute" button opens the editor (also
// available, without signing in, on the welcome page), and the editor's ☰ menu → "Club"
// returns to the hub.
//
// Only the ACTIVE pillar is mounted at a time. Keeping both pillar `Scaffold`s mounted
// simultaneously (e.g. via IndexedStack) corrupts the Windows accessibility tree and
// crashes the app on resize ("Failed to update ui::AXTree: Nodes left pending"). Club's
// state survives remounts via its Riverpod providers; the editor preserves its in-progress
// document across switches (and crashes) by autosaving it to the on-disk drawing library
// (see editor_page.persistence.dart) and reloading it on re-entry.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../club/edit/club_edit_request.dart';
import '../club/state/edit_bridge.dart';
import '../club/ui/club_pillar.dart';
import '../editor/editor_page.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    this.clubPillar = const ClubPillar(),
    this.editorPillar = const EditorPage(),
  });

  /// The social pillar (the launch experience). Overridable so tests can mount the
  /// shell without the editor's FFI engine.
  final Widget clubPillar;

  /// The editor pillar (reachable without login via the centre ⊕ Create button).
  final Widget editorPillar;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const int _club = 0, _editor = 1;

  int _index = _club; // launch on the social pillar

  void _select(int i) {
    if (_index != i) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    // Club → editor remix bridge: when a Club page requests an edit, surface the editor
    // pillar. EditorPage's own listener consumes the request (loads the bytes + records
    // provenance) — both fire on the same provider dispatch, so this is race-free even
    // though the editor immediately clears the provider.
    ref.listen<ClubEditRequest?>(pendingClubEditProvider, (_, next) {
      if (next != null) _select(_editor);
    });
    // Profile → editor: the Private tab (local "My Drawings") asks to open or start a drawing.
    ref.listen<LocalLibraryRequest?>(pendingLocalLibraryProvider, (_, next) {
      if (next != null) _select(_editor);
    });
    // The Club's Contribute button surfaces the editor; the editor's ☰ → Club returns here.
    ref.listen<int>(openEditorProvider, (_, _) => _select(_editor));
    ref.listen<int>(openClubProvider, (_, _) => _select(_club));

    // No pillar-switching chrome — only the active pillar is mounted (each pillar owns its
    // own Scaffold). Keeping both Scaffolds mounted at once crashes the Windows AX bridge.
    //
    // The Club is the app's base screen. When the editor pillar is active, intercept the
    // Android system back so it returns to the Club instead of exiting the app. (Sub-routes
    // pushed on top of the shell — dialogs, pickers, profile pages — pop normally first; this
    // only fires once the editor is at its root with nothing else to pop.)
    final inEditor = _index == _editor;
    return PopScope(
      canPop: !inEditor,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inEditor) _select(_club);
      },
      child: inEditor ? widget.editorPillar : widget.clubPillar,
    );
  }
}
