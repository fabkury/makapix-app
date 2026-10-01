// The screen sweep (docs/i18n/TESTING.md, T4): pump one screen in every language on every
// screen size and hold it to the same three rules each time.
//
//   1. It lays out: no overflow, no exception. (flutter_test turns a RenderFlex overflow into
//      a test failure on its own.)
//   2. No text is cut off — a translation must fit where the English fits.
//   3. Nothing is left in English: in Japanese, Chinese, and Russian any Latin word that is
//      not a brand, format, or unit is a miss; in Spanish, Portuguese, French, and German any
//      text identical to an English message whose translation differs is a miss.
//
// A screen registers once with [sweepScreen]; the cross product is generated here.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'club_fixtures.dart';
import 'l10n_test_support.dart';

const _nonLatinScript = {'ja', 'zh', 'ru'};

/// Registers the sweep tests for one screen state.
///
/// [name] identifies the screen and state ("Settings, signed in"). [build] returns the widget
/// under test. [overrides] are the Riverpod overrides it needs. [act] runs after the first
/// pump (open a menu, scroll, tap a tab) so the state under test is on screen. [allowLatin]
/// lists fixture text; [allowTruncated] lists texts that are cut off by design in every
/// language (user content shown with an ellipsis). [sizes] narrows the screen sizes.
void sweepScreen(
  String name, {
  required Widget Function() build,
  List<Override> Function()? overrides,
  Future<void> Function(WidgetTester tester)? act,
  Iterable<Pattern> allowLatin = const [],
  Iterable<Pattern> allowTruncated = const [],
  Map<String, Size>? sizes,
  Map<String, Object> prefs = const {},
}) {
  group('sweep: $name', () {
    for (final locale in allLocales) {
      for (final size in (sizes ?? kSweepSizes).entries) {
        testWidgets('$locale @ ${size.key}', (tester) async {
          SharedPreferences.setMockInitialValues(prefs);
          await pumpLocalized(
            tester,
            locale,
            ProviderScope(overrides: overrides?.call() ?? const [], child: build()),
            size: size.value,
          );
          // Settle one-shot async state (FutureProviders, post-frame callbacks) without
          // waiting on spinners: a few fixed pumps (editor-test-gotchas).
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          if (act != null) {
            await act(tester);
            for (var i = 0; i < 4; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
          }

          final cut = truncatedTexts(tester)
              .where((t) => !allowTruncated.any((a) => a.allMatches(t.text).isNotEmpty))
              .toList();
          expect(cut, isEmpty, reason: 'text cut off');

          final lang = locale.languageCode;
          if (_nonLatinScript.contains(lang)) {
            expect(leftoverLatin(tester, allow: [...kFixtureText, ...allowLatin]), isEmpty,
                reason: 'Latin-script text on a $lang screen');
          } else if (lang != 'en') {
            expect(leftoverEnglish(tester, lang), isEmpty,
                reason: 'English wording on a $lang screen');
          }
        });
      }
    }
  });
}
