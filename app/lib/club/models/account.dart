/// Models for the account-lifecycle endpoints (`/auth/register`, the email/
/// password OTP flows, handle checks, and linked logins). Kept separate from the
/// signed-in [ClubMe]/[ClubUser] (which come from `/auth/me`).
library;

/// `POST /auth/register`. With a chosen `password` (A2) the server creates the
/// account with it and emails a single 6-digit OTP (`verification_method: "otp"`);
/// without one it generates + emails a random password and a link
/// (`verification_method: "link"`, the website path). New = 201, resume = 200 —
/// both success.
class RegisterResult {
  final int userId;
  final String email;
  final String handle;

  /// `"otp"` → the server emailed a code and accepted our chosen password (skip
  /// the separate OTP request + the temp-password sign-in). `"link"` (default for
  /// any caller that omits a password, incl. a non-A2 server that ignored it) →
  /// fall back to the temp-password flow.
  final String verificationMethod;

  const RegisterResult({
    required this.userId,
    required this.email,
    required this.handle,
    this.verificationMethod = 'link',
  });

  factory RegisterResult.fromJson(Map<String, dynamic> j) => RegisterResult(
        userId: (j['user_id'] as num?)?.toInt() ?? 0,
        email: (j['email'] ?? '').toString(),
        handle: (j['handle'] ?? '').toString(),
        verificationMethod: (j['verification_method'] ?? 'link').toString(),
      );

  bool get isOtp => verificationMethod == 'otp';
}

/// `POST /auth/email-otp/verify` → marks the email verified.
class VerifyEmailResult {
  final bool verified;
  final String handle;
  final bool needsWelcome;
  final String? publicSqid;
  const VerifyEmailResult({
    required this.verified,
    required this.handle,
    required this.needsWelcome,
    this.publicSqid,
  });

  factory VerifyEmailResult.fromJson(Map<String, dynamic> j) => VerifyEmailResult(
        verified: j['verified'] == true,
        handle: (j['handle'] ?? '').toString(),
        needsWelcome: j['needs_welcome'] == true,
        publicSqid: j['public_sqid'] as String?,
      );
}

/// `POST /auth/check-handle-availability`.
class HandleAvailability {
  final String handle;
  final bool available;
  final String message;
  const HandleAvailability({required this.handle, required this.available, required this.message});

  factory HandleAvailability.fromJson(Map<String, dynamic> j) => HandleAvailability(
        handle: (j['handle'] ?? '').toString(),
        available: j['available'] == true,
        message: (j['message'] ?? '').toString(),
      );
}

/// One linked authentication method from `GET /auth/providers`.
class AuthIdentity {
  final String id;
  final String provider; // "password" | "github"
  final String? email;
  final String? username; // github metadata, when present
  final DateTime? createdAt;
  const AuthIdentity({
    required this.id,
    required this.provider,
    this.email,
    this.username,
    this.createdAt,
  });

  factory AuthIdentity.fromJson(Map<String, dynamic> j) {
    final meta = (j['provider_metadata'] as Map?)?.cast<String, dynamic>();
    return AuthIdentity(
      id: (j['id'] ?? '').toString(),
      provider: (j['provider'] ?? '').toString(),
      email: j['email'] as String?,
      username: meta?['username'] as String?,
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
    );
  }

  bool get isGithub => provider == 'github';
  bool get isPassword => provider == 'password';

  /// A short human label, e.g. "GitHub (octocat)" or "Email & password".
  String get label => switch (provider) {
        'github' => username != null ? 'GitHub ($username)' : 'GitHub',
        'password' => 'Email & password',
        _ => provider,
      };
}
