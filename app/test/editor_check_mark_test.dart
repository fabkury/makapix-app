// A selected option chip shows one check mark: Material's own (the FilterChip draws it). The
// editor once also appended "✔" to the label, so selected chips read "✓ AA ✔" (fixed
// 2026-10-02). This keeps the text mark from coming back anywhere in the editor.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no text check mark in the editor; chips rely on Material’s', () {
    final offenders = [
      for (final f in Directory('lib/editor').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && f.readAsStringSync().contains('✔')) f.path,
    ];
    expect(offenders, isEmpty);
  });
}
