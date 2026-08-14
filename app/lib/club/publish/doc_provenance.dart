/// Provenance the editor tracks for the working document, persisted inside the
/// project file (`.mkpx` META chunk) so publish-time declarations reflect the
/// work's whole history across save/load — the server-contract requirement from
/// docs/artwork-provenance message 0002. Pure Dart (no engine dependency): the
/// editor serializes it via `Engine.saveWithMeta(provenance.toMeta())` and the
/// publish flow reads it off the `PublishDraft`.
class DocProvenance {
  /// META keys. `club.everImported` is the sticky import bit ('1'/'0');
  /// `club.importedFormats` the formats ever imported (comma list, first-use
  /// order); `club.parents` the Club parent sqids (comma list, base first).
  static const String keyEverImported = 'club.everImported';
  static const String keyImportedFormats = 'club.importedFormats';
  static const String keyParents = 'club.parents';

  /// Server cap: up to 8 parents after dedup (SPEC-side L2).
  static const int maxParents = 8;

  /// The sticky import bit: true once the import tool was used — or a Club post
  /// seeded the document — at ANY point in the work's history, even if every
  /// pixel was later repainted. False is the strong "hand-drawn from scratch"
  /// claim, provable only for documents tracked from birth. Null = unknown
  /// (a legacy file predating the bit): `creation_method` is then omitted at
  /// publish, which the server records as "unknown" — honest, per message 0001.
  bool? everImported;

  /// Lowercased formats ever imported ('png', 'gif', …), first-use order, deduped.
  final List<String> importedFormats;

  /// Club parent sqids in declaration order — the seeding post first, then any
  /// later-imported posts — deduped, capped at [maxParents].
  final List<String> parents;

  DocProvenance._(this.everImported, this.importedFormats, this.parents);

  /// A document tracked from birth (New document): provably never imported.
  DocProvenance.fresh() : this._(false, [], []);

  /// A document whose history predates provenance tracking (legacy project
  /// files, foreign `.mkpx` files without our META keys).
  DocProvenance.unknown() : this._(null, [], []);

  /// Restore from `.mkpx` META entries; entries without our keys → [unknown].
  factory DocProvenance.fromMeta(Map<String, String> meta) {
    final bit = meta[keyEverImported];
    List<String> csv(String? v) =>
        (v == null || v.isEmpty) ? [] : v.split(',').where((s) => s.isNotEmpty).toList();
    final parents = csv(meta[keyParents]).take(maxParents).toList();
    if (bit == null && parents.isEmpty) return DocProvenance.unknown();
    // Any parent implies remix seeding, which counts as import (message 0001 §2).
    final imported = bit == '1' || parents.isNotEmpty;
    return DocProvenance._(imported, csv(meta[keyImportedFormats]), parents);
  }

  /// META entries to ride in every save. Empty for [unknown] documents — we
  /// never stamp a fabricated history onto a legacy file.
  Map<String, String> toMeta() {
    final bit = everImported;
    if (bit == null) return {};
    return {
      keyEverImported: bit ? '1' : '0',
      if (importedFormats.isNotEmpty) keyImportedFormats: importedFormats.join(','),
      if (parents.isNotEmpty) keyParents: parents.join(','),
    };
  }

  /// Record a use of the import tool. Sets the sticky bit — including on an
  /// [unknown] document: "import was used" is then true regardless of the
  /// unknowable earlier history.
  void markImported(String format) {
    everImported = true;
    final f = format.toLowerCase();
    if (f.isNotEmpty && !importedFormats.contains(f)) importedFormats.add(f);
  }

  /// Record a Club post seeding or being imported into this work. Deduped;
  /// silently ignored past [maxParents] (the publish flow surfaces the cap).
  /// Seeding counts as import, so the sticky bit is set too.
  void addParent(String sqid) {
    everImported = true;
    if (sqid.isEmpty || parents.contains(sqid)) return;
    if (parents.length >= maxParents) return;
    parents.add(sqid);
  }

  /// The `creation_method` to declare at publish: the strong hand-drawn claim,
  /// the sticky import fact, or null = omit the field entirely (unknown).
  String? get creationMethod => switch (everImported) {
        null => null,
        true => 'editor_import',
        false => 'editor_hand_drawn',
      };

  /// The `imported_format` detail for `source_details` (most recent first-class
  /// import format; null when none were file imports).
  String? get importedFormat => importedFormats.isEmpty ? null : importedFormats.join(',');

  /// The parents to declare when publishing, excluding [replacedSqid] when the
  /// publish is a Replace of that very post (a post can never be its own
  /// parent — the server rejects self-loops).
  List<String> parentsForPublish({String? replacedSqid}) =>
      parents.where((p) => p != replacedSqid).toList();
}
