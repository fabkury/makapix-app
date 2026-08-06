import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/umd.dart';
import '../state/api_providers.dart';
import '../state/moderation_providers.dart';
import 'widgets/common.dart';

/// Moderator-only management page for one user — the app counterpart of the
/// website's `/u/{sqid}/manage` (UMD). Reached from the profile overflow menu.
/// The server owner-protects every endpoint (403 for the owner as target).
class UserManagementPage extends ConsumerWidget {
  final String sqid;

  /// Shown in the title while the payload loads (the opener always knows it).
  final String handle;
  const UserManagementPage({super.key, required this.sqid, required this.handle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(umdUserProvider(sqid));
    return Scaffold(
      appBar: AppBar(title: Text('Manage @$handle')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ClubErrorRetry(
          message: e is ClubError
              ? (e.status == 403 ? 'The site owner cannot be managed.' : e.message)
              : 'Could not load this user.',
          onRetry: () async => ref.invalidate(umdUserProvider(sqid)),
        ),
        data: (u) => _UmdBody(user: u),
      ),
    );
  }
}

class _UmdBody extends ConsumerWidget {
  final UmdUserData user;
  const _UmdBody({required this.user});

  void _refresh(WidgetRef ref) => ref.invalidate(umdUserProvider(user.sqid));

  /// Run a moderation call, then refetch the payload; errors become snackbars.
  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() call,
      {required String done, required String failed}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
      _refresh(ref);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.status == 403 ? 'The site owner cannot be managed.' : e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(context),
        const SizedBox(height: 16),
        _sectionCard(context, 'Moderator actions', [
          SwitchListTile(
            value: user.autoPublicApproval,
            title: const Text('Trusted'),
            subtitle: const Text('New posts skip the pending-approval queue'),
            secondary: const Icon(Icons.verified_outlined),
            onChanged: (v) => _run(context, ref,
                () => ref.read(moderationApiProvider).setUserTrusted(user.sqid, v),
                done: v ? '@${user.handle} is now trusted.' : 'Trust revoked.',
                failed: 'Could not update trust.'),
          ),
          ListTile(
            leading: Icon(
                user.hiddenByMod ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            title: Text(user.hiddenByMod ? 'Unhide profile' : 'Hide profile…'),
            subtitle: Text(user.hiddenByMod
                ? 'The profile is currently hidden by moderators'
                : 'Hide the profile from public browsing'),
            onTap: () => _toggleHidden(context, ref),
          ),
          if (user.isBanned)
            ListTile(
              leading: const Icon(Icons.gavel, color: Colors.redAccent),
              title: Text(user.isPermanentlyBanned
                  ? 'Banned permanently'
                  : 'Banned until ${_fmtDate(user.bannedUntil!)}'),
              subtitle: const Text('The user cannot sign in; their data is kept'),
              trailing: TextButton(
                onPressed: () => _unban(context, ref),
                child: const Text('Unban'),
              ),
            )
          else
            ListTile(
              leading: const Icon(Icons.gavel),
              title: const Text('Ban user…'),
              subtitle: const Text('Blocks sign-in for a period; deletes nothing'),
              onTap: () => _ban(context, ref),
            ),
        ]),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Row(children: [
      HandleAvatar(url: user.avatarUrl, handle: user.handle, radius: 28),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('@${user.handle}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 2),
          Text(
            [
              'Reputation ${user.reputation}',
              if (user.roles.any((r) => r != 'user')) user.roles.join(', '),
              if (user.createdAt != null) 'joined ${_fmtDate(user.createdAt!)}',
            ].join('  ·  '),
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          if (user.badges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final b in user.badges)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(b, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _sectionCard(BuildContext context, String title, List<Widget> children) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white70)),
          ),
          ...children,
        ]),
      ),
    );
  }

  Future<void> _toggleHidden(BuildContext context, WidgetRef ref) async {
    final hide = !user.hiddenByMod;
    if (hide) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Hide @${user.handle}?'),
          content: const Text(
              'The profile disappears from public browsing. The user cannot undo this; you can.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hide')),
          ],
        ),
      );
      if (yes != true || !context.mounted) return;
    }
    await _run(context, ref,
        () => ref.read(moderationApiProvider).setUserHidden(user.sqid, hide),
        done: hide ? 'Profile hidden.' : 'Profile is visible again.',
        failed: 'Could not update the profile visibility.');
  }

  Future<void> _unban(BuildContext context, WidgetRef ref) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unban @${user.handle}?'),
        content: const Text('They can sign in again immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unban')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    await _run(context, ref, () => ref.read(moderationApiProvider).unbanUser(user.sqid),
        done: '@${user.handle} unbanned.', failed: 'Could not lift the ban.');
  }

  Future<void> _ban(BuildContext context, WidgetRef ref) async {
    final days = await showBanDurationDialog(context, handle: user.handle);
    if (days == null || !context.mounted) return;
    if (days == kPermanentBan) {
      // Permanent ban gets the irreversible-style second step (it is lifted
      // only by an explicit moderator unban, never by time).
      final second = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ban permanently?'),
          content: Text('@${user.handle} stays banned until a moderator lifts it — '
              'it never expires on its own.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ban permanently'),
            ),
          ],
        ),
      );
      if (second != true || !context.mounted) return;
    }
    await _run(
        context,
        ref,
        () => ref
            .read(moderationApiProvider)
            .banUser(user.sqid, durationDays: days == kPermanentBan ? null : days),
        done: days == kPermanentBan
            ? '@${user.handle} banned permanently.'
            : '@${user.handle} banned for $days ${days == 1 ? 'day' : 'days'}.',
        failed: 'Could not ban the user.');
  }
}

/// Sentinel returned by [showBanDurationDialog] for a permanent ban.
const int kPermanentBan = -1;

/// Ban-duration preset picker: 1 / 7 / 30 / 90 / 365 days or permanent.
/// Pops the chosen day count, [kPermanentBan] for permanent, null on cancel.
/// Top-level so it's widget-testable.
Future<int?> showBanDurationDialog(BuildContext context, {required String handle}) {
  const presets = <int, String>{
    1: '1 day',
    7: '7 days',
    30: '30 days',
    90: '90 days',
    365: '365 days',
    kPermanentBan: 'Permanent',
  };
  var choice = 7;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Ban @$handle?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioGroup<int>(
            groupValue: choice,
            onChanged: (v) => setState(() => choice = v ?? choice),
            child: Column(children: [
              for (final e in presets.entries)
                RadioListTile<int>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: e.key,
                ),
            ]),
          ),
          const SizedBox(height: 4),
          const Text('Banning blocks sign-in; the account and its posts are not deleted.',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, choice), child: const Text('Ban')),
        ],
      ),
    ),
  );
}

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}
