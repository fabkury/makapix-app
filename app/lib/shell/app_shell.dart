// The neutral top-level shell hosting the app's two co-equal pillars: the **Club**
// social layer (the launch experience) and the **Editor** (the animated pixel-art
// editor). Neither pillar is "the app" — this shell hosts both as peers.
//
// The app opens on the Club pillar (signed-out users land on Club's own welcome /
// sign-in funnel). The editor is always reachable, without signing in, via the
// prominent centre ⊕ Create button.
//
// Only the ACTIVE pillar is mounted at a time. Keeping both pillar `Scaffold`s mounted
// simultaneously (e.g. via IndexedStack) corrupts the Windows accessibility tree and
// crashes the app on resize ("Failed to update ui::AXTree: Nodes left pending"). Club's
// state survives remounts via its Riverpod providers; the editor preserves its in-progress
// document across switches with an [EditorSession] snapshot (see editor_session.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../club/edit/club_edit_request.dart';
import '../club/state/edit_bridge.dart';
import '../club/ui/club_home_page.dart';
import '../editor/editor_page.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    this.clubPillar = const ClubHomePage(),
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
  // Material compact→medium boundary: phones get the bottom bar + docked FAB; wider
  // windows (tablet/desktop) get a navigation rail.
  static const double _kRailBreakpoint = 600;

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
    // The Club top-bar Contribute button bumps this to surface the editor (with its current doc).
    ref.listen<int>(openEditorProvider, (_, _) => _select(_editor));

    return LayoutBuilder(
      builder: (context, constraints) {
        final active = _index == _club ? widget.clubPillar : widget.editorPillar;
        return constraints.maxWidth >= _kRailBreakpoint ? _wide(active) : _narrow(active);
      },
    );
  }

  // Phone: a centre-docked ⊕ Create FAB over a notched bottom bar whose single
  // destination is the Club pillar.
  Widget _narrow(Widget body) {
    return Scaffold(
      body: body,
      floatingActionButton: FloatingActionButton(
        heroTag: 'shell-create',
        tooltip: 'Create',
        onPressed: () => _select(_editor),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Club',
              isSelected: _index == _club,
              onPressed: () => _select(_club),
              icon: const Icon(Icons.public),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  // Tablet/desktop: a navigation rail with the Club destination and a prominent
  // leading Create action.
  Widget _wide(Widget body) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index == _club ? 0 : null,
            onDestinationSelected: (_) => _select(_club),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  FloatingActionButton(
                    heroTag: 'shell-create-rail',
                    tooltip: 'Create',
                    onPressed: () => _select(_editor),
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 4),
                  Text('Create', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.public_outlined),
                selectedIcon: Icon(Icons.public),
                label: Text('Club'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
