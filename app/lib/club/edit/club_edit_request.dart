import 'dart:typed_data';

/// A request from the Club UI to open an artwork in the editor (club → editor).
/// Carries the downloaded bytes + the source post so the editor can later offer
/// "Replace original" / pre-fill remix metadata.
class ClubEditRequest {
  final Uint8List bytes;
  final int width;
  final int height;
  final int sourcePostId;
  final String sourceSqid;
  final String sourceTitle;
  final String sourceOwnerHandle;
  final bool isOwner;

  const ClubEditRequest({
    required this.bytes,
    required this.width,
    required this.height,
    required this.sourcePostId,
    required this.sourceSqid,
    required this.sourceTitle,
    required this.sourceOwnerHandle,
    required this.isOwner,
  });
}

/// Provenance the editor keeps while editing a Club artwork; read by the publish
/// flow to offer Replace and pre-fill remix metadata.
class ClubEditSource {
  final int postId;
  final String sqid;
  final String title;
  final String ownerHandle;
  final bool isOwner;

  const ClubEditSource({
    required this.postId,
    required this.sqid,
    required this.title,
    required this.ownerHandle,
    required this.isOwner,
  });
}
