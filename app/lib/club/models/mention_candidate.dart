/// Why a candidate is being offered (`GET /user/mention-candidates` → `reason`).
///
/// The server ranks in this order, then by handle. The composer shows the
/// reason as a quiet label so "who is this?" is answerable without leaving the
/// field.
enum MentionReason {
  owner,
  thread,
  following,
  follower,
  search,

  /// A `reason` this build does not know. The server may add tiers within the
  /// contract, so an unknown value must render, not crash.
  unknown;

  static MentionReason fromWire(Object? raw) => switch (raw?.toString()) {
        'owner' => MentionReason.owner,
        'thread' => MentionReason.thread,
        'following' => MentionReason.following,
        'follower' => MentionReason.follower,
        'search' => MentionReason.search,
        _ => MentionReason.unknown,
      };

  /// Short label for the candidate row. Empty means "show nothing", which is
  /// right for a plain search hit and for a tier we do not recognize.
  String get label => switch (this) {
        MentionReason.owner => 'Artist',
        MentionReason.thread => 'In this thread',
        MentionReason.following => 'You follow',
        MentionReason.follower => 'Follows you',
        MentionReason.search => '',
        MentionReason.unknown => '',
      };
}

/// One row of the mention autocomplete list.
class MentionCandidate {
  final String handle;
  final String sqid; // public_sqid
  final String? avatarUrl;
  final MentionReason reason;

  const MentionCandidate({
    required this.handle,
    required this.sqid,
    this.avatarUrl,
    this.reason = MentionReason.unknown,
  });

  factory MentionCandidate.fromJson(Map<String, dynamic> j) => MentionCandidate(
        handle: (j['handle'] ?? '').toString(),
        sqid: (j['public_sqid'] ?? '').toString(),
        avatarUrl: j['avatar_url'] as String?,
        reason: MentionReason.fromWire(j['reason']),
      );

  @override
  String toString() => 'MentionCandidate(@$handle → $sqid, ${reason.name})';
}
