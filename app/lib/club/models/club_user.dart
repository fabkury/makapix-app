/// The signed-in user as returned by `GET /api/v1/auth/me` (the `user` block).
class ClubUser {
  final String sub; // public_sqid (JWT `sub`)
  final String userKey; // UUID — required by `PATCH /user/{user_key}` (resolves by UUID only)
  final String handle;
  final String? avatarUrl;
  final String? email;

  /// Monitored hashtags the user has opted into seeing (content-filter set §21):
  /// a subset of `politics/nsfw/explicit/13plus/violence`. Empty = all hidden.
  final List<String> approvedHashtags;

  ClubUser({
    required this.sub,
    required this.userKey,
    required this.handle,
    this.avatarUrl,
    this.email,
    this.approvedHashtags = const [],
  });

  factory ClubUser.fromJson(Map<String, dynamic> j) => ClubUser(
        sub: (j['public_sqid'] ?? j['sub'] ?? j['id'] ?? '').toString(),
        userKey: (j['user_key'] ?? '').toString(),
        handle: (j['handle'] ?? 'unknown').toString(),
        avatarUrl: j['avatar_url'] as String?,
        email: j['email'] as String?,
        approvedHashtags:
            (j['approved_hashtags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  ClubUser copyWith({List<String>? approvedHashtags}) => ClubUser(
        sub: sub,
        userKey: userKey,
        handle: handle,
        avatarUrl: avatarUrl,
        email: email,
        approvedHashtags: approvedHashtags ?? this.approvedHashtags,
      );
}

/// `GET /api/v1/auth/me`: user + roles + capabilities/quotas + onboarding flag.
/// `capabilities`/`quotas` are kept as raw maps for now (display only); they get
/// typed when UI gating needs them (brief §3.5).
class ClubMe {
  final ClubUser user;
  final List<String> roles;
  final Map<String, dynamic> capabilities;
  final Map<String, dynamic> quotas;
  final bool needsWelcome;

  ClubMe({
    required this.user,
    required this.roles,
    required this.capabilities,
    required this.quotas,
    required this.needsWelcome,
  });

  factory ClubMe.fromJson(Map<String, dynamic> j) {
    // Tolerate either { user: {...}, roles, ... } or a flat user object.
    final userJson = (j['user'] as Map?)?.cast<String, dynamic>() ?? j;
    return ClubMe(
      user: ClubUser.fromJson(userJson),
      roles: (j['roles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      capabilities: (j['capabilities'] as Map?)?.cast<String, dynamic>() ?? const {},
      quotas: (j['quotas'] as Map?)?.cast<String, dynamic>() ?? const {},
      needsWelcome: j['needs_welcome'] == true,
    );
  }

  bool get canModerate => roles.contains('moderator') || roles.contains('owner');

  ClubMe copyWith({ClubUser? user}) => ClubMe(
        user: user ?? this.user,
        roles: roles,
        capabilities: capabilities,
        quotas: quotas,
        needsWelcome: needsWelcome,
      );
}
