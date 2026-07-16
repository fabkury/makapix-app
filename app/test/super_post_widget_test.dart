import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/state/paged.dart';
import 'package:makapix_club/club/ui/widgets/feed_grid.dart';

/// Empty art_url → tiles render the no-image box, no HTTP inside the test
/// (same trick as profile_ui_test.dart). Unique reaction counts let each
/// tile be located on screen by its like-count text.
Post _post(int id) => Post.fromJson({
      'id': id,
      'storage_key': 'k$id',
      'public_sqid': 'p$id',
      'kind': 'artwork',
      'title': 'post $id',
      'hashtags': [],
      'art_url': '',
      'width': 64,
      'height': 64,
      'frame_count': 1,
      'created_at': '2026-04-21T15:43:33.700608Z',
      'owner': {
        'id': 1,
        'user_key': 'u-key-1',
        'public_sqid': 't5',
        'handle': 'PixelFab',
        'reputation': 500,
      },
      'reaction_count': 100 + id,
      'comment_count': 0,
      'user_has_liked': false,
      'files': [],
    });

Widget _harness(List<Post> posts, {int? superPostId}) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: FeedGrid(
            state: PagedState<Post>(items: posts, initialized: true, atEnd: true),
            onLoadMore: () async {},
            onRefresh: () async {},
            onTap: (_) {},
            superPostId: superPostId,
          ),
        ),
      ),
    );

/// Rect of the whole tile (its ClipRRect) containing the like-count [text].
Rect _tileRect(WidgetTester tester, String text) =>
    tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(ClipRRect)).first);

void main() {
  // Default test surface is 800×600: cols = 6, tileW = (800-8-20)/6.
  const cols = 6;
  const tileW = (800.0 - 8 - 4 * (cols - 1)) / cols;
  const tileH = tileW + 24;
  const sx = tileW + 4, sy = tileH + 4;
  Offset cell(int col, int row) => Offset(4 + col * sx, 4 + row * sy);

  testWidgets('super tile spans 2×2 and later tiles dense-fill around it', (tester) async {
    final posts = [for (var i = 0; i < 12; i++) _post(i)];
    await tester.pumpWidget(_harness(posts, superPostId: 2)); // index 2, col 2
    await tester.pump();

    // Super tile (like count 102): 2×2 block anchored at cell (2, 0).
    final superRect = _tileRect(tester, '102');
    expect(superRect.topLeft, offsetMoreOrLessEquals(cell(2, 0), epsilon: 0.5));
    expect(superRect.width, moreOrLessEquals(2 * tileW + 4, epsilon: 0.5));
    expect(superRect.height, moreOrLessEquals(2 * tileH + 4, epsilon: 0.5));

    // Title + author line, only on the super tile.
    expect(find.textContaining('post 2'), findsOneWidget);
    expect(find.textContaining('@PixelFab'), findsOneWidget);
    expect(find.textContaining('post 3'), findsNothing);

    // Tiles before the super post are unaffected.
    expect(_tileRect(tester, '100').topLeft, offsetMoreOrLessEquals(cell(0, 0), epsilon: 0.5));
    expect(_tileRect(tester, '101').topLeft, offsetMoreOrLessEquals(cell(1, 0), epsilon: 0.5));
    // Block cells are {2,3,8,9}: post 3 → cell 4, post 4 → cell 5,
    // post 5 → row 1 col 0, post 7 → cell 10 (right of the block's second row).
    expect(_tileRect(tester, '103').topLeft, offsetMoreOrLessEquals(cell(4, 0), epsilon: 0.5));
    expect(_tileRect(tester, '104').topLeft, offsetMoreOrLessEquals(cell(5, 0), epsilon: 0.5));
    expect(_tileRect(tester, '105').topLeft, offsetMoreOrLessEquals(cell(0, 1), epsilon: 0.5));
    expect(_tileRect(tester, '107').topLeft, offsetMoreOrLessEquals(cell(4, 1), epsilon: 0.5));
    expect(_tileRect(tester, '108').topLeft, offsetMoreOrLessEquals(cell(5, 1), epsilon: 0.5));
    // Regular tiles keep the uniform size.
    expect(_tileRect(tester, '103').width, moreOrLessEquals(tileW, epsilon: 0.5));
    expect(_tileRect(tester, '103').height, moreOrLessEquals(tileH, epsilon: 0.5));
  });

  testWidgets('null or stale superPostId keeps the grid uniform', (tester) async {
    final posts = [for (var i = 0; i < 8; i++) _post(i)];
    for (final id in [null, 999]) {
      await tester.pumpWidget(_harness(posts, superPostId: id));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        final r = _tileRect(tester, '${100 + i}');
        expect(r.topLeft, offsetMoreOrLessEquals(cell(i % cols, i ~/ cols), epsilon: 0.5),
            reason: 'superPostId=$id tile $i');
        expect(r.width, moreOrLessEquals(tileW, epsilon: 0.5));
      }
      expect(find.textContaining('@PixelFab'), findsNothing);
    }
  });
}
