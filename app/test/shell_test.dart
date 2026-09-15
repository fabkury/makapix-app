// Smoke test for the two-pillar app shell (lib/shell/app_shell.dart): the app opens on
// the Club pillar with the signed-out welcome funnel (no login wall), and the welcome
// page's Contribute button reaches the editor pillar WITHOUT signing in.
//
// Auth and the promoted feed are overridden so the test is deterministic — no
// flutter_secure_storage and no Dio/network. The editor pillar is replaced with a stub so
// the shell can be tested without the editor's native FFI engine (the real EditorPage is
// driven by cargo tests + the `mkpx` harness, and exercised by `./build.ps1 -Run`). We
// assert on the shell's navigation — which pillar is mounted — and on the real Club welcome.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// An [AuthController] stuck in `AuthStatus.loading` — the sign-in state still resolving (the
/// elevator case: a `/auth/me` or Zero-Tap round trip that never answers).
class _LoadingAuth extends AuthController {
  _LoadingAuth._(ClubSession session, ClubConfig cfg)
      : super(session: session, api: ClubApiClient(session), oauth: GithubOAuth(cfg));

  factory _LoadingAuth(ClubConfig cfg) => _LoadingAuth._(ClubSession(config: cfg), cfg);

  @override
  Future<void> init() async {/* never resolves */}
}

Widget _harness({bool resolving = false, AppPillar launch = AppPillar.club}) {
  final cfg = ClubConfig.defaultConfig;
  return ProviderScope(
    overrides: [
      launchPillarProvider.overrideWithValue(launch),
      authControllerProvider
          .overrideWith((ref) => resolving ? _LoadingAuth(cfg) : _SignedOutAuth(cfg)),
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
      ),
    ),
  );
}

// The shell mounts only the active pillar (mounting both Scaffolds at once crashes the
// Windows accessibility bridge), so the editor stub is in the tree iff the editor is active.
final _editorShowing = find.text('editor-stub');

void main() {
  // The shell stamps the launch pillar into shared preferences on mount (launch_pillar.dart);
  // give it an in-memory store so no platform channel is touched.
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  testWidgets('while the sign-in state is still resolving, the editor is one tap away',
      (tester) async {
    await tester.pumpWidget(_harness(resolving: true));
    await tester.pump();

    // Not a blocking spinner: the resolving surface carries the same no-login top bar.
    expect(find.text('Connecting to Makapix Club…'), findsOneWidget);
    expect(_editorShowing, findsNothing);
    await tester.tap(find.byTooltip('Contribute (open the editor)'));
    await tester.pump();
    expect(_editorShowing, findsOneWidget,
        reason: 'the Makapix Editor is promised offline — nothing on the launch path may wait '
            'on the network');
  });

  // "My Drawings" opens the editor with a browse-the-library request (consumed on the editor's
  // mount; the stub here leaves it pending, which is what we assert). One test per surface: a
  // second pumpWidget would reuse the shell's State (same type, same slot) and its mounted pillar.
  Future<void> expectMyDrawingsReachesTheEditor(WidgetTester tester, {required bool resolving}) async {
    await tester.pumpWidget(_harness(resolving: resolving));
    await tester.pump();
    await tester.tap(find.text('My Drawings'));
    await tester.pump();
    expect(_editorShowing, findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    expect(container.read(pendingLocalLibraryProvider), isA<BrowseLocalLibrary>());
  }

  testWidgets('launches straight into the editor when the launch pillar says so (ADR 0035)',
      (tester) async {
    await tester.pumpWidget(_harness(launch: AppPillar.editor));
    await tester.pump();
    expect(_editorShowing, findsOneWidget, reason: 'a recent editor session lands in the editor');
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    expect(container.read(activePillarProvider), AppPillar.editor,
        reason: 'pillar-gated providers see the editor as mounted from the first frame');
    // The editor's ☰ → Club still returns to the hub.
    container.read(openClubProvider.notifier).state++;
    await tester.pump();
    expect(_editorShowing, findsNothing);
    expect(container.read(activePillarProvider), AppPillar.club);
  });

  testWidgets('"My Drawings" on the welcome page reaches the editor without signing in',
      (tester) => expectMyDrawingsReachesTheEditor(tester, resolving: false));

  testWidgets('"My Drawings" on the resolving page reaches the editor without signing in',
      (tester) => expectMyDrawingsReachesTheEditor(tester, resolving: true));
}
