// Lineage read models (artwork-provenance PLAN §5.5): parent slots and the
// "remixes of my works" items. Pure Dart — no engine binary, no network.
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/lineage.dart';

void main() {
  group('LineageParentSlot', () {
    test('available slot carries the post', () {
      final slot = LineageParentSlot.fromJson({
        'position': 0,
        'state': 'available',
        'post': {
          'id': 7,
          'public_sqid': 'aB3xY',
          'title': 'Mushroom',
          'art_url': 'https://vault/x.webp',
          'owner': {'handle': 'fab'},
          'remixable': true,
          'parent_count': 1,
        },
      });
      expect(slot.isAvailable, isTrue);
      expect(slot.post!.sqid, 'aB3xY');
      expect(slot.post!.parentCount, 1);
    });

    test('unavailable and deleted slots carry no identity', () {
      final unavailable =
          LineageParentSlot.fromJson({'position': 1, 'state': 'unavailable'});
      expect(unavailable.isAvailable, isFalse);
      expect(unavailable.isDeleted, isFalse);
      expect(unavailable.post, isNull);

      final deleted = LineageParentSlot.fromJson({'position': 2, 'state': 'deleted'});
      expect(deleted.isDeleted, isTrue);
      expect(deleted.post, isNull);
    });

    test('garbage state defaults to unavailable (no identity assumed)', () {
      final slot = LineageParentSlot.fromJson(const {});
      expect(slot.state, 'unavailable');
      expect(slot.isAvailable, isFalse);
    });
  });

  group('RemixReceivedItem', () {
    test('parses post and my_parent_sqids', () {
      final item = RemixReceivedItem.fromJson({
        'post': {
          'id': 9,
          'public_sqid': 'qW9zK',
          'title': 'Remix!',
          'art_url': 'https://vault/y.webp',
          'owner': {'handle': 'remixer'},
        },
        'my_parent_sqids': ['aB3xY', 'zZ1aa'],
      });
      expect(item.post.sqid, 'qW9zK');
      expect(item.myParentSqids, ['aB3xY', 'zZ1aa']);
    });

    test('missing my_parent_sqids parses as empty', () {
      final item = RemixReceivedItem.fromJson({
        'post': {'public_sqid': 'x', 'art_url': 'u', 'owner': {'handle': 'h'}},
      });
      expect(item.myParentSqids, isEmpty);
    });
  });
}
