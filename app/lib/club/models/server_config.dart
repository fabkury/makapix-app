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

/// Upload conformance rules from `GET /api/v1/config` → `upload`.
class UploadRules {
  final List<String> formats;
  final int maxFileBytes;
  final int freeFormMin;
  final int freeFormMax;
  final List<List<int>> smallWhitelist; // already includes both orientations
  final MkpxRules mkpx;

  const UploadRules({
    required this.formats,
    required this.maxFileBytes,
    required this.freeFormMin,
    required this.freeFormMax,
    required this.smallWhitelist,
    this.mkpx = MkpxRules.disabled,
  });

  factory UploadRules.fromJson(Map<String, dynamic> j) => UploadRules(
        formats: (j['formats'] as List?)?.map((e) => e.toString()).toList() ??
            const ['png', 'gif', 'webp', 'bmp'],
        maxFileBytes: (j['max_file_bytes'] as num?)?.toInt() ?? 5242880,
        freeFormMin: (j['free_form_min'] as num?)?.toInt() ?? 128,
        freeFormMax: (j['free_form_max'] as num?)?.toInt() ?? 256,
        smallWhitelist: ((j['small_whitelist'] as List?) ?? const [])
            .map((e) => (e as List).map((n) => (n as num).toInt()).toList())
            .toList(),
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

  const ClubServerConfig({
    required this.upload,
    this.maxCommentDepth = 2,
    this.maxCommentsPerPost = 1000,
    this.maxEmojisPerUserPerPost = 5,
    this.maxHashtagsPerPost = 64,
  });

  factory ClubServerConfig.fromJson(Map<String, dynamic> j) => ClubServerConfig(
        upload: UploadRules.fromJson((j['upload'] as Map?)?.cast<String, dynamic>() ?? const {}),
        maxCommentDepth: (j['max_comment_depth'] as num?)?.toInt() ?? 2,
        maxCommentsPerPost: (j['max_comments_per_post'] as num?)?.toInt() ?? 1000,
        maxEmojisPerUserPerPost: (j['max_emojis_per_user_per_post'] as num?)?.toInt() ?? 5,
        maxHashtagsPerPost: (j['max_hashtags_per_post'] as num?)?.toInt() ?? 64,
      );

  /// Baked-in fallback (mirrors vault.py) for offline / fetch failure.
  static const ClubServerConfig fallback = ClubServerConfig(
    upload: UploadRules(
      formats: ['png', 'gif', 'webp', 'bmp'],
      maxFileBytes: 5242880,
      freeFormMin: 128,
      freeFormMax: 256,
      smallWhitelist: [
        [8, 8], [8, 16], [16, 8], [8, 32], [32, 8], [16, 16], [16, 32], [32, 16],
        [32, 32], [32, 64], [64, 32], [64, 64], [64, 128], [128, 64],
      ],
    ),
  );
}
