// Account deletion (App Store guideline 5.1.1(v)): the type-DELETE arming
// gate, the API call + confirmation dialog on 202, local sign-out, and the
// error path. Pure widget tests — no engine, no network.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/club_error.dart';
import 'package:makapix_club/club/models/club_user.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/club/ui/auth/delete_account_page.dart';

/// A [ClubApiClient] whose delete-account call is recorded, never sent.
class _FakeApi extends ClubApiClient {
  int deleteCalls = 0;
  ClubError? failWith;
  _FakeApi() : super(ClubSession(config: ClubConfig.defaultConfig));

  @override
  Future<void> requestAccountDeletion() async {
    deleteCalls++;
    final e = failWith;
    if (e != null) throw e;
  }
}

/// An [AuthController] pre-signed-in, with a local-only logout (no storage).
class _FakeAuth extends AuthController {
  int logouts = 0;
  _FakeAuth._(ClubSession session, ClubConfig cfg, ClubApiClient api)
      : super(session: session, api: api, oauth: GithubOAuth(cfg)) {
    state = AuthState.signedIn(ClubMe(
      user: ClubUser(sub: 'x1', userKey: 'key-x1', handle: 'tester'),
      roles: const [],
      capabilities: const {},
      quotas: const {},
      needsWelcome: false,
    ));
  }

  factory _FakeAuth(ClubApiClient api) {
    final cfg = ClubConfig.defaultConfig;
    return _FakeAuth._(ClubSession(config: cfg), cfg, api);
  }

  @override
  Future<void> init() async {/* stay as constructed */}

  @override
  Future<void> logout() async {
    logouts++;
    state = const AuthState.signedOut();
  }
}

void main() {
  late _FakeApi api;
  late _FakeAuth auth;

  Future<void> pumpPage(WidgetTester t) async {
    api = _FakeApi();
    auth = _FakeAuth(api);
    await t.pumpWidget(ProviderScope(
      overrides: [
        clubApiClientProvider.overrideWithValue(api),
        authControllerProvider.overrideWith((ref) => auth),
      ],
      child: const MaterialApp(home: DeleteAccountPage()),
    ));
  }

  Finder deleteButton() =>
      find.widgetWithText(FilledButton, 'Delete my account');

  bool buttonEnabled(WidgetTester t) =>
      t.widget<FilledButton>(deleteButton()).onPressed != null;

  testWidgets('delete button stays disabled until DELETE is typed exactly',
      (t) async {
    await pumpPage(t);
    expect(buttonEnabled(t), isFalse, reason: 'disabled with an empty field');

    await t.enterText(find.byType(TextField), 'delete');
    await t.pump();
    expect(buttonEnabled(t), isFalse, reason: 'lowercase does not arm it');

    await t.enterText(find.byType(TextField), 'DELETE ME');
    await t.pump();
    expect(buttonEnabled(t), isFalse, reason: 'extra words do not arm it');

    await t.enterText(find.byType(TextField), ' DELETE ');
    await t.pump();
    expect(buttonEnabled(t), isTrue, reason: 'exact word (trimmed) arms it');
    expect(api.deleteCalls, 0, reason: 'arming alone must not call the API');
  });

  testWidgets('armed delete → API called once, confirmation shown, signed out',
      (t) async {
    await pumpPage(t);
    await t.enterText(find.byType(TextField), 'DELETE');
    await t.pump();
    // The 640dp content cap wraps the warning card taller, so the button can sit
    // below the fold of the test viewport — scroll it into view like a user would.
    await t.ensureVisible(deleteButton());
    await t.pump();
    await t.tap(deleteButton());
    // The busy spinner animates while the dialog is up, so pumpAndSettle would
    // never settle — pump bounded frames instead.
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    expect(api.deleteCalls, 1);
    expect(find.text('Account deleted'), findsOneWidget);
    expect(auth.logouts, 0, reason: 'sign-out only after the user confirms');

    await t.tap(find.widgetWithText(FilledButton, 'OK'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(auth.logouts, 1);
    expect(auth.state.isSignedIn, isFalse);
  });

  testWidgets('server error → message shown, no sign-out, no confirmation',
      (t) async {
    await pumpPage(t);
    api.failWith = ClubError(
        status: 403, code: 'forbidden', message: 'Owners cannot delete their account.');
    await t.enterText(find.byType(TextField), 'DELETE');
    await t.pump();
    await t.ensureVisible(deleteButton());
    await t.pump();
    await t.tap(deleteButton());
    await t.pumpAndSettle();

    expect(api.deleteCalls, 1);
    expect(find.text('Account deleted'), findsNothing);
    expect(find.text('Owners cannot delete their account.'), findsOneWidget);
    expect(auth.logouts, 0);
    expect(auth.state.isSignedIn, isTrue);
  });
}
