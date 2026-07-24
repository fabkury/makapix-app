import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/monitored_hashtags.dart';
import '../state/animation_settings.dart';
import '../state/publish_providers.dart';
import '../state/auth_controller.dart';
import 'auth/account_management_page.dart';
import 'blocked_users_page.dart';
import 'monitored_hashtags_page.dart';
import 'widgets/common.dart';
import 'widgets/external_links.dart';

/// User settings (`SPEC-CLUB.md` §21). Account tiles push sub-pages (account
/// management, blocked users, the monitored-hashtag content filter); Playback
/// is device-local. Mirrors the website's `/u/{sqid}/settings`.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    // Safety affordances (blocked-users list, community/contact links) appear
    // once the moderation config key is live.
    final moderation = ref.watch(serverConfigProvider).valueOrNull?.moderation;
    // "N of M shown" summary for the monitored-hashtags tile; updates via the
    // auth controller when the sub-page saves.
    final approved =
        ref.watch(authControllerProvider).me?.user.approvedHashtags ?? const [];
    final shownCount = approved.where(kMonitoredHashtagTags.contains).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: CenteredContent(
          child: signedIn
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Account', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Password, handle & linked logins'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AccountManagementPage())),
                ),
                if (moderation != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.block),
                    title: const Text('Blocked users'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const BlockedUsersPage())),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tag),
                  title: const Text('Monitored hashtags'),
                  subtitle: Text(
                    '$shownCount of ${kMonitoredHashtags.length} shown',
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
                Text('Playback', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                SwitchListTile(
                  value: ref.watch(animationAutoplayProvider),
                  onChanged: (v) => ref.read(animationAutoplayProvider.notifier).set(v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Play animations'),
                  subtitle: const Text(
                    'Animated artworks play in feeds and on artwork pages. When off, they '
                    'show their first frame (this device only).',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                if (moderation != null) ...[
                  const Divider(height: 24),
                  Text('Community', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  if (moderation.guidelinesUrl.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.gavel_outlined),
                      title: const Text('Community rules'),
                      trailing: const Icon(Icons.open_in_new, size: 16),
                      onTap: () => openExternalUrl(context, moderation.guidelinesUrl),
                    ),
                  if (moderation.moderationPolicyUrl.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Moderation policy'),
                      trailing: const Icon(Icons.open_in_new, size: 16),
                      onTap: () => openExternalUrl(context, moderation.moderationPolicyUrl),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.mail_outline),
                    title: const Text('Contact the moderators'),
                    subtitle: Text(moderation.contactEmail),
                    onTap: () => openEmail(context, moderation.contactEmail),
                  ),
                ],
              ],
            )
          : SignInPrompt(
              message: 'Sign in to manage your settings.',
              onSignIn: () => Navigator.pop(context),
            )),
    );
  }
}
