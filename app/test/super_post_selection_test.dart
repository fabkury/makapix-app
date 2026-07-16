import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/club_error.dart';
import 'package:makapix_club/club/models/page.dart';
import 'package:makapix_club/club/state/paged.dart';
import 'package:makapix_club/club/state/super_post_provider.dart';

void main() {
  group('pickSuperIndex', () {
    test('deterministic and in range', () {
      for (var count = 1; count <= 30; count++) {
        for (var gen = 1; gen <= 5; gen++) {
          final a = pickSuperIndex(salt: 42, kindIndex: 1, generation: gen, firstPageCount: count);
          final b = pickSuperIndex(salt: 42, kindIndex: 1, generation: gen, firstPageCount: count);
          expect(a, b);
          expect(a, inInclusiveRange(0, count - 1));
        }
      }
    });

    test('-1 when page 1 is empty', () {
      expect(pickSuperIndex(salt: 42, kindIndex: 0, generation: 1, firstPageCount: 0), -1);
      expect(pickSuperIndex(salt: 42, kindIndex: 0, generation: 0, firstPageCount: -3), -1);
    });

    test('varies across generations and kinds (for some salt)', () {
      // Not every pair differs (randomness), but across many generations the
      // picks must not all collapse to one value.
      final picks = {
        for (var gen = 1; gen <= 20; gen++)
          pickSuperIndex(salt: 7, kindIndex: 0, generation: gen, firstPageCount: 24)
      };
      expect(picks.length, greaterThan(1));
      final kinds = {
        for (var kind = 0; kind < 3; kind++)
          for (var gen = 1; gen <= 10; gen++)
            pickSuperIndex(salt: 7, kindIndex: kind, generation: gen, firstPageCount: 24)
      };
      expect(kinds.length, greaterThan(1));
    });
  });

  group('PagedState generation/firstPageCount', () {
    test('bumped on initial load and refresh, stable across loadMore', () async {
      var failNext = false;
      Future<Page<int>> fetch(String? cursor) async {
        if (failNext) throw ClubError(code: 'x', message: 'boom');
        return cursor == null
            ? const Page(items: [1, 2, 3], nextCursor: 'c1')
            : const Page(items: [4, 5], nextCursor: null);
      }

      final n = PagedNotifier<int>(fetch);
      expect(n.state.generation, 0);
      expect(n.state.firstPageCount, 0);

      await n.loadInitial();
      expect(n.state.generation, 1);
      expect(n.state.firstPageCount, 3);

      await n.loadMore();
      expect(n.state.items, [1, 2, 3, 4, 5]);
      expect(n.state.generation, 1, reason: 'loadMore must not re-roll');
      expect(n.state.firstPageCount, 3);

      await n.refresh();
      expect(n.state.generation, 2);
      expect(n.state.firstPageCount, 3);

      failNext = true;
      await n.refresh();
      expect(n.state.error, isNotNull);
      expect(n.state.items, [1, 2, 3], reason: 'failed refresh keeps items');
      expect(n.state.generation, 2, reason: 'failed refresh keeps the old pick valid');
      expect(n.state.firstPageCount, 3);
    });

    test('copyWith preserves both fields', () {
      const s = PagedState<int>(items: [1], generation: 5, firstPageCount: 7);
      final c = s.copyWith(loading: true, error: 'e');
      expect(c.generation, 5);
      expect(c.firstPageCount, 7);
    });
  });
}
