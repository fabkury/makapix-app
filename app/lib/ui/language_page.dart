// Settings → Language: follow the device, or pick one of the app's languages. Shared by both
// pillars (Club settings and the editor's ☰ → View menu). Language names are endonyms, so the
// page is usable by someone who cannot read the language the app is currently showing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../l10n/l10n.dart';
import 'layout.dart';

/// The language the device itself asks for, resolved against what the app offers.
Locale deviceAppLocale() => resolveAppLocale(
    WidgetsBinding.instance.platformDispatcher.locales, availableLocales);

class LanguagePage extends ConsumerWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final picked = ref.watch(appLocaleProvider);
    final controller = ref.read(appLocaleProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.languageTitle)),
      body: CenteredContent(
        child: RadioGroup<Locale?>(
          groupValue: picked,
          onChanged: controller.set,
          child: ListView(
            children: [
              RadioListTile<Locale?>(
                key: const ValueKey('language-system'),
                value: null,
                title: Text(l10n.languageSystemDefault),
                subtitle: Text(
                  l10n.languageSystemDefaultSubtitle(languageFor(deviceAppLocale()).endonym),
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
              const Divider(height: 1),
              for (final language in availableLanguages)
                RadioListTile<Locale?>(
                  key: ValueKey('language-${language.locale.toLanguageTag()}'),
                  value: language.locale,
                  title: Text(language.endonym),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The row that opens [LanguagePage]: a globe (the icon is the affordance for someone lost in
/// the wrong language), the word "Language", and the current choice as an endonym.
class LanguageTile extends ConsumerWidget {
  const LanguageTile({super.key, this.contentPadding = EdgeInsets.zero, this.dense = false});
  final EdgeInsetsGeometry? contentPadding;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final picked = ref.watch(appLocaleProvider);
    return ListTile(
      key: const ValueKey('language-tile'),
      dense: dense,
      contentPadding: contentPadding,
      leading: const Icon(Icons.language),
      title: Text(l10n.languageTitle),
      subtitle: Text(
        picked == null ? l10n.languageSystemDefault : languageFor(picked).endonym,
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const LanguagePage())),
    );
  }
}
