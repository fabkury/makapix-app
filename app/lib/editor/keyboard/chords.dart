// Chord: the physical keystroke half of a keyboard Binding (CONTEXT.md "Keyboard vocabulary").
// A Chord is a trigger key plus modifier flags; "Primary" abstracts over the platform's command
// modifier (⌘ on Apple platforms, Ctrl elsewhere) so one default table serves every platform and
// stored bindings stay portable. Pure Dart over LogicalKeyboardKey — no widgets, no engine.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the Primary modifier is ⌘ (meta) on this platform. Follows
/// [defaultTargetPlatform] so tests can steer it via [debugDefaultTargetPlatformOverride].
bool primaryIsMeta() =>
    defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

/// A keystroke: one trigger key + modifier flags. Immutable value type.
@immutable
class Chord {
  final LogicalKeyboardKey key;
  final bool shift;
  final bool alt;
  final bool primary; // the platform command modifier (⌘ / Ctrl)

  const Chord(this.key, {this.shift = false, this.alt = false, this.primary = false});

  /// The Chord a key event represents right now, or null for a bare modifier press.
  /// The trigger key is normalized (numpad/shifted synonyms fold onto the canonical key)
  /// so bindings match regardless of which physical variant produced the logical key.
  static Chord? fromEvent(KeyEvent event) {
    final normalized = _normalize(event.logicalKey);
    if (normalized == null) return null; // a modifier by itself is not a Chord
    final hk = HardwareKeyboard.instance;
    final meta = hk.isMetaPressed, control = hk.isControlPressed;
    final primaryDown = primaryIsMeta() ? meta : control;
    final otherDown = primaryIsMeta() ? control : meta;
    if (otherDown) return null; // the non-Primary command modifier never participates
    return Chord(normalized, shift: hk.isShiftPressed, alt: hk.isAltPressed, primary: primaryDown);
  }

  @override
  bool operator ==(Object other) =>
      other is Chord &&
      other.key == key &&
      other.shift == shift &&
      other.alt == alt &&
      other.primary == primary;

  @override
  int get hashCode => Object.hash(key, shift, alt, primary);

  /// Wire format, e.g. "Primary+Shift+Z" — the 6.B bindings-file representation.
  String serialize() => [
        if (primary) 'Primary',
        if (alt) 'Alt',
        if (shift) 'Shift',
        _keyName(key),
      ].join('+');

  /// Parse the [serialize] format. Returns null on anything unrecognized (fail-soft:
  /// a corrupt stored chord falls back to the default binding, never crashes).
  static Chord? parse(String s) {
    var shift = false, alt = false, primary = false;
    LogicalKeyboardKey? key;
    for (final part in s.split('+')) {
      switch (part) {
        case 'Shift':
          shift = true;
        case 'Alt':
          alt = true;
        case 'Primary':
          primary = true;
        default:
          if (key != null) return null; // two trigger keys
          key = _keyByName[part];
          if (key == null) return null;
      }
    }
    if (key == null) return null;
    return Chord(key, shift: shift, alt: alt, primary: primary);
  }

  /// Human label with the platform's real modifier glyphs, for the cheat sheet.
  String display() => [
        if (primary) primaryIsMeta() ? '⌘' : 'Ctrl',
        if (alt) primaryIsMeta() ? '⌥' : 'Alt',
        if (shift) '⇧',
        _keyName(key),
      ].join(primaryIsMeta() ? '' : '+');

  @override
  String toString() => 'Chord(${serialize()})';
}

// Fold physical/shifted variants of a trigger key onto its canonical logical key, and reject
// bare modifiers. Layout quirks covered: some layouts deliver Shift+/ as `question` and
// Shift+= as `add`; the numpad has its own Enter/+/-/. keys.
LogicalKeyboardKey? _normalize(LogicalKeyboardKey key) {
  if (_bareModifiers.contains(key)) return null;
  return _synonyms[key] ?? key;
}

final _bareModifiers = <LogicalKeyboardKey>{
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};

final _synonyms = <LogicalKeyboardKey, LogicalKeyboardKey>{
  LogicalKeyboardKey.numpadEnter: LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadAdd: LogicalKeyboardKey.equal,
  LogicalKeyboardKey.add: LogicalKeyboardKey.equal,
  LogicalKeyboardKey.numpadSubtract: LogicalKeyboardKey.minus,
  LogicalKeyboardKey.question: LogicalKeyboardKey.slash,
  LogicalKeyboardKey.numpadDecimal: LogicalKeyboardKey.period,
};

// Names for the keys the default map uses (letters/digits come from keyLabel). The name table
// is the serialization vocabulary — additions are fine, renames are a bindings-file migration.
final _namedKeys = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.comma: ',',
  LogicalKeyboardKey.period: '.',
  LogicalKeyboardKey.slash: '/',
  LogicalKeyboardKey.bracketLeft: '[',
  LogicalKeyboardKey.bracketRight: ']',
  LogicalKeyboardKey.equal: '=',
  LogicalKeyboardKey.minus: '-',
};

String _keyName(LogicalKeyboardKey key) => _namedKeys[key] ?? key.keyLabel.toUpperCase();

final Map<String, LogicalKeyboardKey> _keyByName = {
  for (final e in _namedKeys.entries) e.value: e.key,
  for (var c = 0x41; c <= 0x5A; c++) // A–Z
    String.fromCharCode(c): LogicalKeyboardKey(0x61 + (c - 0x41)), // logical letters are lowercase code points
  for (var c = 0x30; c <= 0x39; c++) // 0–9
    String.fromCharCode(c): LogicalKeyboardKey(c),
};
