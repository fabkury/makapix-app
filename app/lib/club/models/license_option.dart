/// A selectable license (`GET /api/v1/license` → items). `id` is what upload sends.
class LicenseOption {
  final int id;
  final String identifier;
  final String title;
  final String? badgePath;
  const LicenseOption({required this.id, required this.identifier, required this.title, this.badgePath});

  /// NoDerivatives licenses forbid remixes: the server forces `remixable=false`
  /// for them and 422s an explicit `remixable=true` (`remixable_conflicts_with_license`).
  bool get isNoDerivatives => identifier.toUpperCase().contains('-ND');

  factory LicenseOption.fromJson(Map<String, dynamic> j) => LicenseOption(
        id: (j['id'] as num?)?.toInt() ?? 0,
        identifier: (j['identifier'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        badgePath: j['badge_path'] as String?,
      );
}
