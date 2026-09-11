// The id-keyed LRU behind the Frames page's thumbnails (frames/frame_thumb_cache.dart).
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/frames/frame_thumb_cache.dart';

void main() {
  test('put/get keep recency order and evict the least recently used', () {
    final evicted = <String>[];
    final c = LruById<String>(capacity: 3, onEvict: evicted.add);
    c.put(1, 'a');
    c.put(2, 'b');
    c.put(3, 'c');
    expect(c.get(1), 'a'); // 1 becomes most recent
    c.put(4, 'd');
    expect(evicted, ['b'], reason: '2 was the least recently used');
    expect(c.contains(2), isFalse);
    expect(c.length, 3);
    expect(c.peek(3), 'c');
    c.put(3, 'c2');
    expect(evicted, ['b', 'c'], reason: 'replacing a value evicts the old one');
    expect(c.get(3), 'c2');
  });

  test('invalidate and clear dispose what they drop', () {
    final evicted = <int>[];
    final c = LruById<int>(capacity: 10, onEvict: evicted.add);
    for (var i = 0; i < 5; i++) {
      c.put(i, i * 10);
    }
    c.invalidate([1, 3, 99]);
    expect(evicted, [10, 30]);
    expect(c.length, 3);
    c.clear();
    expect(evicted, [10, 30, 0, 20, 40]);
    expect(c.length, 0);
    expect(c.get(0), isNull);
  });
}
