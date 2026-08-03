// Smoke test for the two-pillar app shell (lib/shell/app_shell.dart): the app opens on
// the Club pillar with the signed-out welcome funnel (no login wall), and the welcome
// page's Contribute button reaches the editor pillar WITHOUT signing in.
//
// Auth and the promoted feed are overridden so the test is deterministic — no
// flutter_secure_storage and no Dio/network. The editor pillar is replaced with a stub so
// the shell can be tested without the editor's native FFI engine (the real EditorPage is
// driven by cargo tests + the `mkpx` harness, and exercised by `./build.ps1 -Run`). We
// assert on the shell's navigation — which pillar is mounted — and on the real Club welcome.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/page.dart' as club;
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/server_config.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/club/state/edit_bridge.dart';
import 'package:makapix_club/club/state/feed_providers.dart';
import 'package:makapix_club/club/state/paged.dart';
import 'package:makapix_club/club/state/publish_providers.dart';
import 'package:makapix_club/shell/app_shell.dart';
import 'package:makapix_club/shell/incoming_files.dart';

/// A signed-out [AuthController] that performs no token load / network.
class _SignedOutAuth extends AuthController {
  _SignedOutAuth._(ClubSession session, ClubConfig cfg)
      : super(session: session, api: ClubApiClient(session), oauth: GithubOAuth(cfg)) {
    state = const AuthState.signedOut();
  }

  factory _SignedOutAuth(ClubConfig cfg) => _SignedOutAuth._(ClubSession(config: cfg), cfg);

  @override
  Future<void> init() async {/* stay signed-out; no token load */}
}

Widget _harness() {
  final cfg = ClubConfig.defaultConfig;
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _SignedOutAuth(cfg)),
      // The welcome screen's "Featured" grid watches the promoted feed — return an empty
      // page synchronously so no network is attempted.
      feedProvider(FeedKind.promoted).overrideWith(
        (ref) => PagedNotifier<Post>((_) async => const club.Page<Post>(items: [])),
      ),
      // The Club root now reads server config (to arm the first-run rules gate) even when
      // signed out — return the offline fallback (moderation off) so no /config network
      // call is made; the gate stays passed, exactly as against a pre-flip server.
      serverConfigProvider.overrideWith((ref) async => ClubServerConfig.fallback),
    ],
    child: const MaterialApp(
      home: AppShell(
        editorPillar: Scaffold(body: Center(child: Text('editor-stub'))),
        animatorPillar: Scaffold(body: Center(child: Text('animator-stub'))),
      ),
    ),
  );
}

// The shell mounts only the active pillar (mounting two Scaffolds at once crashes the
// Windows accessibility bridge), so a stub is in the tree iff its pillar is active.
final _editorShowing = find.text('editor-stub');
final _animatorShowing = find.text('animator-stub');

void main() {
  testWidgets('opens on the Club pillar with the signed-out welcome funnel', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.text('Sign in / Create account'), findsOneWidget,
        reason: 'signed-out users get Club\'s welcome funnel, not a login wall');
    expect(_editorShowing, findsNothing, reason: 'the app launches on the Club pillar');
  });

  testWidgets('the welcome Contribute button reaches the editor without signing in', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    // Contribute on the signed-out welcome top bar opens the editor (no login wall).
    await tester.tap(find.byTooltip('Contribute (open the editor)'));
    await tester.pump();
    expect(_editorShowing, findsOneWidget,
        reason: 'the editor pillar is reachable while signed out');

    // The editor's ☰ → Club returns to the hub. The editor stub has no ☰, so drive the same
    // provider signal the menu item bumps.
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    container.read(openClubProvider.notifier).state++;
    await tester.pump();
    expect(_editorShowing, findsNothing, reason: 'openClubProvider returns to the Club pillar');
  });

  testWidgets('the Animator pillar mounts on its provider signals and returns to Club',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    expect(_animatorShowing, findsNothing, reason: 'the app launches on the Club pillar');

    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));

    // The Contribute hub's Animator card bumps openAnimatorProvider.
    container.read(openAnimatorProvider.notifier).state++;
    await tester.pump();
    expect(_animatorShowing, findsOneWidget,
        reason: 'openAnimatorProvider mounts the Animator pillar');
    expect(_editorShowing, findsNothing, reason: 'only the active pillar is mounted');

    // ☰ → Club returns to the hub.
    container.read(openClubProvider.notifier).state++;
    await tester.pump();
    expect(_animatorShowing, findsNothing);

    // "Animate this" requests travel the pending bridge and also mount the pillar.
    container.read(pendingAnimatorProvider.notifier).state = const AnimateDrawing('dwg_x');
    await tester.pump();
    expect(_animatorShowing, findsOneWidget,
        reason: 'pendingAnimatorProvider mounts the Animator pillar');
  });

  testWidgets('incoming "Open in Makapix" files mount the pillar their type belongs to',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final bytes = Uint8List.fromList([1, 2, 3]);

    // A .mkps scene file lands on the Animator bridge and surfaces that pillar.
    expect(dispatchIncomingFile(container, 'Bouncing ball.mkps', bytes), isTrue);
    await tester.pump();
    expect(_animatorShowing, findsOneWidget,
        reason: 'an incoming scene file mounts the Animator pillar');
    expect(container.read(pendingAnimatorProvider), isA<OpenSceneBytes>());

    // Back to Club, then a .mkpx drawing lands on the editor bridge.
    container.read(pendingAnimatorProvider.notifier).state = null; // the stub never consumes
    container.read(openClubProvider.notifier).state++;
    await tester.pump();
    expect(dispatchIncomingFile(container, 'Sprite.mkpx', bytes), isTrue);
    await tester.pump();
    expect(_editorShowing, findsOneWidget,
        reason: 'an incoming drawing file mounts the editor pillar');
    expect(container.read(pendingLocalLibraryProvider), isA<OpenDrawingBytes>());
  });
}
