// User Management Dashboard payloads (`GET /api/admin/user/{sqid}/manage`,
// moderator-only, root-mounted like PMD). Mirrors the website's UMD page.

/// The far-future sentinel the server stores for a permanent ban
/// (`PERMANENT_BAN_UNTIL`, year 9999) — NULL must stay readable as "not
/// banned", so permanence is encoded as a date that never arrives.
bool isPermanentBanDate(DateTime d) => d.year >= 9999;

class UmdUserData {
  final int id;
  final String userKey; // UUID
  final String sqid; // public_sqid
  final String handle;
  final String? avatarUrl;
  final int reputation;
  final List<String> badges;
  final bool autoPublicApproval; // "trusted": posts skip the approval queue
  final bool hiddenByMod;
  final DateTime? bannedUntil; // null = not banned; see [isPermanentBanDate]
  final List<String> roles;
  final DateTime? createdAt;

  const UmdUserData({
    required this.id,
    required this.userKey,
    required this.sqid,
    required this.handle,
    this.avatarUrl,
    required this.reputation,
    this.badges = const [],
    required this.autoPublicApproval,
    required this.hiddenByMod,
    this.bannedUntil,
    this.roles = const [],
    this.createdAt,
  });

  /// Banned right now (an expired temporary ban reads as not banned, matching
  /// the server's authentication-time check).
  bool get isBanned => bannedUntil != null && bannedUntil!.isAfter(DateTime.now().toUtc());

  bool get isPermanentlyBanned => bannedUntil != null && isPermanentBanDate(bannedUntil!);

  factory UmdUserData.fromJson(Map<String, dynamic> j) => UmdUserData(
        id: (j['id'] as num?)?.toInt() ?? 0,
        userKey: (j['user_key'] ?? '').toString(),
        sqid: (j['public_sqid'] ?? '').toString(),
        handle: (j['handle'] ?? 'unknown').toString(),
        avatarUrl: j['avatar_url'] as String?,
        reputation: (j['reputation'] as num?)?.toInt() ?? 0,
        badges: (j['badges'] as List?)
                ?.map((e) => ((e as Map)['badge'] ?? '').toString())
                .where((b) => b.isNotEmpty)
                .toList() ??
            const [],
        autoPublicApproval: j['auto_public_approval'] == true,
        hiddenByMod: j['hidden_by_mod'] == true,
        bannedUntil: DateTime.tryParse((j['banned_until'] ?? '').toString()),
        roles: (j['roles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      );
}
