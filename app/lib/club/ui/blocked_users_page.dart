import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/blocked_user.dart';
import '../models/club_error.dart';
import '../models/safety_copy.dart';
import '../state/api_providers.dart';
import '../state/feed_providers.dart';
import '../state/profile_providers.dart';
import '../state/publish_providers.dart';
import '../state/safety_providers.dart';
import 'profile_page.dart';
import 'widgets/common.dart';

/// Settings → Blocked users: the caller's blocked list with per-row unblock.
/// App Review looks for this screen (ugc-safety §4).
class BlockedUsersPage extends ConsumerStatefulWidget {
  const BlockedUsersPage({super.key});
  @override
  ConsumerState<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends ConsumerState<BlockedUsersPage> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    // Load-more idiom: FeedGrid's scroll listener.
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 400) {
        ref.read(blockedUsersProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  int get _maxBlocks =>
      ref.read(serverConfigProvider).valueOrNull?.moderation?.maxBlocksPerUser ?? 1000;

  Future<void> _unblock(BlockedUser u) async {
    final l10n = context.l10n;
    try {
      await ref.read(safetyApiProvider).unblock(u.publicSqid);
      ref.read(blockedUsersProvider.notifier).remove(u.publicSqid);
      // Keep other surfaces fresh without reloading this list.
      ref.invalidate(profileProvider(u.publicSqid));
      ref.invalidate(feedProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.unblockedToast(u.handle))));
      }
    } on ClubError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(blockErrorMessage(e, maxBlocksPerUser: _maxBlocks))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.blockUpdateFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(blockedUsersProvider);
    final n = ref.read(blockedUsersProvider.notifier);
    Widget body;
    if (s.error != null && s.items.isEmpty) {
      body = ClubErrorRetry(message: s.error!, onRetry: n.refresh);
    } else if (!s.initialized && s.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (s.items.isEmpty) {
      body = ClubEmpty(message: context.l10n.blockedEmpty, icon: Icons.block);
    } else {
      body = RefreshIndicator(
        onRefresh: n.refresh,
        child: ListView.separated(
          controller: _sc,
          itemCount: s.items.length + (s.atEnd ? 0 : 1),
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            if (i >= s.items.length) {
              return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: SizedBox(
                          height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))));
            }
            return _row(s.items[i]);
          },
        ),
      );
    }
    return Scaffold(
        appBar: AppBar(title: Text(context.l10n.settingsBlockedUsers)),
        body: CenteredContent(child: body));
  }

  Widget _row(BlockedUser u) => ListTile(
        // Tight on purpose: "Unblock" is a long word in some languages ("Blockierung
        // aufheben"), and on a 320 px phone the handle was left 49 px.
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        horizontalTitleGap: 12,
        leading: HandleAvatar(url: u.avatarUrl, handle: u.handle, radius: 18),
        title: Text('@${u.handle}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(context.l10n.blockedWhen(timeAgo(u.blockedAt)),
            style: const TextStyle(fontSize: 11)),
        trailing: TextButton(
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => _unblock(u),
            child: Text(context.l10n.unblockAction)),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ProfilePage(sqid: u.publicSqid))),
      );
}
