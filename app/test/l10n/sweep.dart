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

/// A bare screen with one button, for sweeping a sheet or dialog: the sweep's `act` calls
/// [tapOpener], which runs [open] with a live context and ref.
class Opener extends ConsumerWidget {
  const Opener(this.open, {super.key});
  final void Function(BuildContext context, WidgetRef ref) open;

  static const ValueKey<String> buttonKey = ValueKey('sweep-opener');

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: IconButton(
            key: buttonKey,
            icon: const Icon(Icons.open_in_new),
            onPressed: () => open(context, ref),
          ),
        ),
      );
}

Future<void> tapOpener(WidgetTester tester) => tester.tap(find.byKey(Opener.buttonKey));

/// Lets a menu, sheet, or dialog that was just opened finish its animation, so the next tap
/// lands on what it shows. One long `pump` is not enough: the animation only starts on the
/// first frame after the tap.
Future<void> settleOpen(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Registers the sweep tests for one screen state.
///
/// [name] identifies the screen and state ("Settings, signed in"). [build] returns the widget
/// under test. [overrides] are the Riverpod overrides it needs; it receives the [backend] this
/// test created (a fresh fake per test), to hand to `clubOverrides`. [act] runs after the first
/// pump (open a menu, scroll, tap a tab) so the state under test is on screen. [allowLatin]
/// lists fixture text; [allowEnglish] lists texts that read the same in every language but
/// happen to equal an English message (a key letter such as "W"); [allowTruncated] lists texts
/// that are cut off by design in every language (user content shown with an ellipsis). [sizes] narrows the screen sizes. [drain]
/// unmounts the screen at the end and lets that much time pass, for screens that keep a timer.
void sweepScreen(
  String name, {
  required Widget Function() build,
  List<Override> Function(FakeBackend? backend)? overrides,
  Future<void> Function(WidgetTester tester)? act,
  Iterable<Pattern> allowLatin = const [],
  Iterable<Pattern> allowEnglish = const [],
  Iterable<Pattern> allowTruncated = const [],
  Map<String, Size>? sizes,
  Map<String, Object> prefs = const {},
  FakeBackend Function()? backend,
  Duration? drain,
}) {
  group('sweep: $name', () {
    for (final locale in allLocales) {
      for (final size in (sizes ?? kSweepSizes).entries) {
        testWidgets('$locale @ ${size.key}', (tester) async {
          // A tap that lands on nothing leaves the screen in the wrong state and the checks
          // pass on a screen nobody asked about: make it a failure, not a warning.
          WidgetController.hitTestWarningShouldBeFatal = true;
          addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
          SharedPreferences.setMockInitialValues(prefs);
          final fake = backend?.call();
          await pumpLocalized(
            tester,
            locale,
            build(),
            size: size.value,
            overrides: overrides?.call(fake) ?? const [],
          );
          // Settle one-shot async state (FutureProviders, post-frame callbacks) without
          // waiting on spinners: a few fixed pumps (editor-test-gotchas).
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          if (act != null) {
            await act(tester);
            // Long enough for a menu, sheet, or dialog to finish opening (300 ms).
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
          }

          // One picture per language, at the common phone size, for the visual review (T6).
          // Taken before the checks so a failing screen is on disk to look at.
          if (size.key == 'phone') {
            final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
            await screenshot(tester, '${slug}_${locale.languageCode}');
          }

          expect(fake?.unhandled ?? const [], isEmpty,
              reason: 'requests the fake backend has no route for');

          final cut = truncatedTexts(tester)
              .where((t) => !allowTruncated.any((a) => a.allMatches(t.text).isNotEmpty))
              // Fixture content (an email address, a handle) is user text: one long unbreakable
              // string of it splitting across lines is not a translation's doing.
              .where((t) => !(t.brokenWord && kFixtureText.any((f) => t.text.contains(f))))
              .toList();
          expect(cut, isEmpty, reason: 'text cut off');

          final lang = locale.languageCode;
          if (_nonLatinScript.contains(lang)) {
            expect(leftoverLatin(tester, allow: [...kFixtureText, ...allowLatin]), isEmpty,
                reason: 'Latin-script text on a $lang screen');
          } else if (lang != 'en') {
            final english = leftoverEnglish(tester, lang)
                .where((t) => !allowEnglish.any((a) => a.allMatches(t).isNotEmpty))
                .toList();
            expect(english, isEmpty, reason: 'English wording on a $lang screen');
          }

          // A screen that polls leaves its next tick scheduled; unmount and let it run out.
          if (drain != null) {
            await tester.pumpWidget(const SizedBox());
            await tester.pump(drain);
          }
        });
      }
    }
  });
}
