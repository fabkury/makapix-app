// Pure unit tests for the byte-budgeted LRU — no engine, no network, no widgets.
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/anim/byte_budget_lru.dart';

void main() {
  // Values are strings; size = string length, so budgets read naturally.
  ByteBudgetLru<String, String> lru(int maxBytes, List<String> evicted) =>
      ByteBudgetLru<String, String>(
        maxBytes: maxBytes,
        sizeOf: (v) => v.length,
        onEvict: evicted.add,
      );

  test('tracks totalBytes across puts', () {
    final evicted = <String>[];
    final c = lru(100, evicted);
    expect(c.put('a', 'xxxxx'), isTrue); // 5
    expect(c.put('b', 'xxx'), isTrue); // 3
    expect(c.totalBytes, 8);
    expect(c.length, 2);
    expect(evicted, isEmpty);
  });

  test('evicts least-recently-used first', () {
    final evicted = <String>[];
    final c = lru(10, evicted);
    c.put('a', 'aaaa'); // 4
    c.put('b', 'bbbb'); // 4
    c.put('c', 'cccc'); // 4 → must evict 'a'
    expect(evicted, ['aaaa']);
    expect(c.get('a'), isNull);
    expect(c.get('b'), 'bbbb');
    expect(c.totalBytes, 8);
  });

  test('get refreshes recency', () {
    final evicted = <String>[];
    final c = lru(10, evicted);
    c.put('a', 'aaaa');
    c.put('b', 'bbbb');
    c.get('a'); // 'b' is now LRU
    c.put('c', 'cccc');
    expect(evicted, ['bbbb']);
    expect(c.get('a'), 'aaaa');
    expect(c.get('b'), isNull);
  });

  test('overwriting a key evicts the old value and adjusts bytes', () {
    final evicted = <String>[];
    final c = lru(100, evicted);
    c.put('a', 'aaaa'); // 4
    c.put('a', 'aa'); // 2
    expect(evicted, ['aaaa']);
    expect(c.totalBytes, 2);
    expect(c.length, 1);
    expect(c.get('a'), 'aa');
  });

  test('an entry larger than the whole budget is refused, nothing evicted', () {
    final evicted = <String>[];
    final c = lru(5, evicted);
    c.put('a', 'aaa'); // 3
    expect(c.put('big', 'xxxxxxxxxx'), isFalse); // 10 > 5
    expect(evicted, isEmpty);
    expect(c.get('big'), isNull);
    expect(c.get('a'), 'aaa'); // untouched
    expect(c.totalBytes, 3);
  });

  test('a maximal entry may evict everything else to fit', () {
    final evicted = <String>[];
    final c = lru(5, evicted);
    c.put('a', 'aa');
    c.put('b', 'bb');
    expect(c.put('big', 'xxxxx'), isTrue); // exactly the budget
    expect(evicted, ['aa', 'bb']);
    expect(c.totalBytes, 5);
    expect(c.length, 1);
  });

  test('remove credits bytes and fires onEvict', () {
    final evicted = <String>[];
    final c = lru(100, evicted);
    c.put('a', 'aaaa');
    c.remove('a');
    expect(evicted, ['aaaa']);
    expect(c.totalBytes, 0);
    c.remove('a'); // absent key is a no-op
    expect(evicted, ['aaaa']);
  });

  test('clear evicts everything', () {
    final evicted = <String>[];
    final c = lru(100, evicted);
    c.put('a', 'aa');
    c.put('b', 'bbb');
    c.clear();
    expect(evicted.toSet(), {'aa', 'bbb'});
    expect(c.totalBytes, 0);
    expect(c.length, 0);
  });
}
