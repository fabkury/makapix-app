// The neutral top-level shell hosting the app's co-equal pillars: the **Club** social layer
// (the launch experience), the **Editor** (the animated pixel-art editor), and the
// **Animator** (the scene/keyframe animation tool). No pillar is "the app" — this shell
// hosts them as peers.
//
// The app opens on the Club pillar (signed-out users land on Club's own welcome / sign-in
// funnel). There is no persistent pillar-switching chrome (no bottom bar / rail): navigation
// is in-content — the Club's Contribute surfaces open the editor or the Animator, and each
// creative pillar's ☰ menu → "Club" returns to the hub.
//
// Only the ACTIVE pillar is mounted at a time. Keeping two pillar `Scaffold`s mounted
// simultaneously (e.g. via IndexedStack) corrupts the Windows accessibility tree and
// crashes the app on resize ("Failed to update ui::AXTree: Nodes left pending"). Club's
// state survives remounts via its Riverpod providers; the creative pillars preserve their
// in-progress documents across switches (and crashes) by autosaving to their on-disk
// libraries and reloading on re-entry.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../animator/animator_page.dart';
import '../club/edit/club_edit_request.dart';
import '../club/state/edit_bridge.dart';
import '../club/ui/club_pillar.dart';
import '../editor/editor_page.dart';
import 'incoming_files.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    this.clubPillar = const ClubPillar(),
    this.editorPillar = const EditorPage(),
    this.animatorPillar = const AnimatorPage(),
  });

  /// The social pillar (the launch experience). Overridable so tests can mount the
  /// shell without the creative pillars' FFI engines.
  final Widget clubPillar;

  /// The editor pillar (reachable without login via the Contribute surfaces).
  final Widget editorPillar;

  /// The Animator pillar (reachable without login via the Contribute hub).
  final Widget animatorPillar;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const int _club = 0, _editor = 1, _animator = 2;

  int _index = _club; // launch on the social pillar

  void _select(int i) {
    if (_index != i) setState(() => _index = i);
  }

  @override
  void initState() {
    super.initState();
    // "Open in Makapix": documents the OS hands the app route onto the same pending
    // bridges as in-app requests; the listeners in build() then switch pillars.
    IncomingFiles.attach(_onIncomingFile);
  }

  @override
  void dispose() {
    IncomingFiles.detach();
    super.dispose();
  }

  void _onIncomingFile(String name, Uint8List bytes) {
    if (!mounted) return;
    dispatchIncomingFile(ProviderScope.containerOf(context, listen: false), name, bytes);
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
    // → Animator: "Animate this" / gallery / new-scene requests (consumed on mount, same
    // two-listener pattern as the editor bridges).
    ref.listen<AnimatorRequest?>(pendingAnimatorProvider, (_, next) {
      if (next != null) _select(_animator);
    });
    // Contribute buttons surface the creative pillars; their ☰ → Club returns here.
    ref.listen<int>(openEditorProvider, (_, _) => _select(_editor));
    ref.listen<int>(openAnimatorProvider, (_, _) => _select(_animator));
    ref.listen<int>(openClubProvider, (_, _) => _select(_club));

    // No pillar-switching chrome — only the active pillar is mounted (each pillar owns its
    // own Scaffold). Keeping two Scaffolds mounted at once crashes the Windows AX bridge.
    //
    // The Club is the app's base screen. When a creative pillar is active, intercept the
    // Android system back so it returns to the Club instead of exiting the app. (Sub-routes
    // pushed on top of the shell — dialogs, pickers, profile pages — pop normally first;
    // this only fires once the pillar is at its root with nothing else to pop.)
    final atClub = _index == _club;
    return PopScope(
      canPop: atClub,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !atClub) _select(_club);
      },
      child: switch (_index) {
        _editor => widget.editorPillar,
        _animator => widget.animatorPillar,
        _ => widget.clubPillar,
      },
    );
  }
}
