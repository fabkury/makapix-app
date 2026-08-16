// The stored-bindings loader (DESIGN.md §2.6): keyboard_bindings.json in the app-support
// directory, merged over the platform defaults. V1 ships the loader and schema so phase 6.B's
// rebinding UI bolts on without a migration; nothing writes the file yet. Fail-soft like the
// rest of _initPersistence: a missing, corrupt, or future-versioned file leaves the defaults
// untouched — a broken bindings file must never cost the artist their keyboard.
import 'dart:convert';
import 'dart:io';

import 'chords.dart';
import 'commands.dart';
import 'default_bindings.dart';

const kBindingsFileName = 'keyboard_bindings.json';
const kBindingsSchemaVersion = 1;

/// Merge a stored bindings JSON document over [defaults]. Per entry: a chord string replaces
/// the Command's default Chords; `null` unbinds — except for the core four (CONTEXT.md
/// decision: rebindable, never unbindable), where `null` is ignored. Unknown ids, unparsable
/// chords, wrong shapes, and unknown schema versions are all ignored (defaults win).
BindingTable resolveBindings(String? jsonText, BindingTable defaults) {
  if (jsonText == null) return defaults;
  Object? doc;
  try {
    doc = jsonDecode(jsonText);
  } catch (_) {
    return defaults;
  }
  if (doc is! Map<String, dynamic>) return defaults;
  if (doc['version'] != kBindingsSchemaVersion) return defaults; // future migrations hook here
  final stored = doc['bindings'];
  if (stored is! Map<String, dynamic>) return defaults;
  final out = {for (final e in defaults.entries) e.key: List<Chord>.of(e.value)};
  stored.forEach((id, value) {
    if (!out.containsKey(id)) return; // unknown (or retired) Command: keep for 6.B migration
    if (value == null) {
      if (!coreCommandIds.contains(id)) out[id] = const [];
      return;
    }
    if (value is! String) return;
    final chord = Chord.parse(value);
    if (chord != null) out[id] = [chord];
  });
  return out;
}

/// Read and merge `keyboard_bindings.json` from [supportDir]. Missing file → defaults.
Future<BindingTable> loadBindings(Directory supportDir, BindingTable defaults) async {
  try {
    final f = File('${supportDir.path}${Platform.pathSeparator}$kBindingsFileName');
    if (!await f.exists()) return defaults;
    return resolveBindings(await f.readAsString(), defaults);
  } catch (_) {
    return defaults; // fail-soft: I/O trouble must not break the editor
  }
}
