import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/edit/club_edit_request.dart';
import 'package:makapix_club/club/publish/publish_draft.dart';

void main() {
  test('ClubEditRequest carries bytes + source + ownership', () {
    final req = ClubEditRequest(
      bytes: Uint8List.fromList([1, 2, 3]),
      width: 64,
      height: 64,
      sourcePostId: 42,
      sourceSqid: 'eDfc',
      sourceTitle: 'monster',
      sourceOwnerHandle: 'Fab',
      isOwner: true,
    );
    expect(req.bytes.length, 3);
    expect(req.sourcePostId, 42);
    expect(req.isOwner, isTrue);
  });

  test('PublishDraft carries an optional ClubEditSource', () {
    const src = ClubEditSource(postId: 42, sqid: 'eDfc', title: 'monster', ownerHandle: 'Fab', isOwner: true);
    final remix = PublishDraft(
        bytes: Uint8List(0), format: 'png', filename: 'a.png', width: 64, height: 64, frameCount: 1, source: src);
    expect(remix.source?.isOwner, isTrue);

    final fresh = PublishDraft(
        bytes: Uint8List(0), format: 'png', filename: 'a.png', width: 64, height: 64, frameCount: 1);
    expect(fresh.source, isNull);
  });
}
