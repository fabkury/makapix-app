import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/monitored_hashtags.dart';
import '../models/club_error.dart';
import '../state/animation_settings.dart';
import '../state/api_providers.dart';
import '../state/auth_controller.dart';
import '../state/feed_providers.dart';
import '../state/publish_providers.dart';
import 'auth/account_management_page.dart';
import 'blocked_users_page.dart';
import 'widgets/common.dart';
import 'widgets/external_links.dart';

/// User settings (`SPEC-CLUB.md` §21). Currently surfaces the monitored-hashtag
/// content filter: opt in to seeing posts tagged
/// `#politics/#nsfw/#explicit/#13plus/#violence` (all hidden by default).
/// Mirrors the website's `/u/{sqid}/settings`.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late Set<String> _selected;
  late Set<String> _initial;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final approved = ref.read(authControllerProvider).me?.user.approvedHashtags ?? const [];
    // Keep only currently-monitored tags (a since-removed tag would be unmappable).
    final valid = approved.where(kMonitoredHashtagTags.contains).toSet();
    _selected = {...valid};
    _initial = {...valid};
  }

  bool get _dirty =>
      _selected.length != _initial.length || !_selected.containsAll(_initial);

  Future<void> _save() async {
    final userKey = ref.read(authControllerProvider).me?.user.userKey ?? '';
    if (userKey.isEmpty) {
      _toast('Could not determine your account id.');
      return;
    }
    setState(() => _saving = true);
    try {
      final result =
          await ref.read(settingsApiProvider).setApprovedHashtags(userKey, _selected.toList());
      final applied = result.where(kMonitoredHashtagTags.contains).toSet();
      ref.read(authControllerProvider.notifier).updateApprovedHashtags(applied.toList());
      // Feeds are filtered server-side from approved_hashtags — re-fetch so the
      // change is visible immediately.
      ref.invalidate(feedProvider);
      if (!mounted) return;
      setState(() {
        _selected = {...applied};
        _initial = {...applied};
        _saving = false;
      });
      _toast('Saved.');
    } on ClubError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save settings.');
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    // Safety affordances (blocked-users list, community/contact links) appear
    // once the moderation config key is live.
    final moderation = ref.watch(serverConfigProvider).valueOrNull?.moderation;
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
                const Divider(height: 24),
                Text('Monitored hashtags', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text(
                  'Posts tagged with these are hidden by default. Tick a tag to opt in to '
                  'seeing it across feeds, search and notifications.',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 12),
                for (final h in kMonitoredHashtags) _tagTile(h),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: (!_dirty || _saving) ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save changes'),
                  ),
                ),
                const Divider(height: 24),
                // Playback is the page's first LOCAL setting: device-scoped, persisted via
                // SharedPreferences, and applied immediately — no Save button (unlike the
                // server-side monitored-hashtags section above).
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

  Widget _tagTile(MonitoredHashtag h) {
    final cs = Theme.of(context).colorScheme;
    final on = _selected.contains(h.tag);
    return CheckboxListTile(
      value: on,
      onChanged: _saving
          ? null
          : (v) => setState(() {
                if (v == true) {
                  _selected.add(h.tag);
                } else {
                  _selected.remove(h.tag);
                }
              }),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Row(children: [
        Text(h.label,
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        _badge(on ? 'Shown' : 'Hidden', on ? cs.primary : Colors.white38),
      ]),
      subtitle: Text(h.description, style: const TextStyle(color: Colors.white54)),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11)),
      );
}
