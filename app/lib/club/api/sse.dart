/// Minimal Server-Sent Events wire parser — the subset the Club API emits
/// (`GET /realtime/notifications`, contract in the server repo's
/// `docs/http-api/notifications.md`).
///
/// Pure and I/O-free: feed decoded text chunks in via [addChunk]; complete
/// events come back out. Chunk boundaries are arbitrary (an event may span
/// several chunks, or one chunk may carry several events). Comment frames
/// (`: keepalive`) carry no data and produce no events.
class SseEvent {
  /// The `event:` field, or `"message"` when the frame has none (SSE default).
  final String event;

  /// Multi-line `data:` fields joined with `\n`.
  final String data;

  const SseEvent(this.event, this.data);
}

class SseParser {
  String _pending = '';

  /// Consume [chunk] and return every event completed by it, in order.
  List<SseEvent> addChunk(String chunk) {
    var text = _pending + chunk;
    // Hold back a trailing CR: it may be half of a CRLF split across chunks,
    // and eagerly converting it to LF would fabricate a frame boundary.
    var held = '';
    if (text.endsWith('\r')) {
      held = '\r';
      text = text.substring(0, text.length - 1);
    }
    // Normalize CRLF/CR line endings so frame splitting is a single '\n\n' scan.
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final events = <SseEvent>[];
    int sep;
    while ((sep = text.indexOf('\n\n')) >= 0) {
      final e = _parseFrame(text.substring(0, sep));
      text = text.substring(sep + 2);
      if (e != null) events.add(e);
    }
    _pending = text + held;
    return events;
  }

  static SseEvent? _parseFrame(String frame) {
    var event = 'message';
    final dataLines = <String>[];
    for (final line in frame.split('\n')) {
      if (line.startsWith(':')) continue; // comment (keepalive)
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trim());
      }
    }
    // Comment-only / empty frames carry nothing actionable.
    if (dataLines.isEmpty) return null;
    return SseEvent(event, dataLines.join('\n'));
  }
}
