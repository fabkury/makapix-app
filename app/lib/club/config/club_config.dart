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

  /// Versioned REST base — all routers live under `/api/v1`.
  String get apiBase => '$baseUrl/api/v1';

  /// MQTT-over-WebSocket endpoint (used by a later phase for live notifications).
  String get realtimeUrl => switch (env) {
        ClubEnvironment.dev => 'wss://development.makapix.club/mqtt',
        ClubEnvironment.prod => 'wss://makapix.club/mqtt',
      };

  // ---- GitHub OAuth (server-brokered; native custom-scheme return leg) ----

  // NOTE — accepted legacy: the `.editor` token below is retained intentionally. It matches
  // the Android applicationId (the installed-app identity) and the server OAuth allowlist
  // byte-for-byte, so it is NOT renamed alongside the desktop binary (makapix_editor →
  // makapix_club). It persists until an indeterminate, server-coordinated future migration.

  /// Custom scheme the app registers for the web-auth callback (Android manifest).
  static const String oauthScheme = 'club.makapix.editor';

  /// The exact redirect URI allowlisted server-side (must match byte-for-byte).
  static const String oauthRedirectUri = 'club.makapix.editor://oauth/github';
}
