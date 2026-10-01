// T4 sweeps: Settings and the language picker.
import 'package:makapix_club/club/ui/settings_page.dart';
import 'package:makapix_club/ui/language_page.dart';

import 'club_fixtures.dart';
import 'sweep.dart';

void main() {
  sweepScreen(
    'Settings, signed in',
    build: () => const SettingsPage(),
    overrides: (_) => clubOverrides(signedIn: true),
  );

  sweepScreen(
    'Settings, signed out',
    build: () => const SettingsPage(),
    overrides: (_) => clubOverrides(signedIn: false),
  );

  sweepScreen(
    'Language picker',
    build: () => const LanguagePage(),
    // The picker lists each language under its own name, in its own script.
    allowLatin: const ['Deutsch', 'English', 'Español', 'Français', 'Português (Brasil)'],
  );
}
