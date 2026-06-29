import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/player_providers.dart';

/// Observes the nested Club Navigator (registered in `ClubPillar`) so [SendTargetBinder] can
/// re-assert its page's send target whenever that page becomes visible again — e.g. after a
/// covering route (artwork detail, search) is popped.
final RouteObserver<PageRoute<dynamic>> clubRouteObserver = RouteObserver<PageRoute<dynamic>>();

/// Wrap a Club page's body in this to declare what "Send to Player" should target while that page
/// is the visible route. It writes [target] into [playerSendTargetProvider] on first show, on each
/// reveal (`didPopNext`), and whenever [target] changes (feed swipe, artwork load). Pass a null
/// [target] to disable sending on that page (e.g. the Following feed has no player channel).
class SendTargetBinder extends ConsumerStatefulWidget {
  final PlayerSendTarget? target;
  final Widget child;
  const SendTargetBinder({super.key, required this.target, required this.child});

  @override
  ConsumerState<SendTargetBinder> createState() => _SendTargetBinderState();
}

class _SendTargetBinderState extends ConsumerState<SendTargetBinder> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    // Idempotent: re-subscribing the same (route, aware) pair is a no-op and won't re-fire didPush.
    if (route is PageRoute) clubRouteObserver.subscribe(this, route);
  }

  @override
  void didUpdateWidget(covariant SendTargetBinder old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) _apply();
  }

  /// Provider mutation can't happen during build, so defer to after the frame.
  void _apply() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(playerSendTargetProvider.notifier);
      if (notifier.state != widget.target) notifier.state = widget.target;
    });
  }

  @override
  void didPush() => _apply();
  @override
  void didPopNext() => _apply();

  @override
  void dispose() {
    clubRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
