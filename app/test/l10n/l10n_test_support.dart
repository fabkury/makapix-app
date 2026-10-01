// Shared harness for the i18n test layers (docs/i18n/TESTING.md).
//
// What it gives a test:
//   * real font metrics — Roboto from the Flutter SDK cache (Latin, Cyrillic: the widths an
//     Android phone lays out) plus a CJK font from the operating system as glyph fallback.
//     Without these, flutter_test draws every glyph as a 1-em square, or — worse for a fit
//     check — draws glyphs a font lacks as its narrow "missing glyph" box;
//   * [pumpLocalized] — pump a widget under the app's theme and delegates, in one language, on
//     one screen size;
//   * [truncatedTexts] — every laid-out text that does not fit its box;
//   * [leftoverEnglish] — text still in English on a screen pumped in another language.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/app.dart';
import 'package:makapix_club/l10n/app_locale.dart';
import 'package:makapix_club/l10n/l10n.dart';

/// Every language the app is translated into.
List<Locale> get allLocales => [for (final l in kAppLanguages) l.locale];

/// The screens a layout check runs on: the narrowest phone still in use, a common Android
/// phone, a large phone, a tablet in portrait, and a desktop window.
const Map<String, Size> kSweepSizes = {
  'phone-small': Size(320, 568),
  'phone': Size(360, 740),
  'phone-large': Size(412, 915),
  'tablet': Size(800, 1280),
  'desktop': Size(1280, 800),
};

bool _fontsLoaded = false;

/// The family the harness registers its CJK fallback font under.
const String kTestCjkFamily = 'L10nTestCJK';

/// A font with Chinese and Japanese glyphs, from the operating system. Which one does not
/// matter for layout — CJK glyphs are 1 em wide in all of them — but one must exist.
const List<String> _cjkFontCandidates = [
  r'C:\Windows\Fonts\Noto Sans SC.ttf',
  r'C:\Windows\Fonts\msyh.ttc', // Microsoft YaHei: ships with every Windows 10/11
  r'C:\Windows\Fonts\YuGothM.ttc',
  '/System/Library/Fonts/PingFang.ttc',
  '/System/Library/Fonts/Hiragino Sans GB.ttc',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
];

/// Registers Roboto (the Android system font, and Material's default family under test) and a
/// CJK fallback, so text is measured with real advances.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  final cjk = _cjkFontCandidates.map(File.new).where((f) => f.existsSync()).firstOrNull;
  if (cjk == null) {
    fail('No CJK system font found (looked for: ${_cjkFontCandidates.join(', ')}). '
        'The l10n layout tests need one to measure Chinese and Japanese text.');
  }
  final cjkLoader = FontLoader(kTestCjkFamily)
    ..addFont(Future.value(ByteData.sublistView(cjk.readAsBytesSync())));
  await cjkLoader.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    fail('FLUTTER_ROOT is not set — run these tests through `flutter test`.');
  }
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final loader = FontLoader('Roboto');
  var n = 0;
  for (final name in const [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-light.ttf',
    'roboto-italic.ttf',
  ]) {
    final f = File('${dir.path}/$name');
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
    n++;
  }
  if (n == 0) fail('Roboto not found under ${dir.path}');
  await loader.load();
  // The icon font, so screenshots show icons instead of empty boxes.
  final icons = File('${dir.path}/materialicons-regular.otf');
  if (icons.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await iconLoader.load();
  }
  _fontsLoaded = true;
}

/// Wraps [child] the way the app does: its theme, its localization delegates, [locale].
Widget localizedApp(Locale locale, Widget child) => MaterialApp(
      key: UniqueKey(), // a fresh Navigator per pump (editor-test-gotchas)
      debugShowCheckedModeBanner: false,
      theme: makapixTheme(fontFamilyFallback: const [kTestCjkFamily]),
      locale: locale,
      supportedLocales: allLocales,
      localizationsDelegates: kAppLocalizationsDelegates,
      builder: (context, c) => RepaintBoundary(
        key: _shotKey,
        child: L10nBinding(child: c ?? const SizedBox.shrink()),
      ),
      home: child,
    );

final GlobalKey _shotKey = GlobalKey(debugLabel: 'l10n screenshot');

/// Where [screenshot] writes: app/build/l10n_shots/ (git-ignored build output).
const String kShotDir = 'build/l10n_shots';

/// Saves the screen pumped by [pumpLocalized] as `build/l10n_shots/<name>.png`, at 2× so small
/// type stays legible. The pictures are for looking at — the review step of T6 — not goldens:
/// nothing compares them.
Future<void> screenshot(WidgetTester tester, String name) async {
  final boundary = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$kShotDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Sets the test surface to [size] logical pixels at 1× (restored when the test ends).
void setSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps [child] in [locale] on a [size] screen, with real fonts.
///
/// As in the app, the `ProviderScope` sits above the `MaterialApp`, so sheets, dialogs, and
/// pushed routes see the same providers (and [overrides]) as the screen that opened them.
Future<void> pumpLocalized(WidgetTester tester, Locale locale, Widget child,
    {Size size = const Size(360, 740), List<Override> overrides = const []}) async {
  await loadAppFonts();
  setSurface(tester, size);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: localizedApp(locale, child)));
  await tester.pump();
  addTearDown(debugResetAppL10n);
}

