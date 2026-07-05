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

  const ClubServerConfig({
    required this.upload,
    this.maxCommentDepth = 2,
    this.maxCommentsPerPost = 1000,
    this.maxEmojisPerUserPerPost = 5,
    this.maxHashtagsPerPost = 64,
    this.maxModHashtagsPerPost,
  });

  bool get modHashtagsEnabled => maxModHashtagsPerPost != null;

  factory ClubServerConfig.fromJson(Map<String, dynamic> j) => ClubServerConfig(
        upload: UploadRules.fromJson((j['upload'] as Map?)?.cast<String, dynamic>() ?? const {}),
        maxCommentDepth: (j['max_comment_depth'] as num?)?.toInt() ?? 2,
        maxCommentsPerPost: (j['max_comments_per_post'] as num?)?.toInt() ?? 1000,
        maxEmojisPerUserPerPost: (j['max_emojis_per_user_per_post'] as num?)?.toInt() ?? 5,
        maxHashtagsPerPost: (j['max_hashtags_per_post'] as num?)?.toInt() ?? 64,
        // No default: absent key must stay null (feature-off), per contract §2.
        maxModHashtagsPerPost: (j['max_mod_hashtags_per_post'] as num?)?.toInt(),
      );

  /// Baked-in fallback (mirrors vault.py) for offline / fetch failure.
  static const ClubServerConfig fallback = ClubServerConfig(
    upload: UploadRules(
      formats: ['png', 'gif', 'webp', 'bmp'],
      maxFileBytes: 5242880,
    ),
  );
}
