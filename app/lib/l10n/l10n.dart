// How code reaches the translated strings (docs/i18n/DESIGN.md §3).
//
//   * Widgets:            `context.l10n.settingsTitle`
//   * Context-free code:  `appL10n.someMessage` — controllers, validators, and API error mappers
//                         that build a message with no BuildContext in reach.
//
// A localized string is resolved at the moment it is shown or produced, never stored in a
// const, a static, or a long-lived field: the language can change while the app runs.
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'app_localizations.dart';
import 'app_localizations_en.dart';

export 'app_localizations.dart';

final AppLocalizations _english = AppLocalizationsEn();

AppLocalizations _current = _english;

/// The strings of the language the app is showing right now, for code with no [BuildContext].
/// English until the first localized frame (and in unit tests that pump no app). Widgets use
/// [L10nContext.l10n] instead, so they rebuild when the language changes.
AppLocalizations get appL10n => _current;

extension L10nContext on BuildContext {
  /// The strings for this context's locale. Falls back to English under a tree with no
  /// [AppLocalizations] delegate (bare `MaterialApp`s in widget tests).
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? _english;
}

/// Sits directly under the app's `Localizations` and publishes the resolved language to the
/// context-free world: [appL10n] and `Intl.defaultLocale` (bare `NumberFormat` / `DateFormat`).
class L10nBinding extends StatelessWidget {
  const L10nBinding({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l10n != null) {
      _current = l10n;
      Intl.defaultLocale = l10n.localeName;
    }
    return child;
  }
}

/// [value] with exactly [digits] decimals and the user's decimal separator ("1.25" in English,
/// "1,25" in German): `toStringAsFixed` for text on screen. No digit grouping, so it also suits
/// a text field the user edits (every numeric field accepts a decimal comma).
String fmtFixed(num value, int digits) =>
    NumberFormat(digits == 0 ? '0' : '0.${'0' * digits}', _current.localeName).format(value);

/// Test hook: put [appL10n] back to English between tests that pumped another language.
@visibleForTesting
void debugResetAppL10n() {
  _current = _english;
  Intl.defaultLocale = null;
}
