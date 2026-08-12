// The player poll's pillar + lifecycle gating (battery F8): the 15 s timer runs only
// while the app is foreground AND the Club pillar is mounted. Engine-free, network-free
// (signed-out auth short-circuits refresh() before any HTTP).
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/club/state/edit_bridge.dart';
import 'package:makapix_club/club/state/player_providers.dart';

/// A signed-out [AuthController] that performs no token load / network
/// (mirrors shell_test.dart).
class _SignedOutAuth extends AuthController {
  _SignedOutAuth._(ClubSession session, ClubConfig cfg)
      : super(session: session, api: ClubApiClient(session), oauth: GithubOAuth(cfg)) {
    state = const AuthState.signedOut();
  }

  factory _SignedOutAuth(ClubConfig cfg) => _SignedOutAuth._(ClubSession(config: cfg), cfg);

  @override
  Future<void> init() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() {
    final c = ProviderContainer(overrides: [
      authControllerProvider
          .overrideWith((ref) => _SignedOutAuth(ClubConfig.defaultConfig)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('poll runs on the Club pillar and stops while the editor is mounted', () {
    final c = makeContainer();
    final ctrl = c.read(playerControllerProvider.notifier);
    expect(ctrl.pollingActive, isTrue, reason: 'launch = Club pillar, foreground');

    c.read(activePillarProvider.notifier).state = AppPillar.editor;
    expect(ctrl.pollingActive, isFalse, reason: 'no poll while the bar is unmounted');

    c.read(activePillarProvider.notifier).state = AppPillar.club;
    expect(ctrl.pollingActive, isTrue, reason: 'poll resumes on pillar return');
  });

  test('poll stops while backgrounded and resumes on foreground', () {
    final c = makeContainer();
    final ctrl = c.read(playerControllerProvider.notifier);
    expect(ctrl.pollingActive, isTrue);

    ctrl.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(ctrl.pollingActive, isFalse, reason: 'no network polling in the background');

    // `inactive` counts as foreground (desktop focus loss — house style).
    ctrl.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(ctrl.pollingActive, isTrue);
  });

  test('backgrounded-in-editor stays stopped after foregrounding into the editor', () {
    final c = makeContainer();
    final ctrl = c.read(playerControllerProvider.notifier);
    c.read(activePillarProvider.notifier).state = AppPillar.editor;
    ctrl.didChangeAppLifecycleState(AppLifecycleState.paused);
    ctrl.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(ctrl.pollingActive, isFalse, reason: 'editor pillar still gates the poll');
  });
}
