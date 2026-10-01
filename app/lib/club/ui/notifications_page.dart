import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

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
      body = ClubEmpty(message: context.l10n.notifEmpty, icon: Icons.notifications_none);
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
        appBar: AppBar(title: Text(context.l10n.notifications)),
        body: CenteredContent(child: body));
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
    final l10n = context.l10n;
    final who = x.actorHandle ?? l10n.notifSomeone;
    final title = x.contentTitle;
    // A sentence, then (when there is one) the quoted excerpt after a colon.
    String withPreview(String text, String? preview) =>
        preview != null && preview.isNotEmpty ? l10n.notifWithPreview(text, preview) : text;
    switch (x.type) {
      case 'reaction':
        final emoji = x.emoji ?? '';
        return title != null
            ? l10n.notifReaction(who, emoji, title)
            : l10n.notifReactionYourPost(who, emoji);
      case 'comment':
        return withPreview(l10n.notifComment(who), x.commentPreview);
      case 'comment_reply':
        return withPreview(l10n.notifReply(who), x.commentPreview);
      case 'comment_like':
        return l10n.notifCommentLike(who);
      case 'mention':
        // `comment_id` null means the mention was in the post's description
        // (server message 0004/0002 §4). Both variants deep-link to the post.
        if (x.commentId == null || x.commentId!.isEmpty) {
          return title != null
              ? l10n.notifMentionDescriptionOf(who, title)
              : l10n.notifMentionDescription(who);
        }
        return withPreview(
            title != null ? l10n.notifMentionCommentOn(who, title) : l10n.notifMentionComment(who),
            x.commentPreview);
      case 'follow':
        return l10n.notifFollow(who);
      case 'remix':
        // Content fields are denormalized from the CHILD post (the remix), so
        // contentTitle names the remix and the tile deep-links to it.
        return title != null ? l10n.notifRemixTitled(who, title) : l10n.notifRemix(who);
      case 'post_promoted':
        return withPreview(l10n.notifPromoted, title);
      case 'post_approved':
        return title != null ? l10n.notifApprovedTitled(title) : l10n.notifApproved;
      case 'trust_granted':
        // No tap target by contract (post_id and content_* are null); the
        // avatar still links to the granting moderator's profile.
        return x.actorHandle != null ? l10n.notifTrustBy(x.actorHandle!) : l10n.notifTrust;
      case 'mod_hashtags_updated':
        // The +tag −tag diff arrives pre-formatted in comment_preview (contract §7).
        return withPreview(
            title != null ? l10n.notifModTags(title) : l10n.notifModTagsYourArtwork,
            x.commentPreview);
      case 'reputation_change':
        return l10n.notifReputation;
      case 'moderator_granted':
        return x.actorHandle != null ? l10n.notifModeratorBy(x.actorHandle!) : l10n.notifModerator;
      case 'moderator_revoked':
        return l10n.notifModeratorRevoked;
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
