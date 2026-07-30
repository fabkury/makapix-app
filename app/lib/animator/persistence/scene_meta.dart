// Scene library metadata — DrawingMeta's twin for `.mkps` Scenes (adds the frame rate).
// Non-authoritative (the doc bytes are the truth); tolerant parsing with fallbacks.
import 'dart:convert';

class SceneMeta {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int width;
  final int height;
  final int frameCount;
  final int fpsMilli;

  const SceneMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.fpsMilli,
  });

  SceneMeta copyWith({String? title, DateTime? updatedAt}) => SceneMeta(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        width: width,
        height: height,
        frameCount: frameCount,
        fpsMilli: fpsMilli,
      );

  String encode() => jsonEncode({
        'id': id,
        'title': title,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'width': width,
        'height': height,
        'frameCount': frameCount,
        'fpsMilli': fpsMilli,
      });

  static SceneMeta? tryParse(String json,
      {required String fallbackId, required DateTime fallbackTime}) {
    try {
      final m = jsonDecode(json);
      if (m is! Map<String, dynamic>) return null;
      final id = m['id'] as String?;
      if (id == null || id.isEmpty) return null;
      DateTime time(String key) =>
          DateTime.tryParse(m[key] as String? ?? '')?.toUtc() ?? fallbackTime;
      return SceneMeta(
        id: id,
        title: m['title'] as String? ?? 'Untitled',
        createdAt: time('createdAt'),
        updatedAt: time('updatedAt'),
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
        frameCount: (m['frameCount'] as num?)?.toInt() ?? 1,
        fpsMilli: (m['fpsMilli'] as num?)?.toInt() ?? 12500,
      );
    } catch (_) {
      return null;
    }
  }
}
