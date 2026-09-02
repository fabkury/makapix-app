import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_notification.dart';
import '../models/safety_copy.dart';
import '../models/server_config.dart';
import '../state/api_providers.dart';
import '../state/notifications_providers.dart';
import '../state/publish_providers.dart';
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
    // Live report-reason labels for the report tiles; null until the config
    // loads (the copy helpers then fall back to their baked-in table).
    final reasons = ref.watch(serverConfigProvider).valueOrNull?.moderation?.reportReasons;
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
            return _tile(s.items[i], reasons);
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

  static const _reportTypes = {'new_report', 'report_resolved'};

  Widget _tile(ClubNotification x, List<ReportReason>? reasons) {
    final hasThumb = x.contentArtUrl != null && x.contentArtUrl!.isNotEmpty;
    // Whole-tile link: the post when the payload names one, else the reported
    // user's profile (report-artwork message 0001 — content_sqid is always a
    // post sqid or null, a reported user rides in target_user_*), else inert
    // (a report whose target vanished, trust_granted, legacy rows).
    final link = x.link;
    // Actor avatar → profile (actor_public_sqid, nullable: anonymous/deleted
    // actors get an inert avatar and the whole-tile post link keeps working).
    final actorSqid = x.actorPublicSqid;
    final avatarTap = actorSqid != null && actorSqid.isNotEmpty
        ? () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ProfilePage(sqid: actorSqid)))
        : null;
    // Thumbnail slot: the artwork for post/comment targets, the reported user's
    // avatar for user targets (mirrors the website's report card).
    Widget? trailing;
    if (hasThumb) {
      trailing = SizedBox(width: 40, height: 40, child: PixelArtImage(url: x.contentArtUrl!));
    } else if (x.hasTargetUser) {
      trailing = HandleAvatar(
          url: x.targetUserAvatarUrl, handle: x.targetUserHandle ?? '?', radius: 20);
    }
    return ListTile(
      leading: _shieldTypes.contains(x.type)
          ? const CircleAvatar(radius: 18, child: Icon(Icons.shield, size: 18))
          : GestureDetector(
              onTap: avatarTap,
              child: HandleAvatar(url: x.actorAvatarUrl, handle: x.actorHandle ?? '?', radius: 18),
            ),
      // Comment reports carry the excerpt on a second line, so give report
      // tiles one more line than the rest.
      title: Text(_text(x, reasons),
          maxLines: _reportTypes.contains(x.type) ? 3 : 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(timeAgo(x.createdAt), style: const TextStyle(fontSize: 11)),
      trailing: trailing,
      onTap: link == null
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => link.isPost
                      ? ArtworkDetailPage(sqid: link.sqid)
                      : ProfilePage(sqid: link.sqid))),
    );
  }

  String _text(ClubNotification x, List<ReportReason>? reasons) {
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
        // Composed from reason_code + the reported post/comment/user
        // (report-artwork message 0001); legacy rows keep their pre-formatted
        // summary. The reports queue itself stays web-only.
        return newReportText(x, reasons: reasons);
      case 'report_resolved':
        return reportResolvedText(x);
      default:
        return '$who · ${x.type}';
    }
  }
}
