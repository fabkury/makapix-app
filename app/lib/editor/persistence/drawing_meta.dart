import 'dart:convert';

/// Sidecar metadata for one library drawing (`meta.json`). Non-authoritative: title/dates/dims are
/// a convenience for the gallery and can be rebuilt from the `.mkpx` + file mtime if lost. The
/// drawing's pixels live in `doc.mkpx`, never here.
class DrawingMeta {
  static const int currentSchema = 1;

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int width;
  final int height;
  final int frameCount;

  const DrawingMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.width,
    required this.height,
    required this.frameCount,
  });

  DrawingMeta copyWith({
    String? title,
    DateTime? updatedAt,
    int? width,
    int? height,
    int? frameCount,
  }) =>
      DrawingMeta(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        width: width ?? this.width,
        height: height ?? this.height,
        frameCount: frameCount ?? this.frameCount,
      );

  Map<String, dynamic> toJson() => {
        'schema': currentSchema,
        'id': id,
        'title': title,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'width': width,
        'height': height,
        'frameCount': frameCount,
      };

  String encode() => jsonEncode(toJson());

  /// Parse `meta.json`. Tolerant: missing/garbage fields fall back to sensible defaults so a
  /// partially-written sidecar never hides a recoverable drawing. Returns null only if the JSON is
  /// unparseable or has no usable id.
  static DrawingMeta? tryParse(String source, {String? fallbackId, DateTime? fallbackTime}) {
    try {
      final m = jsonDecode(source);
      if (m is! Map) return null;
      final id = (m['id'] as String?) ?? fallbackId;
      if (id == null || id.isEmpty) return null;
      final now = fallbackTime ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      DateTime when(String key) {
        final v = m[key];
        return v is String ? (DateTime.tryParse(v) ?? now) : now;
      }

      int intOr(String key, int dflt) {
        final v = m[key];
        return v is num ? v.toInt() : dflt;
      }

      return DrawingMeta(
        id: id,
        title: (m['title'] as String?)?.trim().isNotEmpty == true ? m['title'] as String : 'Untitled',
        createdAt: when('createdAt'),
        updatedAt: when('updatedAt'),
        width: intOr('width', 0),
        height: intOr('height', 0),
        frameCount: intOr('frameCount', 1),
      );
    } catch (_) {
      return null;
    }
  }
}
