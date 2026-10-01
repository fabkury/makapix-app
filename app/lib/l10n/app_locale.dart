// Which language the app shows (docs/i18n/DESIGN.md §3): the device's language by default,
// or the one the user picked in Settings → Language. The choice is device-local (shared
// preferences), read once in `main()` before the first frame so the app never flashes the
// wrong language, and applied live — switching rebuilds the tree, no restart.
// l10n-ignore-file: the endonyms below are shown as-is in every language.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A language the app is translated into.
class AppLanguage {
  const AppLanguage(this.locale, this.endonym);
  final Locale locale;

  /// The language's own name for itself — what the picker shows, in every UI language.
  final String endonym;
}

/// Every translated language, in picker order (Latin-script names A→Z, then the rest).
/// `zh` is Simplified Chinese; Traditional would be a separate `zh_Hant` entry.
const List<AppLanguage> kAppLanguages = [
  AppLanguage(Locale('de'), 'Deutsch'),
  AppLanguage(Locale('en'), 'English'),
  AppLanguage(Locale('es'), 'Español'),
  AppLanguage(Locale('fr'), 'Français'),
  AppLanguage(Locale('pt'), 'Português (Brasil)'),
  AppLanguage(Locale('ru'), 'Русский'),
  AppLanguage(Locale('ja'), '日本語'),
  AppLanguage(Locale('zh'), '简体中文'),
];

const Locale kFallbackLocale = Locale('en');

/// The release switch for the translations. While the string extraction is in progress
/// (docs/i18n/PLAN.md) a release build ships English only — a half-translated screen is worse
/// than an English one. Debug builds and tests always see every language, and a release build
/// can preview them with `--dart-define=L10N_PREVIEW=true`. Flip to `true` at milestone L4.
const bool kTranslationsShipped = false;

const bool _preview = bool.fromEnvironment('L10N_PREVIEW');

/// The languages this build offers.
List<AppLanguage> get availableLanguages => (kTranslationsShipped || _preview || !kReleaseMode)
    ? kAppLanguages
    : kAppLanguages.where((l) => l.locale == kFallbackLocale).toList();

/// `supportedLocales` for the `MaterialApp`: English first (Flutter's own last-resort fallback).
List<Locale> get availableLocales => [
      kFallbackLocale,
      for (final l in availableLanguages)
        if (l.locale != kFallbackLocale) l.locale,
    ];

AppLanguage languageFor(Locale locale) => kAppLanguages.firstWhere(
      (l) => l.locale.languageCode == locale.languageCode,
      orElse: () => kAppLanguages.firstWhere((l) => l.locale == kFallbackLocale),
    );

/// The language to show for a device whose preferred languages are [preferred] (most wanted
/// first): the first one the app is translated into, matched by language alone — `pt-PT` gets
/// Portuguese, `es-MX` Spanish, any Chinese gets Simplified — else English.
Locale resolveAppLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  for (final want in preferred ?? const <Locale>[]) {
    for (final have in supported) {
      if (have.languageCode == want.languageCode) return have;
    }
  }
  return kFallbackLocale;
}

/// Persistence of the user's explicit choice. Absent or unknown = follow the device.
class AppLocalePrefs {
  AppLocalePrefs._();

  static const String key = 'app.locale_v1';

  /// The saved choice, or null to follow the device. Never throws and never waits long.
  static Future<Locale?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      return decode(prefs.getString(key));
    } catch (e) {
      debugPrint('[locale] read skipped: $e');
      return null;
    }
  }

  /// A stored tag is honored only while this build still offers that language.
  @visibleForTesting
  static Locale? decode(String? tag) {
    if (tag == null || tag.isEmpty) return null;
    for (final l in availableLanguages) {
      if (l.locale.toLanguageTag() == tag) return l.locale;
    }
    return null;
  }

  static Future<void> write(Locale? locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, locale.toLanguageTag());
      }
    } catch (e) {
      debugPrint('[locale] write skipped: $e');
    }
  }
}

/// The choice read in `main()`; overridden there. Null = follow the device.
final initialAppLocaleProvider = Provider<Locale?>((_) => null);

/// The user's explicit language, or null to follow the device.
class AppLocaleController extends StateNotifier<Locale?> {
  AppLocaleController(super.initial);

  Future<void> set(Locale? locale) async {
    state = locale; // apply live first; persistence is best-effort
    await AppLocalePrefs.write(locale);
  }
}

final appLocaleProvider = StateNotifierProvider<AppLocaleController, Locale?>(
    (ref) => AppLocaleController(ref.watch(initialAppLocaleProvider)));
