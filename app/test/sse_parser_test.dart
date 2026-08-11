import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/sse.dart';

void main() {
  test('parses a complete event frame', () {
    final p = SseParser();
    final events = p.addChunk('event: connected\ndata: {"unread_count": 3}\n\n');
    expect(events, hasLength(1));
    expect(events[0].event, 'connected');
    expect(events[0].data, '{"unread_count": 3}');
  });

  test('defaults to "message" when the frame has no event line', () {
    final events = SseParser().addChunk('data: hello\n\n');
    expect(events.single.event, 'message');
    expect(events.single.data, 'hello');
  });

  test('buffers across arbitrary chunk boundaries', () {
    final p = SseParser();
    expect(p.addChunk('event: notif'), isEmpty);
    expect(p.addChunk('ication\ndata: {"id":'), isEmpty);
    final events = p.addChunk(' "abc"}\n\n');
    expect(events.single.event, 'notification');
    expect(events.single.data, '{"id": "abc"}');
  });

  test('one chunk may complete several events', () {
    final events = SseParser()
        .addChunk('event: a\ndata: 1\n\nevent: b\ndata: 2\n\ndata: partial');
    expect(events.map((e) => e.event), ['a', 'b']);
    expect(events.map((e) => e.data), ['1', '2']);
  });

  test('keepalive comment frames produce no events', () {
    final p = SseParser();
    expect(p.addChunk(': keepalive\n\n'), isEmpty);
    // A comment inside a data frame is skipped, the data survives.
    final events = p.addChunk(': keepalive\nevent: timeout\ndata: {"message": "bye"}\n\n');
    expect(events.single.event, 'timeout');
  });

  test('joins multi-line data with newlines', () {
    final events = SseParser().addChunk('data: line1\ndata: line2\n\n');
    expect(events.single.data, 'line1\nline2');
  });

  test('normalizes CRLF line endings, including split across chunks', () {
    final p = SseParser();
    expect(p.addChunk('event: connected\r\ndata: {}\r'), isEmpty);
    final events = p.addChunk('\n\r\n');
    expect(events.single.event, 'connected');
    expect(events.single.data, '{}');
  });
}
