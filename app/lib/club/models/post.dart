/// An artwork (or playlist) post. Mirrors `GET /p/{sqid}` / feed items.
class Post {
  final int id;
  final String sqid; // public_sqid
  final String storageKey;
  final String kind; // "artwork" | "playlist"
  final String title;
  final String? description;
  final List<String> hashtags;
  final String artUrl; // full display URL (animated webp/gif render directly)
  final int width;
  final int height;
  final int frameCount;
  final int? uniqueColors;
  final bool transparencyActual;
  final bool alphaActual;
  final DateTime? createdAt;
  final bool promoted;
  final String? promotedCategory;
  final PostOwner owner;
  final int reactionCount;
  final int commentCount;
  final int viewCount;
  final bool userHasLiked;
  final List<PostFile> files;
  final License? license;
  final bool hasMkpx; // attached layers (.mkpx) file — drives the golden Edit button
  final int? mkpxFileBytes;
  final DateTime? mkpxAttachedAt; // changes on attach AND replace (cache stamp)

  Post({
    required this.id,
    required this.sqid,
    required this.storageKey,
    required this.kind,
    required this.title,
    required this.description,
    required this.hashtags,
    required this.artUrl,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.uniqueColors,
    required this.transparencyActual,
    required this.alphaActual,
    required this.createdAt,
    required this.promoted,
    required this.promotedCategory,
    required this.owner,
    required this.reactionCount,
    required this.commentCount,
    this.viewCount = 0,
    required this.userHasLiked,
    required this.files,
    required this.license,
    this.hasMkpx = false,
    this.mkpxFileBytes,
    this.mkpxAttachedAt,
  });

  bool get isAnimated => frameCount > 1;
  bool get isPlaylist => kind == 'playlist';

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: (j['id'] as num?)?.toInt() ?? 0,
        sqid: (j['public_sqid'] ?? '').toString(),
        storageKey: (j['storage_key'] ?? '').toString(),
        kind: (j['kind'] ?? 'artwork').toString(),
        title: (j['title'] ?? '').toString(),
        description: j['description'] as String?,
        hashtags: (j['hashtags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        artUrl: (j['art_url'] ?? '').toString(),
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
        frameCount: (j['frame_count'] as num?)?.toInt() ?? 1,
        uniqueColors: (j['unique_colors'] as num?)?.toInt(),
        transparencyActual: j['transparency_actual'] == true,
        alphaActual: j['alpha_actual'] == true,
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
        promoted: j['promoted'] == true,
        promotedCategory: j['promoted_category'] as String?,
        owner: PostOwner.fromJson(((j['owner'] as Map?) ?? const {}).cast<String, dynamic>()),
        reactionCount: (j['reaction_count'] as num?)?.toInt() ?? 0,
        commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
        viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
        userHasLiked: j['user_has_liked'] == true,
        files: (j['files'] as List?)
                ?.map((e) => PostFile.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        license: j['license'] is Map
            ? License.fromJson((j['license'] as Map).cast<String, dynamic>())
            : null,
        hasMkpx: j['has_mkpx'] == true,
        mkpxFileBytes: (j['mkpx_file_bytes'] as num?)?.toInt(),
        mkpxAttachedAt: DateTime.tryParse((j['mkpx_attached_at'] ?? '').toString()),
      );
}

class PostOwner {
  final String userKey; // UUID (used as owner_id filter for the gallery)
  final String sqid; // public_sqid (social endpoints)
  final String handle;
  final String? avatarUrl;
  final String? tagline;
  final int reputation;

  PostOwner({
    required this.userKey,
    required this.sqid,
    required this.handle,
    required this.avatarUrl,
    required this.tagline,
    required this.reputation,
  });

  factory PostOwner.fromJson(Map<String, dynamic> j) => PostOwner(
        userKey: (j['user_key'] ?? '').toString(),
        sqid: (j['public_sqid'] ?? '').toString(),
        handle: (j['handle'] ?? 'unknown').toString(),
        avatarUrl: j['avatar_url'] as String?,
        tagline: j['tagline'] as String?,
        reputation: (j['reputation'] as num?)?.toInt() ?? 0,
      );
}

class PostFile {
  final String format;
  final int fileBytes;
  final bool isNative;
  PostFile({required this.format, required this.fileBytes, required this.isNative});

  factory PostFile.fromJson(Map<String, dynamic> j) => PostFile(
        format: (j['format'] ?? '').toString(),
        fileBytes: (j['file_bytes'] as num?)?.toInt() ?? 0,
        isNative: j['is_native'] == true,
      );
}

class License {
  final String identifier;
  final String title;
  final String? canonicalUrl;
  final String? badgePath;
  License({required this.identifier, required this.title, this.canonicalUrl, this.badgePath});

  factory License.fromJson(Map<String, dynamic> j) => License(
        identifier: (j['identifier'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        canonicalUrl: j['canonical_url'] as String?,
        badgePath: j['badge_path'] as String?,
      );
}
