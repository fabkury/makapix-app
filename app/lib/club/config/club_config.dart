/// Environment + endpoint configuration for the Makapix Club API.
///
/// The app and the makapix.club website are independent clients of the same
/// server (SPEC-CLUB). Caddy strips a leading `/api`, so the versioned REST base
/// is `{baseUrl}/api/v1`.
enum ClubEnvironment { dev, prod }

class ClubConfig {
  final ClubEnvironment env;
  const ClubConfig(this.env);

  /// Selected at build time via `--dart-define=CLUB_ENV=prod` (defaults to `dev` for local and
  /// internal-testing builds) so a release can't silently ship pointing at the dev server. [F-8]
  static const String _envName = String.fromEnvironment('CLUB_ENV', defaultValue: 'dev');
  static const ClubConfig defaultConfig =
      ClubConfig(_envName == 'prod' ? ClubEnvironment.prod : ClubEnvironment.dev);

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

  // ---- GitHub OAuth (server-brokered; HTTPS App Link return leg) ----

  // The OAuth return uses a verified **HTTPS App Link** on a dedicated host (distinct from the
  // API host to avoid the same-origin App Links trap), so Android opens the app directly — no
  // chooser, no lingering browser tab. The custom scheme is a fallback, kept allowlisted
  // server-side during the cutover. App id migrated club.makapix.editor → club.makapix.app
  // (2026-06-30), so the scheme + applicationId + assetlinks package_name all use the new id.

  /// callbackUrlScheme passed to flutter_web_auth_2 — `https` (matches the App Link).
  static const String oauthCallbackScheme = 'https';

  /// Custom-scheme fallback the app registers (Android manifest); matches applicationId.
  static const String oauthScheme = 'club.makapix.app';

  /// The exact redirect URI sent to `/auth/github/login` and captured on return — a
  /// per-environment HTTPS App Link, allowlisted server-side (must match byte-for-byte).
  String get oauthRedirectUri => switch (env) {
        ClubEnvironment.dev => 'https://app-dev.makapix.club/oauth/github',
        ClubEnvironment.prod => 'https://app.makapix.club/oauth/github',
      };

  /// The custom-scheme fallback redirect (also allowlisted server-side during cutover).
  static const String oauthCustomRedirectUri = 'club.makapix.app://oauth/github';
}
