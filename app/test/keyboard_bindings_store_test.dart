// The stored-bindings resolver (keyboard/bindings_store.dart): overrides merge over defaults,
// the core four can be remapped but never unbound, and every malformed input fails soft to the
// defaults — a broken file must never cost the artist their keyboard.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/keyboard/bindings_store.dart';
import 'package:makapix_club/editor/keyboard/chords.dart';
import 'package:makapix_club/editor/keyboard/default_bindings.dart';

String doc(Map<String, dynamic> bindings, {int version = kBindingsSchemaVersion}) =>
    jsonEncode({'version': version, 'bindings': bindings});

void main() {
  final defaults = defaultBindings();

  test('no file → defaults, verbatim', () {
    expect(resolveBindings(null, defaults), same(defaults));
  });

  test('an override replaces the default chords', () {
    final r = resolveBindings(doc({'tool.pencil': 'Q'}), defaults);
    expect(r['tool.pencil'], [const Chord(LogicalKeyboardKey.keyQ)]);
    expect(r['tool.brush'], defaults['tool.brush']); // untouched neighbors keep defaults
  });

  test('null unbinds a non-core command', () {
    final r = resolveBindings(doc({'sheet.layers': null}), defaults);
    expect(r['sheet.layers'], isEmpty);
  });

  test('the core four ignore null (rebindable, never unbindable)', () {
    final r = resolveBindings(
        doc({'edit.undo': null, 'edit.redo': null, 'draft.commit': null, 'draft.cancel': null}),
        defaults);
    for (final id in ['edit.undo', 'edit.redo', 'draft.commit', 'draft.cancel']) {
      expect(r[id], defaults[id], reason: id);
    }
  });

  test('a core command CAN be remapped', () {
    final r = resolveBindings(doc({'edit.undo': 'Primary+U'}), defaults);
    expect(r['edit.undo'], [const Chord(LogicalKeyboardKey.keyU, primary: true)]);
  });

  test('unknown ids, bad chords, and wrong value shapes are ignored', () {
    final r = resolveBindings(
        doc({'no.such.command': 'Q', 'tool.brush': 'NotAKey+Q', 'tool.eraser': 42}), defaults);
    expect(r['tool.brush'], defaults['tool.brush']);
    expect(r['tool.eraser'], defaults['tool.eraser']);
    expect(r.containsKey('no.such.command'), isFalse);
  });

  test('corrupt JSON, wrong shapes, and future versions fail soft to defaults', () {
    expect(resolveBindings('{oops', defaults), same(defaults));
    expect(resolveBindings('[1,2,3]', defaults), same(defaults));
    expect(resolveBindings(jsonEncode({'bindings': {}}), defaults), same(defaults));
    expect(resolveBindings(doc({'tool.pencil': 'Q'}, version: 99), defaults), same(defaults));
  });
}
