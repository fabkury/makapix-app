/// One entry in `GET /v1/me/blocks` — a user the caller has blocked.
class BlockedUser {
  final String publicSqid;
  final String handle;
  final String? avatarUrl;
  final DateTime? blockedAt;

  const BlockedUser({
    required this.publicSqid,
    required this.handle,
    required this.avatarUrl,
    required this.blockedAt,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
        publicSqid: (j['public_sqid'] ?? '').toString(),
        handle: (j['handle'] ?? 'unknown').toString(),
        avatarUrl: j['avatar_url'] as String?,
        blockedAt: DateTime.tryParse((j['blocked_at'] ?? '').toString()),
      );
}
