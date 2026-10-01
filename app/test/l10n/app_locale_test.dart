// T3 (docs/i18n/TESTING.md): which language the app shows — the device's by default, the
// user's pick when there is one — and that the pick survives a restart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/app.dart';
import 'package:makapix_club/l10n/app_locale.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:makapix_club/ui/language_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_support.dart';

Locale _resolve(List<Locale> device) => resolveAppLocale(device, allLocales);

void main() {
  group('resolveAppLocale', () {
    test('the device language wins when the app has it, whatever the region', () {
      expect(_resolve([const Locale('pt', 'BR')]), const Locale('pt'));
      expect(_resolve([const Locale('pt', 'PT')]), const Locale('pt'));
      expect(_resolve([const Locale('es', 'MX')]), const Locale('es'));
      expect(_resolve([const Locale('de', 'AT')]), const Locale('de'));
      expect(_resolve([const Locale('fr', 'CA')]), const Locale('fr'));
      expect(_resolve([const Locale('ru', 'RU')]), const Locale('ru'));
      expect(_resolve([const Locale('ja', 'JP')]), const Locale('ja'));
      expect(_resolve([const Locale('en', 'GB')]), const Locale('en'));
    });

    test('any Chinese resolves to Simplified (the only Chinese the app has)', () {
      expect(_resolve([const Locale('zh', 'CN')]), const Locale('zh'));
      expect(
          _resolve([const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN')]),
          const Locale('zh'));
      expect(
          _resolve([const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')]),
          const Locale('zh'));
    });

    test('an untranslated language falls through to the next preference, then English', () {
      expect(_resolve([const Locale('ko', 'KR')]), const Locale('en'));
      expect(_resolve([const Locale('ko', 'KR'), const Locale('ja', 'JP')]), const Locale('ja'));
      expect(_resolve([const Locale('it'), const Locale('nl'), const Locale('pt', 'BR'), const Locale('en')]),
          const Locale('pt'));
      expect(_resolve([]), const Locale('en'));
      expect(resolveAppLocale(null, allLocales), const Locale('en'));
    });

    test('a build offering English only resolves everything to English', () {
      expect(resolveAppLocale([const Locale('de')], const [Locale('en')]), const Locale('en'));
    });
  });

  group('AppLocalePrefs', () {
    test('decode accepts only languages the app offers', () {
      expect(AppLocalePrefs.decode(null), isNull);
      expect(AppLocalePrefs.decode(''), isNull);
      expect(AppLocalePrefs.decode('pt'), const Locale('pt'));
      expect(AppLocalePrefs.decode('zh'), const Locale('zh'));
      expect(AppLocalePrefs.decode('ko'), isNull, reason: 'a language since removed follows the device');
      expect(AppLocalePrefs.decode('not a tag'), isNull);
    });

    test('a pick round-trips through preferences; clearing it follows the device again', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AppLocalePrefs.read(), isNull);
      await AppLocalePrefs.write(const Locale('ja'));
      expect(await AppLocalePrefs.read(), const Locale('ja'));
      await AppLocalePrefs.write(null);
      expect(await AppLocalePrefs.read(), isNull);
      expect((await SharedPreferences.getInstance()).containsKey(AppLocalePrefs.key), isFalse);
    });
  });

  group('the app root', () {
    // A stand-in for the app shell: it only reports the language it was built in.
    Widget probe(List<Override> overrides) => ProviderScope(
          overrides: overrides,
          child: Consumer(builder: (context, ref, _) {
            final supported = availableLocales;
            return MaterialApp(
              locale: ref.watch(appLocaleProvider),
              supportedLocales: supported,
              localizationsDelegates: kAppLocalizationsDelegates,
              localeListResolutionCallback: (preferred, _) => resolveAppLocale(preferred, supported),
              builder: (context, child) => L10nBinding(child: child!),
              home: Builder(builder: (context) => Text(context.l10n.settingsTitle)),
            );
          }),
        );

    testWidgets('follows the device language', (tester) async {
      addTearDown(debugResetAppL10n);
      tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(probe(const []));
      await tester.pump();
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(appL10n.localeName, 'de', reason: 'context-free code sees the same language');
    });

    testWidgets('re-resolves when the device language changes while running', (tester) async {
      addTearDown(debugResetAppL10n);
      tester.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(probe(const []));
      await tester.pump();
      expect(find.text('Paramètres'), findsOneWidget);
      tester.platformDispatcher.localesTestValue = const [Locale('es', 'ES')];
      await tester.pump();
      await tester.pump();
      expect(find.text('Ajustes'), findsOneWidget);
    });

    testWidgets('the pick beats the device language', (tester) async {
      addTearDown(debugResetAppL10n);
      tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(probe([initialAppLocaleProvider.overrideWithValue(const Locale('ja'))]));
      await tester.pump();
      expect(find.text('設定'), findsOneWidget);
    });

    testWidgets('an unsupported device language shows English', (tester) async {
      addTearDown(debugResetAppL10n);
      tester.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(probe(const []));
      await tester.pump();
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('LanguagePage', () {
    Future<ProviderContainer> pumpPicker(WidgetTester tester, {Locale device = const Locale('en', 'US')}) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(debugResetAppL10n);
      tester.platformDispatcher.localesTestValue = [device];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      setSurface(tester, const Size(360, 740));
      late ProviderContainer container;
      await tester.pumpWidget(ProviderScope(
        child: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          final supported = availableLocales;
          return MaterialApp(
            locale: ref.watch(appLocaleProvider),
            supportedLocales: supported,
            localizationsDelegates: kAppLocalizationsDelegates,
            localeListResolutionCallback: (preferred, _) => resolveAppLocale(preferred, supported),
            home: const LanguagePage(),
          );
        }),
      ));
      await tester.pump();
      return container;
    }

    testWidgets('lists every language by its own name, plus System default', (tester) async {
      await pumpPicker(tester);
      for (final l in kAppLanguages) {
        expect(find.text(l.endonym), findsWidgets, reason: l.endonym);
      }
      expect(find.text('System default'), findsOneWidget);
      expect(find.text('Follows your device: English'), findsOneWidget);
    });

    testWidgets('picking a language switches the app at once and saves the pick', (tester) async {
      final container = await pumpPicker(tester);
      await tester.tap(find.byKey(const ValueKey('language-pt')));
      await tester.pumpAndSettle();
      expect(container.read(appLocaleProvider), const Locale('pt'));
      expect(find.text('Idioma'), findsOneWidget, reason: 'the page itself is now in Portuguese');
      expect(find.text('Padrão do sistema'), findsOneWidget);
      expect(await AppLocalePrefs.read(), const Locale('pt'));

      // Back to System default: follows the (English) device again and forgets the pick.
      await tester.tap(find.byKey(const ValueKey('language-system')));
      await tester.pumpAndSettle();
      expect(container.read(appLocaleProvider), isNull);
      expect(find.text('Language'), findsOneWidget);
      expect(await AppLocalePrefs.read(), isNull);
    });

    testWidgets('System default names the language the device resolves to', (tester) async {
      await pumpPicker(tester, device: const Locale('ru', 'RU'));
      expect(find.text('Как на устройстве: Русский'), findsOneWidget);
    });
  });
}
