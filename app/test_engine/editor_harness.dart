// Pumps the REAL EditorPage — engine DLL and all — for the i18n sweeps of the editor
// (docs/i18n/TESTING.md, T4-E).
//
// The suite under app/test/ never loads the engine (CLAUDE.md), so the editor's own screen has
// no widget test there. This directory is a second suite that does load it:
//
//     cargo build -p makapix-ffi --release      # once, and after engine changes
//     flutter test test_engine
//
// `flutter test` runs with app/ as the working directory, and the engine loader already looks
// in ../target/release, so nothing needs configuring. The plugins the editor touches at startup
// (path_provider, shared_preferences) are faked; drawings land in a temp folder per test.
// ignore_for_file: invalid_use_of_visible_for_testing_member
// (the analyzer only treats app/test/ as test code; this suite lives beside it)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/editor_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/l10n/club_fixtures.dart';
import '../test/l10n/l10n_test_support.dart';

export '../test/l10n/l10n_test_support.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

/// Points path_provider at a fresh temp folder (removed when the test ends).
Directory fakeAppDirs(WidgetTester tester) {
  final dir = Directory.systemTemp.createTempSync('mkpx_l10n_');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_pathProvider, (call) async => dir.path);
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_pathProvider, null);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return dir;
}

/// Lets real asynchronous work finish — file I/O, image decodes — which the fake clock of a
/// widget test never advances on its own.
Future<void> settleReal(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// One line for a caught exception: its first line, plus the widget chain of a layout overflow
/// ("creator: Row ← Padding ← …"), which says where it is.
String describeException(Object err) {
  final lines = err.toString().split('\n');
  final creator = lines.map((l) => l.trim()).where((l) => l.startsWith('creator:')).firstOrNull;
  return creator == null ? lines.first : '${lines.first} ($creator)';
}

/// Pumps the real editor in [locale] on a [size] screen and waits for its first drawing.
Future<void> pumpEditor(
  WidgetTester tester,
  Locale locale, {
  Size size = const Size(412, 915),
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final dir = fakeAppDirs(tester);
  await pumpLocalized(
    tester,
    locale,
    const EditorPage(),
    size: size,
    overrides: clubOverrides(signedIn: false),
    textScale: kSweepTextScale,
  );
  // The editor restores (or creates) its drawing asynchronously after the first frame. Wait
  // for the drawing to reach disk — unmounting earlier than that races the startup code.
  for (var i = 0; i < 100; i++) {
    await settleReal(tester, rounds: 1);
    if (dir.listSync(recursive: true).any((f) => f.path.endsWith('.mkpx'))) break;
  }
  await settleReal(tester, rounds: 4);
}

/// Unmounts the editor and lets its teardown (final autosave, journal drain) finish, so no
/// timer or file handle outlives the test.
Future<void> closeEditor(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await settleReal(tester, rounds: 4);
}
