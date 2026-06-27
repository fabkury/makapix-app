/// Environment + endpoint configuration for the Makapix Club API.
///
/// The app and the makapix.club website are independent clients of the same
/// server (SPEC-CLUB). Caddy strips a leading `/api`, so the versioned REST base
/// is `{baseUrl}/api/v1`.
enum ClubEnvironment { dev, prod }

class ClubConfig {
  final ClubEnvironment env;
  const ClubConfig(this.env);

  /// Default while the social pillar is under development (staging server).
  static const ClubConfig defaultConfig = ClubConfig(ClubEnvironment.dev);

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

  /// Custom scheme the app registers for the web-auth callback (Android manifest).
  static const String oauthScheme = 'club.makapix.editor';

  /// The exact redirect URI allowlisted server-side (must match byte-for-byte).
  static const String oauthRedirectUri = 'club.makapix.editor://oauth/github';
}