/// The strings of [locale], without a widget tree.
AppLocalizations l10nFor(Locale locale) => lookupAppLocalizations(locale);

/// A laid-out text that does not fit its box.
class Truncated {
  Truncated(this.text, this.box, this.needed);
  final String text;
  final Size box;
  final double needed;
  @override
  String toString() =>
      '"$text" needs ${needed.toStringAsFixed(1)} px, has ${box.width.toStringAsFixed(1)} px';
}

/// Each laid-out paragraph once (`allRenderObjects` repeats a render object for every element
/// that resolves to it).
Iterable<RenderParagraph> paragraphs(WidgetTester tester) => {
      for (final ro in tester.allRenderObjects)
        if (ro is RenderParagraph && ro.attached) ro,
    };

/// Every text on screen that is cut off: it ran past its last allowed line, or (single-line)
/// it is wider than its box. A translated label must never be here.
List<Truncated> truncatedTexts(WidgetTester tester) {
  final out = <Truncated>[];
  for (final ro in paragraphs(tester)) {
    if (!ro.hasSize) continue;
    final text = ro.text.toPlainText();
    if (_withoutIconGlyphs(text).trim().isEmpty) continue; // an Icon, not a label
    final natural = ro.getMaxIntrinsicWidth(double.infinity);
    final singleLine = ro.maxLines == 1 || !ro.softWrap;
    final tooWide = singleLine && natural > ro.size.width + 0.5;
    if (ro.didExceedMaxLines || tooWide) {
      out.add(Truncated(text, ro.size, natural));
    }
  }
  return out;
}

/// Icons are text too (a glyph from an icon font, in the Unicode private-use areas).
String _withoutIconGlyphs(String s) => String.fromCharCodes(s.runes.where((r) =>
    !(r >= 0xE000 && r <= 0xF8FF) && !(r >= 0xF0000 && r <= 0x10FFFF)));

/// All text currently laid out: paragraphs, plus tooltip messages.
List<String> visibleTexts(WidgetTester tester) {
  final out = <String>[];
  for (final ro in paragraphs(tester)) {
    final t = _withoutIconGlyphs(ro.text.toPlainText()).trim();
    if (t.isNotEmpty) out.add(t);
  }
  for (final w in tester.allWidgets) {
    if (w is Tooltip) {
      final m = w.message ?? w.richMessage?.toPlainText();
      if (m != null && m.trim().isNotEmpty) out.add(m.trim());
    }
  }
  return out;
}

/// Words that stay in Latin script in every language: brand and product names, file formats,
/// units, and color-model abbreviations (docs/i18n/GLOSSARY.md "Never translated").
const Set<String> kNeverTranslated = {
  'makapix', 'club', 'editor', 'github', 'apple', 'google', 'android', 'ios', 'windows',
  'mkpx', 'png', 'gif', 'webp', 'apng', 'jpeg', 'jpg', 'bmp', 'mp4', 'gpl', 'aseprite',
  'hsv', 'rgb', 'rgba', 'hex', 'aa', 'px', 'ms', 'fps', 'kib', 'mib', 'gib', 'ok', 'url',
  'nsfw', 'id', 'cc', 'by', 'sa', 'nc', 'nd',
};

final RegExp _latinWord = RegExp(r'[A-Za-z]{3,}');

/// Texts on a screen pumped in a non-Latin-script language ([locale] ja / zh / ru) that still
/// contain Latin words: a string the extraction missed, or one never translated. [allow] lists
/// fixture content (user names, post titles) the test itself put on screen.
List<String> leftoverLatin(WidgetTester tester, {Iterable<Pattern> allow = const []}) {
  final out = <String>[];
  for (final t in visibleTexts(tester)) {
    var s = t;
    for (final a in allow) {
      s = s.replaceAll(a, ' ');
    }
    final words = _latinWord
        .allMatches(s)
        .map((m) => m.group(0)!.toLowerCase())
        .where((w) => !kNeverTranslated.contains(w));
    if (words.isNotEmpty) out.add(t);
  }
  return out;
}

/// The messages of one ARB file, without the `@` metadata entries.
Map<String, String> readArb(String locale) {
  final raw = jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

/// The `@key` metadata of the English template.
Map<String, Map<String, dynamic>> readArbMeta() {
  final raw = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      if (e.key.startsWith('@') && !e.key.startsWith('@@'))
        e.key.substring(1): (e.value as Map).cast<String, dynamic>(),
  };
}

/// Texts on a screen pumped in a Latin-script language (es / pt / fr / de) that are still the
/// English wording: the rendered text equals an English message whose [locale] translation
/// is different.
List<String> leftoverEnglish(WidgetTester tester, String locale) {
  final en = readArb('en');
  final tr = readArb(locale);
  final englishOnly = <String>{
    for (final e in en.entries)
      if (tr[e.key] != e.value && !tr.containsValue(e.value)) e.value,
  };
  return [
    for (final t in visibleTexts(tester))
      if (englishOnly.contains(t)) t,
  ];
}
