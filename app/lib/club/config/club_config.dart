/// Environment + endpoint configuration for the Makapix Club API.
///
/// The app and the makapix.club website are independent clients of the same
/// server (SPEC-CLUB). Caddy strips a leading `/api`, so the versioned REST base
/// is `{baseUrl}/api/v1`.
enum ClubEnvironment { dev, prod }

class ClubConfig {
  final ClubEnvironment env;
  const ClubConfig(this.env);

  /// Selected at build time via `--dart-define=CLUB_ENV=dev`. **Defaults to `prod`** (decided
  /// 2026-07-02): no build — release or otherwise — can point at the dev server by omission;
  /// dev must be asked for explicitly (`./build.ps1 -Dev`, `./build_android.ps1 -Dev`). [F-8]
  static const String _envName = String.fromEnvironment('CLUB_ENV', defaultValue: 'prod');
  static const ClubConfig defaultConfig =
      ClubConfig(_envName == 'dev' ? ClubEnvironment.dev : ClubEnvironment.prod);

  /// Network timeouts applied to every Dio client. Without them a stalled connection (captive
  /// portal, dead server) hangs the request — and the spinner — forever. [audit F-7]
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration ioTimeout = Duration(seconds: 30);

  String get baseUrl => switch (env) {
        ClubEnvironment.dev => 'https://development.makapix.club',
        ClubEnvironment.prod => 'https://makapix.club',
      };

  /// Versioned REST base — most routers live under `/api/v1`.
  String get apiBase => '$baseUrl/api/v1';

  /// Unversioned API root (`/api`). A few routers are mounted outside `/v1` —
  /// notably the Post Management Dashboard (`/api/pmd/*`), which the server groups
  /// with hardware/web-infra surfaces as a separate, unversioned contract.
  String get apiRoot => '$baseUrl/api';

  /// MQTT-over-WebSocket endpoint (used by a later phase for live notifications).
  String get realtimeUrl => switch (env) {
        ClubEnvironment.dev => 'wss://development.makapix.club/mqtt',
        ClubEnvironment.prod => 'wss://makapix.club/mqtt',
      };

  // ---- GitHub OAuth (server-brokered) — return leg differs per environment ----

  // App id migrated club.makapix.editor → club.makapix.app (2026-06-30); the scheme,
  // applicationId, and assetlinks package_name all use the new id. Both the HTTPS App Link
  // and the custom scheme are server-allowlisted.
  //
  // **dev** returns via a verified **HTTPS App Link** (`app-dev.makapix.club`), a *sibling* of
  // the dev API host `development.makapix.club`, so Chrome hands the callback's 302 off to the
  // app cleanly. **prod** must use the **custom scheme**: its App Link host `app.makapix.club`
  // is a *subdomain* of the prod API host `makapix.club`, so Chrome treats the 302 (and even a
  // same-host "Open Makapix" page tap) as same-site and keeps it in the tab — App Links there
  // can't hand off. Custom-scheme links aren't subject to that suppression. (Fixing prod to use
  // App Links would need the app-link host to be cross-host from the callback host — a server
  // topology change; the custom scheme is the pragmatic, app-only fix.)

  /// Sign in with Apple (iOS, Apple guideline 4.8). ON since 2026-07-09: the server
  /// `apple_identity_token` grant is live on dev (server msg 0002 in
  /// docs/apple-signin/, contract in docs/ios-release/apple-signin-server.md); the
  /// joint prod flip follows on-device TestFlight verification. The button
  /// additionally self-hides where the native flow is unavailable (non-iOS, or
  /// iOS < 13) via `AppleOAuth.isAvailable()`.
  static const bool kAppleSignInEnabled = true;

  /// Custom scheme the app registers (Android manifest); matches applicationId.
  static const String oauthScheme = 'club.makapix.app';

  /// The custom-scheme return (server-allowlisted).
  static const String oauthCustomRedirectUri = 'club.makapix.app://oauth/github';

  /// The redirect URI sent to `/auth/github/login` and captured on return — the HTTPS App Link
  /// on dev, the custom scheme on prod (see the note above). Server-allowlisted byte-for-byte.
  String get oauthRedirectUri => switch (env) {
        ClubEnvironment.dev => 'https://app-dev.makapix.club/oauth/github',
        ClubEnvironment.prod => oauthCustomRedirectUri,
      };

  /// callbackUrlScheme passed to flutter_web_auth_2 — must equal the **scheme** of the captured
  /// return URL (the plugin keys pending callbacks by `Uri.scheme`): `https` for the dev App
  /// Link, the custom scheme for the prod custom-scheme return.
  String get oauthCallbackScheme => switch (env) {
        ClubEnvironment.dev => 'https',
        ClubEnvironment.prod => oauthScheme,
      };
}
