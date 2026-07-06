/// Layers-file (.mkpx) capability from `GET /api/v1/config` → `upload.mkpx`.
/// Absent key or `enabled: false` → feature off: hide the share checkbox,
/// the golden Edit button styling, and every other mkpx affordance.
class MkpxRules {
  final bool enabled;
  final int maxFileBytes;

  const MkpxRules({required this.enabled, required this.maxFileBytes});

  factory MkpxRules.fromJson(Map<String, dynamic>? j) => MkpxRules(
        enabled: (j?['enabled'] as bool?) ?? false,
        maxFileBytes: (j?['max_file_bytes'] as num?)?.toInt() ?? 52428800,
      );

  static const MkpxRules disabled =
      MkpxRules(enabled: false, maxFileBytes: 52428800);
}

/// Upload rules from `GET /api/v1/config` → `upload`. Accepted artwork **sizes** are NOT
/// here — they are hardcoded in `ClubSizeRules` (conformance.dart) by decision; the server
/// re-checks on upload either way.
class UploadRules {
  final List<String> formats;
  final int maxFileBytes;
  final MkpxRules mkpx;

  const UploadRules({
    required this.formats,
    required this.maxFileBytes,
    this.mkpx = MkpxRules.disabled,
  });

  factory UploadRules.fromJson(Map<String, dynamic> j) => UploadRules(
        formats: (j['formats'] as List?)?.map((e) => e.toString()).toList() ??
            const ['png', 'gif', 'webp', 'bmp'],
        maxFileBytes: (j['max_file_bytes'] as num?)?.toInt() ?? 5242880,
        mkpx: MkpxRules.fromJson((j['mkpx'] as Map?)?.cast<String, dynamic>()),
      );
}

/// One selectable report reason from `GET /config` → `moderation.report_reasons`
/// (a `{code, label}` pair). Labels are rendered verbatim from the server; the
/// `code` list may grow within contract v1, so unknown codes flow through
/// untouched (ugc-safety §1 / A6).
class ReportReason {
  final String code;
  final String label;
  const ReportReason({required this.code, required this.label});

  factory ReportReason.fromJson(Map<String, dynamic> j) => ReportReason(
        code: (j['code'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
      );
}

/// UGC-safety capability from `GET /config` → `moderation`. Nullable on
/// [ClubServerConfig] — an absent key means the feature is off everywhere
/// (report/block entries, blocked-users screen, community links, the first-run
/// rules gate). Presence of the key is the launch signal (ugc-safety §1 / D17),
/// same mechanism as `upload.mkpx` and `max_mod_hashtags_per_post`.
class ModerationRules {
  final List<ReportReason> reportReasons;
  final String contactEmail;
  final String guidelinesUrl;
  final String moderationPolicyUrl;
  final int maxBlocksPerUser;

  const ModerationRules({
    required this.reportReasons,
    this.contactEmail = 'acme@makapix.club',
    this.guidelinesUrl = '',
    this.moderationPolicyUrl = '',
    this.maxBlocksPerUser = 1000,
  });

  /// Parse the `moderation` block, or return `null` when the feature is
  /// unavailable. A missing block **or** an empty `report_reasons` list both
  /// read as feature-off (A18): a report form whose submit could never enable
  /// is a worse failure mode than the affordances staying hidden.
  static ModerationRules? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final reasons = (j['report_reasons'] as List?)
            ?.map((e) => ReportReason.fromJson((e as Map).cast<String, dynamic>()))
            .where((r) => r.code.isNotEmpty)
            .toList() ??
        const <ReportReason>[];
    if (reasons.isEmpty) return null;
    return ModerationRules(
      reportReasons: reasons,
      contactEmail: (j['contact_email'] ?? 'acme@makapix.club').toString(),
      guidelinesUrl: (j['guidelines_url'] ?? '').toString(),
      moderationPolicyUrl: (j['moderation_policy_url'] ?? '').toString(),
      maxBlocksPerUser: (j['max_blocks_per_user'] as num?)?.toInt() ?? 1000,
    );
  }
}

/// Server-authoritative client config (`GET /api/v1/config`).
class ClubServerConfig {
  final UploadRules upload;
  final int maxCommentDepth;
  final int maxCommentsPerPost;
  final int maxEmojisPerUserPerPost;
  final int maxHashtagsPerPost;

  /// Moderator-hashtags cap — nullable **on purpose**: `null` means the server
  /// does not have the feature (key absent from `GET /config`), and every
  /// mod-hashtag editor affordance stays hidden. Presence of the key is the
  /// launch signal (contract §2 / D19), same mechanism as `upload.mkpx`.
  final int? maxModHashtagsPerPost;

  /// UGC-safety rules — nullable, no default: `null` = feature off everywhere
  /// (ugc-safety §1 / A5). Presence of the `moderation` block is the gate.
  final ModerationRules? moderation;

  const ClubServerConfig({
    required this.upload,
    this.maxCommentDepth = 2,
    this.maxCommentsPerPost = 1000,
    this.maxEmojisPerUserPerPost = 5,
    this.maxHashtagsPerPost = 64,
    this.maxModHashtagsPerPost,
    this.moderation,
  });

  bool get modHashtagsEnabled => maxModHashtagsPerPost != null;
  bool get moderationEnabled => moderation != null;

  factory ClubServerConfig.fromJson(Map<String, dynamic> j) => ClubServerConfig(
        upload: UploadRules.fromJson((j['upload'] as Map?)?.cast<String, dynamic>() ?? const {}),
        maxCommentDepth: (j['max_comment_depth'] as num?)?.toInt() ?? 2,
        maxCommentsPerPost: (j['max_comments_per_post'] as num?)?.toInt() ?? 1000,
        maxEmojisPerUserPerPost: (j['max_emojis_per_user_per_post'] as num?)?.toInt() ?? 5,
        maxHashtagsPerPost: (j['max_hashtags_per_post'] as num?)?.toInt() ?? 64,
        // No default: absent key must stay null (feature-off), per contract §2.
        maxModHashtagsPerPost: (j['max_mod_hashtags_per_post'] as num?)?.toInt(),
        moderation: ModerationRules.fromJson((j['moderation'] as Map?)?.cast<String, dynamic>()),
      );

  /// Baked-in fallback (mirrors vault.py) for offline / fetch failure.
  static const ClubServerConfig fallback = ClubServerConfig(
    upload: UploadRules(
      formats: ['png', 'gif', 'webp', 'bmp'],
      maxFileBytes: 5242880,
    ),
  );
}
