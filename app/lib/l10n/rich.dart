// Emphasis inside a translated sentence.
//
// A sentence with a bold phrase in the middle cannot be three messages glued together — the
// phrase sits elsewhere in other languages, or the sentence is not split at all. The message
// carries the emphasis itself, as `<b>…</b>`, and the translator moves the tags with the words:
//
//   "We have <b>zero tolerance</b> for objectionable content."
//   "Wir dulden <b>keinerlei</b> anstößige Inhalte."
import 'package:flutter/widgets.dart';

final RegExp _bold = RegExp(r'<b>(.*?)</b>', dotAll: true);

/// The spans of [message], with each `<b>…</b>` run in bold.
List<InlineSpan> boldSpans(String message) {
  final out = <InlineSpan>[];
  var at = 0;
  for (final m in _bold.allMatches(message)) {
    if (m.start > at) out.add(TextSpan(text: message.substring(at, m.start)));
    out.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.bold)));
    at = m.end;
  }
  if (at < message.length) out.add(TextSpan(text: message.substring(at)));
  return out;
}
