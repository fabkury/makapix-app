import 'post.dart' show PostFile;

/// Post Management Dashboard models (`/api/pmd/*`, SPEC-CLUB §20).

/// One row in the PMD table — the signed-in user's own post.
class PmdPostItem {
  final int id;
  final String sqid;
  final String title;
  final String? description;
  final DateTime? createdAt;
  final int width;
  final int height;
  final int frameCount;
  final List<PostFile> files;
  final String artUrl;
  final bool hiddenByUser;
  final int reactionCount;
  final int commentCount;
  final int viewCount;
  final String? licenseIdentifier; // e.g. "CC-BY-4.0"; null = all rights reserved

  const PmdPostItem({
    required this.id,
    required this.sqid,
    required this.title,
    this.description,
    this.createdAt,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.files,
    required this.artUrl,
    required this.hiddenByUser,
    required this.reactionCount,
    required this.commentCount,
    required this.viewCount,
    this.licenseIdentifier,
  });

  /// The native file's bytes/format (falls back to the first file).
  int get fileBytes {
    for (final f in files) {
      if (f.isNative) return f.fileBytes;
    }
    return files.isNotEmpty ? files.first.fileBytes : 0;
  }

  String get format {
    for (final f in files) {
      if (f.isNative) return f.format;
    }
    return files.isNotEmpty ? files.first.format : '';
  }

  PmdPostItem copyWith({bool? hiddenByUser, String? licenseIdentifier, bool clearLicense = false}) =>
      PmdPostItem(
        id: id,
        sqid: sqid,
        title: title,
        description: description,
        createdAt: createdAt,
        width: width,
        height: height,
        frameCount: frameCount,
        files: files,
        artUrl: artUrl,
        hiddenByUser: hiddenByUser ?? this.hiddenByUser,
        reactionCount: reactionCount,
        commentCount: commentCount,
        viewCount: viewCount,
        licenseIdentifier: clearLicense ? null : (licenseIdentifier ?? this.licenseIdentifier),
      );

  factory PmdPostItem.fromJson(Map<String, dynamic> j) => PmdPostItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        sqid: (j['public_sqid'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        description: j['description'] as String?,
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
        frameCount: (j['frame_count'] as num?)?.toInt() ?? 1,
        files: (j['files'] as List?)
                ?.map((e) => PostFile.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        artUrl: (j['art_url'] ?? '').toString(),
        hiddenByUser: j['hidden_by_user'] == true,
        reactionCount: (j['reaction_count'] as num?)?.toInt() ?? 0,
        commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
        viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
        licenseIdentifier: j['license_identifier'] as String?,
      );
}

/// Result of a batch action / license change (`{success, affected_count, message}`).
class BatchActionResult {
  final bool success;
  final int affectedCount;
  final String message;
  const BatchActionResult(
      {required this.success, required this.affectedCount, required this.message});

  factory BatchActionResult.fromJson(Map<String, dynamic> j) => BatchActionResult(
        success: j['success'] == true,
        affectedCount: (j['affected_count'] as num?)?.toInt() ?? 0,
        message: (j['message'] ?? '').toString(),
      );
}

/// A batch download request (the async ZIP export job).
class Bdr {
  final String id;
  final String status; // pending | processing | ready | failed | expired
  final int artworkCount;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? expiresAt;
  final String? errorMessage;

  const Bdr({
    required this.id,
    required this.status,
    required this.artworkCount,
    this.createdAt,
    this.completedAt,
    this.expiresAt,
    this.errorMessage,
  });

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';
  bool get isExpired => status == 'expired';
  bool get inProgress => status == 'pending' || status == 'processing';

  factory Bdr.fromJson(Map<String, dynamic> j) => Bdr(
        id: (j['id'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        artworkCount: (j['artwork_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
        completedAt: DateTime.tryParse((j['completed_at'] ?? '').toString()),
        expiresAt: DateTime.tryParse((j['expires_at'] ?? '').toString()),
        errorMessage: j['error_message'] as String?,
      );
}

/// Result of creating a BDR (`POST /pmd/bdr`).
class CreateBdrResult {
  final String id;
  final String status;
  final int artworkCount;
  final String message;
  const CreateBdrResult(
      {required this.id,
      required this.status,
      required this.artworkCount,
      required this.message});

  factory CreateBdrResult.fromJson(Map<String, dynamic> j) => CreateBdrResult(
        id: (j['id'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        artworkCount: (j['artwork_count'] as num?)?.toInt() ?? 0,
        message: (j['message'] ?? '').toString(),
      );
}
