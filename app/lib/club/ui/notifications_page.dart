import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_notification.dart';
import '../state/api_providers.dart';
import '../state/notifications_providers.dart';
import 'artwork_detail_page.dart';
import 'profile_page.dart';
import 'widgets/common.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    // Load-more idiom shared with the other paged lists (FeedGrid et al.).
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 400) {
        ref.read(notificationsFeedProvider.notifier).loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(notificationsApiProvider).markAllRead();
      } catch (_) {}
      if (!mounted) return;
      ref.read(unreadCountProvider.notifier).refresh();
      ref.read(notificationsFeedProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(notificationsFeedProvider);
    final n = ref.read(notificationsFeedProvider.notifier);
    Widget body;
    if (s.error != null && s.items.isEmpty) {
      body = ClubErrorRetry(message: s.error!, onRetry: n.refresh);
    } else if (!s.initialized && s.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (s.items.isEmpty) {
      body = const ClubEmpty(message: 'No notifications yet.', icon: Icons.notifications_none);
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
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))));
            }
            return _tile(s.items[i]);
          },
        ),
      );
    }
    return Scaffold(
        appBar: AppBar(title: const Text('Notifications')), body: CenteredContent(child: body));
  }

  // Moderation/report types are presented impersonally (a shield avatar), never
  // an acting moderator's identity, keeping both tile halves consistent.
  // post_approved mirrors the website's choice to not name the approving
  // moderator (new-post-ux message 0001); trust_granted is deliberately NOT
  // here — the website names the granting moderator for that one.
  static const _shieldTypes = {
    'mod_hashtags_updated',
    'new_report',
    'report_resolved',
    'post_approved',
  };

  Widget _tile(ClubNotification x) {
    final hasThumb = x.contentArtUrl != null && x.contentArtUrl!.isNotEmpty;
    // `new_report` is forced inert until the server confirms what its
    // content_sqid carries — for a user-target report it isn't a post sqid, so
    // the default post link would open a broken page (ugc-safety R9).
    final canTap = x.hasContentLink && x.type != 'new_report';
    // Actor avatar → profile (actor_public_sqid, nullable: anonymous/deleted
    // actors get an inert avatar and the whole-tile post link keeps working).
    final actorSqid = x.actorPublicSqid;
    final avatarTap = actorSqid != null && actorSqid.isNotEmpty
        ? () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ProfilePage(sqid: actorSqid)))
        : null;
    return ListTile(
      leading: _shieldTypes.contains(x.type)
          ? const CircleAvatar(radius: 18, child: Icon(Icons.shield, size: 18))
          : GestureDetector(
              onTap: avatarTap,
              child: HandleAvatar(url: x.actorAvatarUrl, handle: x.actorHandle ?? '?', radius: 18),
            ),
      title: Text(_text(x), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(timeAgo(x.createdAt), style: const TextStyle(fontSize: 11)),
      trailing: hasThumb
          ? SizedBox(width: 40, height: 40, child: PixelArtImage(url: x.contentArtUrl!))
          : null,
      onTap: canTap
          ? () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: x.contentSqid!)))
          : null,
    );
  }

  String _text(ClubNotification x) {
    final who = x.actorHandle ?? 'Someone';
    switch (x.type) {
      case 'reaction':
        return '$who reacted ${x.emoji ?? ''} to ${x.contentTitle ?? 'your post'}';
      case 'comment':
        return '$who commented: ${x.commentPreview ?? ''}';
      case 'comment_reply':
        return '$who replied: ${x.commentPreview ?? ''}';
      case 'comment_like':
        return '$who liked your comment';
      case 'follow':
        return '$who started following you';
      case 'remix':
        // Content fields are denormalized from the CHILD post (the remix), so
        // contentTitle names the remix and the tile deep-links to it.
        return '$who published a remix of your artwork'
            '${x.contentTitle != null ? ': "${x.contentTitle}"' : ''}';
      case 'post_promoted':
        return 'Your post was promoted${x.contentTitle != null ? ': ${x.contentTitle}' : ''}';
      case 'post_approved':
        return 'Your artwork${x.contentTitle != null ? ' "${x.contentTitle}"' : ''} '
            'was approved by a moderator and is now publicly released';
      case 'trust_granted':
        // No tap target by contract (post_id and content_* are null); the
        // avatar still links to the granting moderator's profile.
        return x.actorHandle != null
            ? '${x.actorHandle} granted you Trust — your posts are now '
                'auto-approved for public release'
            : 'You were granted Trust — your posts are now auto-approved '
                'for public release';
      case 'mod_hashtags_updated':
        // The +tag −tag diff arrives pre-formatted in comment_preview (contract §7).
        return 'A moderator changed the hashtags on ${x.contentTitle ?? 'your artwork'}'
            '${x.commentPreview != null ? ': ${x.commentPreview}' : ''}';
      case 'reputation_change':
        return 'Your reputation changed';
      case 'moderator_granted':
        return x.actorHandle != null
            ? '${x.actorHandle} made you a moderator'
            : 'You are now a moderator';
      case 'moderator_revoked':
        return 'Your moderator role was removed';
      case 'new_report':
        // Server puts the summary ("New {target_type} report: {reason_code}")
        // in content_title; post_id/content_sqid are null (no in-app queue to
        // link to), so the tile stays no-tap (message 0003 §4b).
        return x.contentTitle ?? 'New content report';
      case 'report_resolved':
        return "Thanks — we've reviewed your report.";
      default:
        return '$who · ${x.type}';
    }
  }
}
