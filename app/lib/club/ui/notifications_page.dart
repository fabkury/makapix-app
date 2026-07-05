import 'package:flutter/material.dart';
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
    return Scaffold(appBar: AppBar(title: const Text('Notifications')), body: body);
  }

  Widget _tile(ClubNotification x) {
    final hasThumb = x.contentArtUrl != null && x.contentArtUrl!.isNotEmpty;
    return ListTile(
      // Moderation is presented impersonally ("A moderator…"): a shield avatar,
      // never the acting moderator's identity, keeping both tile halves consistent.
      leading: x.type == 'mod_hashtags_updated'
          ? const CircleAvatar(radius: 18, child: Icon(Icons.shield, size: 18))
          : HandleAvatar(url: x.actorAvatarUrl, handle: x.actorHandle ?? '?', radius: 18),
      title: Text(_text(x), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(timeAgo(x.createdAt), style: const TextStyle(fontSize: 11)),
      trailing: hasThumb
          ? SizedBox(width: 40, height: 40, child: PixelArtImage(url: x.contentArtUrl!))
          : null,
      onTap: x.hasContentLink
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
      default:
        return '$who · ${x.type}';
    }
  }
}
