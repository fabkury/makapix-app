import 'dart:convert';

import 'doc_provenance.dart';

/// Build the optional provenance/lineage multipart form fields for
/// `POST /post/upload` and `POST /post/{id}/replace-artwork`
/// (docs/artwork-provenance messages 0001 + 0002). Every field is optional
/// server-side — an absent field records as "unknown", so omission is always
/// the safe fallback. Pure Dart, engine- and Flutter-free for testability.
Map<String, String> provenanceFormFields({
  /// The app version ('1.2.2') — sent as `client: app/<version>` and
  /// `source_details.editor_version`. Empty = omit both.
  required String appVersion,

  /// `Platform.operatingSystem`; only 'ios'/'android' are whitelisted values
  /// for `source_details.editor_platform`, so anything else omits the key.
  required String platform,

  /// The upload device's form factor: 'mobile' | 'tablet' (| 'desktop' for the
  /// Windows build). Null = omit.
  String? deviceType,

  /// The document's tracked provenance; null (a draft that didn't come from
  /// the editor) declares no method, formats, or parents.
  DocProvenance? provenance,

  /// For replace-artwork: the sqid of the post being replaced. Its own sqid is
  /// excluded from `remixed_from` (a post can never be its own parent).
  String? replacedSqid,

  /// The owner's Remixable choice — upload only (replace ignores it there and
  /// the toggle belongs to PATCH). Null = omit (server default applies).
  bool? remixable,

  /// True when the user explicitly chose to publish without the remix claim
  /// after a 422 `remix_not_allowed` / `parent_not_found` — drops only
  /// `remixed_from`, never the rest of the declaration.
  bool declareParents = true,
}) {
  final fields = <String, String>{
    if (appVersion.isNotEmpty) 'client': 'app/$appVersion',
  };
  final method = provenance?.creationMethod;
  if (method != null) fields['creation_method'] = method;
  final importedFormat = provenance?.importedFormat;
  final details = <String, String>{
    if (appVersion.isNotEmpty) 'editor_version': appVersion,
    if (platform == 'ios' || platform == 'android') 'editor_platform': platform,
    if (deviceType != null && deviceType.isNotEmpty) 'device_type': deviceType,
    if (method == 'editor_import' && importedFormat != null) 'imported_format': importedFormat,
  };
  if (details.isNotEmpty) fields['source_details'] = jsonEncode(details);
  if (declareParents) {
    final parents = provenance?.parentsForPublish(replacedSqid: replacedSqid) ?? const [];
    if (parents.isNotEmpty) fields['remixed_from'] = parents.join(',');
  }
  if (remixable != null) fields['remixable'] = remixable.toString();
  return fields;
}
