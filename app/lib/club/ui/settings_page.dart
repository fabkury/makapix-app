import 'package:flutter/material.dart';

import 'package:makapix_club/l10n/app_locale.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:makapix_club/ui/language_page.dart';
import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/monitored_hashtags.dart';
import '../models/club_user.dart';
import '../state/animation_settings.dart';
import '../state/publish_providers.dart';
import '../state/auth_controller.dart';
import 'auth/account_management_page.dart';
import 'blocked_users_page.dart';
import 'mentions_settings_page.dart';
import 'monitored_hashtags_page.dart';
import 'widgets/common.dart';
import 'widgets/external_links.dart';

/// User settings (`SPEC-CLUB.md` §21). General holds the device-local options that need no
/// account (language); Account tiles push sub-pages (account management, blocked users, the
/// monitored-hashtag content filter); Playback is device-local. Mirrors the website's
/// `/u/{sqid}/settings`.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    // Safety affordances (blocked-users list, community/contact links) appear
    // once the moderation config key is live.
    final moderation = ref.watch(serverConfigProvider).valueOrNull?.moderation;
    // "N of M shown" summary for the monitored-hashtags tile; updates via the
    // auth controller when the sub-page saves.
    final approved =
        ref.watch(authControllerProvider).me?.user.approvedHashtags ?? const [];
    final shownCount = approved.where(kMonitoredHashtagTags.contains).length;
    // The Mentions row rides the same launch signal as the composers.
    final mentionsEnabled =
        ref.watch(serverConfigProvider).valueOrNull?.mentionsEnabled ?? false;
    final mentionPolicy = ref.watch(authControllerProvider).me?.user.mentionPolicy ??
        MentionPolicy.everyone;
    // The language row needs no account, so it leads the page signed in or out. It only
    // appears once the build offers more than English (kTranslationsShipped).
    final languageRows = availableLanguages.length > 1
        ? <Widget>[
            Text(l10n.settingsSectionGeneral, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const LanguageTile(),
            const Divider(height: 24),
          ]
        : const <Widget>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: CenteredContent(
          child: signedIn
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...languageRows,
                Text(l10n.settingsSectionAccount, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: Text(l10n.settingsAccountManagement),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AccountManagementPage())),
                ),
                if (moderation != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.block),
                    title: Text(l10n.settingsBlockedUsers),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const BlockedUsersPage())),
                  ),
                if (mentionsEnabled)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alternate_email),
                    title: Text(l10n.settingsMentions),
                    subtitle: Text(
                      l10n.settingsMentionsSummary(mentionPolicy.wire),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const MentionsSettingsPage())),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tag),
                  title: Text(l10n.settingsMonitoredHashtags),
                  subtitle: Text(
                    l10n.settingsMonitoredHashtagsSummary(shownCount, kMonitoredHashtags.length),
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const MonitoredHashtagsPage())),
                ),
                const Divider(height: 24),
                // Playback is the page's first LOCAL setting: device-scoped, persisted via
                // SharedPreferences, and applied immediately — no Save button (unlike the
                // server-side monitored-hashtags sub-page above).
                Text(l10n.settingsSectionPlayback, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                SwitchListTile(
                  value: ref.watch(animationAutoplayProvider),
                  onChanged: (v) => ref.read(animationAutoplayProvider.notifier).set(v),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.settingsPlayAnimations),
                  subtitle: Text(
                    l10n.settingsPlayAnimationsSubtitle,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
                if (moderation != null) ...[
                  const Divider(height: 24),
                  Text(l10n.settingsSectionCommunity, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  if (moderation.guidelinesUrl.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.gavel_outlined),
                      title: Text(l10n.settingsCommunityRules),
                      trailing: const Icon(Icons.open_in_new, size: 16),
                      onTap: () => openExternalUrl(context, moderation.guidelinesUrl),
                    ),
                  if (moderation.moderationPolicyUrl.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(l10n.settingsModerationPolicy),
                      trailing: const Icon(Icons.open_in_new, size: 16),
                      onTap: () => openExternalUrl(context, moderation.moderationPolicyUrl),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.mail_outline),
                    title: Text(l10n.settingsContactModerators),
                    subtitle: Text(moderation.contactEmail),
                    onTap: () => openEmail(context, moderation.contactEmail),
                  ),
                ],
              ],
            )
          : Column(children: [
              if (languageRows.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: languageRows),
                ),
              Expanded(
                child: SignInPrompt(
                  message: l10n.settingsSignInPrompt,
                  onSignIn: () => Navigator.pop(context),
                ),
              ),
            ])),
    );
  }
}
