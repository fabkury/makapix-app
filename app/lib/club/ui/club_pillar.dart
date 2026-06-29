import 'package:flutter/material.dart';

import 'club_home_page.dart';
import 'widgets/player_bar.dart';
import 'widgets/send_target_binder.dart';

/// Hosts the Club pillar: a nested [Navigator] (so every Club route — home, artwork detail,
/// search, profile — stays below) with the persistent [PlayerBar] pinned underneath. Scoping the
/// bar here, rather than in `AppShell`, guarantees it can never appear on the editor pillar
/// (`AppShell` mounts exactly one pillar at a time).
///
/// The outer [SafeArea] consumes the bottom inset once for both the nested content and the bar.
class ClubPillar extends StatefulWidget {
  const ClubPillar({super.key});

  @override
  State<ClubPillar> createState() => _ClubPillarState();
}

class _ClubPillarState extends State<ClubPillar> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  late final _NavObserver _observer = _NavObserver(_syncCanPop);
  bool _canPopNested = false;

  void _syncCanPop() {
    if (!mounted) return;
    final canPop = _navKey.currentState?.canPop() ?? false;
    if (canPop != _canPopNested) setState(() => _canPopNested = canPop);
  }

  @override
  Widget build(BuildContext context) {
    // When the nested stack has pushed routes, intercept Android back to pop it. At the Club home
    // root, allow the pop to bubble to AppShell (which lets the system handle it → exit app).
    return PopScope(
      canPop: !_canPopNested,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _navKey.currentState?.maybePop();
      },
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Navigator(
                key: _navKey,
                observers: [_observer, clubRouteObserver],
                onGenerateRoute: (settings) => MaterialPageRoute(
                  builder: (_) => const ClubHomePage(),
                  settings: settings,
                ),
              ),
            ),
            const PlayerBar(),
          ],
        ),
      ),
    );
  }
}

/// Rebuilds the [PopScope]'s `canPop` whenever the nested stack changes depth.
class _NavObserver extends NavigatorObserver {
  final VoidCallback onChanged;
  _NavObserver(this.onChanged);

  void _schedule() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _schedule();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _schedule();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _schedule();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _schedule();
}
