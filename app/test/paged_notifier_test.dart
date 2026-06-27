import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/page.dart';
import 'package:makapix_club/club/state/paged.dart';

void main() {
  test('loads initial, appends on loadMore, stops at end', () async {
    Future<Page<int>> fetch(String? cursor) async => cursor == null
        ? const Page(items: [1, 2], nextCursor: 'c1')
        : const Page(items: [3, 4], nextCursor: null);

    final n = PagedNotifier<int>(fetch);
    await n.loadInitial();
    expect(n.state.items, [1, 2]);
    expect(n.state.atEnd, isFalse);
    expect(n.state.initialized, isTrue);

    await n.loadMore();
    expect(n.state.items, [1, 2, 3, 4]);
    expect(n.state.atEnd, isTrue);

    await n.loadMore(); // no-op once atEnd
    expect(n.state.items, [1, 2, 3, 4]);
  });

  test('refresh resets the list and cursor', () async {
    var calls = 0;
    Future<Page<int>> fetch(String? cursor) async {
      calls++;
      return Page(items: [calls], nextCursor: null);
    }

    final n = PagedNotifier<int>(fetch);
    await n.loadInitial();
    expect(n.state.items, [1]);
    await n.refresh();
    expect(n.state.items, [2]);
  });

  test('surfaces fetch errors without throwing', () async {
    Future<Page<int>> fetch(String? cursor) async => throw StateError('boom');
    final n = PagedNotifier<int>(fetch);
    await n.loadInitial();
    expect(n.state.error, isNotNull);
    expect(n.state.items, isEmpty);
    expect(n.state.initialized, isTrue);
  });
}
