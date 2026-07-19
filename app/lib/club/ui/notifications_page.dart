import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_notification.dart';
import '../state/api_providers.dart';
import '../state/notifications_providers.dart';
import 'artwork_detail_page.dart';
import 'widgets/common.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  @override
  void initState() {
    super.initState();
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
          itemCount: s.items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (ctx, i) => _tile(s.items[i]),
        ),
      );
    }
    return Scaffold(
        appBar: AppBar(title: const Text('Notifications')), body: CenteredContent(child: body));
  }

  // Moderation/report types are presented impersonally (a shield avatar), never
  // an acting moderator's identity, keeping both tile halves consistent.
  static const _shieldTypes = {'mod_hashtags_updated', 'new_report', 'report_resolved'};

  Widget _tile(ClubNotification x) {
    final hasThumb = x.contentArtUrl != null && x.contentArtUrl!.isNotEmpty;
    // `new_report` is forced inert until the server confirms what its
    // content_sqid carries — for a user-target report it isn't a post sqid, so
    // the default post link would open a broken page (ugc-safety R9).
    final canTap = x.hasContentLink && x.type != 'new_report';
    return ListTile(
      leading: _shieldTypes.contains(x.type)
          ? const CircleAvatar(radius: 18, child: Icon(Icons.shield, size: 18))
          : HandleAvatar(url: x.actorAvatarUrl, handle: x.actorHandle ?? '?', radius: 18),
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
      case 'post_promoted':
        return 'Your post was promoted${x.contentTitle != null ? ': ${x.contentTitle}' : ''}';
      case 'mod_hashtags_updated':
        // The +tag −tag diff arrives pre-formatted in comment_preview (contract §7).
        return 'A moderator changed the hashtags on ${x.contentTitle ?? 'your artwork'}'
            '${x.commentPreview != null ? ': ${x.commentPreview}' : ''}';
      case 'reputation_change':
        return 'Your reputation changed';
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
