import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/comment.dart';
import '../../models/mention_markup.dart';
import '../../models/report.dart';
import '../../state/auth_controller.dart';
import '../../state/post_providers.dart';
import '../../state/publish_providers.dart';
import '../club_account_page.dart';
import '../profile_page.dart';
import '../report_page.dart';
import 'common.dart';
import 'mention_field.dart';
import 'mention_text.dart';

/// Threaded comments (depth ≤2) with a composer, likes, reply, and delete-own.
class CommentsSection extends ConsumerStatefulWidget {
  final int postId;
  const CommentsSection({super.key, required this.postId});
  @override
  ConsumerState<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<CommentsSection> {
  final _field = TextEditingController();
  late final MentionComposer _mentions = MentionComposer(controller: _field);
  final _fieldFocus = FocusNode();
  String? _replyTo;
  String? _replyToHandle;
  bool _sending = false;

  @override
  void dispose() {
    _mentions.dispose();
    _fieldFocus.dispose();
    _field.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    // What the user sees is plain `@handle`; the wire carries `<@sqid>` for the
    // handles they actually picked from the candidates list.
    final maxMentions = ref.read(serverConfigProvider).valueOrNull?.maxMentionsPerText ??
        kMaxMentionsPerText;
    final body = _mentions.serialized(maxMentions: maxMentions).trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final picked = [
      for (final p in _mentions.picked) MentionRef(sqid: p.sqid, handle: p.handle),
    ];
    final err = await ref
        .read(commentsProvider(widget.postId).notifier)
        .add(body, parentId: _replyTo, mentions: picked);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (err == null) {
        _field.clear();
        _mentions.seedFromMarkup(null, const []); // drop the picks with the text
        _replyTo = null;
        _replyToHandle = null;
      }
    });
    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(commentsProvider(widget.postId));
    final auth = ref.watch(authControllerProvider);
    // Ownership is matched by handle: server comment payloads carry no author
    // sqid (only the optimistic local ones do), and handles are unique.
    final myHandle = auth.me?.user.handle;
    // Report affordance appears once the moderation config key is live (works
    // signed-out); ref.watch so it shows when the config future resolves.
    final canReport = ref.watch(serverConfigProvider).valueOrNull?.moderationEnabled ?? false;
    final canModerate = ref.watch(isModeratorProvider);
    final l10n = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
              async.maybeWhen(
                  data: (tree) => l10n.commentsTitleCount(countComments(tree)),
                  orElse: () => l10n.commentsTitle),
              style: const TextStyle(fontWeight: FontWeight.bold))),
      async.when(
        loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Padding(
            padding: const EdgeInsets.all(8),
            child: Text(l10n.commentsLoadError, style: const TextStyle(color: Colors.white54))),
        data: (tree) => tree.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.commentsEmpty, style: const TextStyle(color: Colors.white38)))
            : Column(children: [
                for (final c in tree) _tile(c, myHandle, canReport, canModerate, depth: 0)
              ]),
      ),
      const SizedBox(height: 8),
      if (auth.isSignedIn) _composer() else _signInRow(),
    ]);
  }

  Widget _signInRow() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubAccountPage())),
          icon: const Icon(Icons.login),
          label: Text(context.l10n.commentsSignIn),
        ),
      );

  Widget _composer() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_replyToHandle != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Text(context.l10n.commentsReplyingTo(_replyToHandle!),
                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
              const Spacer(),
              IconButton(
                iconSize: 16,
                onPressed: () => setState(() {
                  _replyTo = null;
                  _replyToHandle = null;
                }),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
        Row(children: [
          Expanded(
            child: MentionField(
              composer: _mentions,
              focusNode: _fieldFocus,
              postId: widget.postId,
              enabled: ref.watch(serverConfigProvider).valueOrNull?.mentionsEnabled ?? false,
              maxMentions: ref.watch(serverConfigProvider).valueOrNull?.maxMentionsPerText ??
                  kMaxMentionsPerText,
              child: TextField(
                controller: _field,
                focusNode: _fieldFocus,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                decoration: InputDecoration(
                    hintText: context.l10n.commentsHint,
                    border: const OutlineInputBorder(),
                    counterText: ''),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _sending
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(onPressed: _send, icon: const Icon(Icons.send)),
        ]),
      ]);

  // Open a comment author's profile (no-op for anonymous authors, whose
  // `author_public_sqid` is null).
  void _openAuthor(CommentAuthor? author) {
    final sqid = author?.sqid;
    if (sqid == null || sqid.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(sqid: sqid)));
  }

  Widget _tile(Comment c, String? myHandle, bool canReport, bool canModerate,
      {required int depth}) {
    final isOwn = myHandle != null && c.author?.handle == myHandle;
    final notifier = ref.read(commentsProvider(widget.postId).notifier);
    final l10n = context.l10n;
    // Only moderators ever receive hidden comments — render them dimmed with a
    // "hidden" chip so the mod sees what the public does not.
    Widget dimIfHidden(Widget child) =>
        c.hiddenByMod ? Opacity(opacity: 0.45, child: child) : child;
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0, top: 6, bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          dimIfHidden(GestureDetector(
            onTap: () => _openAuthor(c.author),
            child: HandleAvatar(url: c.author?.avatarUrl, handle: c.author?.handle ?? '?', radius: 12),
          )),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                dimIfHidden(GestureDetector(
                  onTap: () => _openAuthor(c.author),
                  child: Text(c.author?.handle ?? l10n.commentsGuest,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                )),
                const SizedBox(width: 6),
                Text(timeAgo(c.createdAt), style: const TextStyle(fontSize: 11, color: Colors.white38)),
                if (c.hiddenByMod) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(l10n.commentsHiddenChip,
                        style: const TextStyle(fontSize: 10, color: Colors.redAccent)),
                  ),
                ],
              ]),
              dimIfHidden(c.deleted
                  ? Text(c.deletedByMod ? l10n.commentsDeletedByMod : l10n.commentsDeleted,
                      style: const TextStyle(fontSize: 13, color: Colors.white38))
                  : MentionText(
                      markup: c.bodyMarkup,
                      plain: c.body,
                      mentions: c.mentions,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    )),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                // Tap toggles the like; long-press (with a count) shows who liked.
                _miniBtn(c.likedByMe ? Icons.favorite : Icons.favorite_border,
                    c.likeCount > 0 ? '${c.likeCount}' : l10n.commentsLike,
                    onTap: () async {
                      final err = await notifier.toggleLike(c);
                      if (err != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                      }
                    },
                    onLongPress: c.likeCount > 0 ? () => _showLikeUsers(c) : null,
                    active: c.likedByMe),
                if (depth == 0)
                  _miniBtn(Icons.reply, l10n.commentsReply, onTap: () => setState(() {
                        _replyTo = c.id;
                        _replyToHandle = c.author?.handle ?? l10n.commentsGuest;
                      })),
                if (isOwn)
                  _miniBtn(Icons.delete_outline, l10n.commonDelete, onTap: () => notifier.delete(c.id)),
                if (canReport && !isOwn && !c.deleted)
                  _miniBtn(Icons.flag_outlined, l10n.commonReport,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => ReportPage(target: ReportTarget.comment(c))))),
                if (canModerate) _modMenu(c, isOwn),
              ]),
            ]),
          ),
        ]),
        for (final r in c.replies) _tile(r, myHandle, canReport, canModerate, depth: depth + 1),
      ]),
    );
  }

  // ---- moderator comment actions (role-gated; the server is the real gate) ----

  /// Compact shield menu on every row for moderators: delete (mod tombstone),
  /// undelete, hide/unhide, and purge of the preserved original text.
  Widget _modMenu(Comment c, bool isOwn) {
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.commentsModTooltip,
      padding: EdgeInsets.zero,
      onSelected: (v) {
        if (v == 'delete') _modDelete(c);
        if (v == 'undelete') _modUndelete(c);
        if (v == 'hide') _modSetHidden(c, true);
        if (v == 'unhide') _modSetHidden(c, false);
        if (v == 'purge') _modPurge(c);
      },
      itemBuilder: (_) => [
        // Own comments already have the plain Delete button; the mod entry is
        // for other people's comments (writes the moderator tombstone).
        if (!c.deleted && !isOwn)
          PopupMenuItem(value: 'delete', child: Text(l10n.commentsModDelete)),
        if (c.deleted) PopupMenuItem(value: 'undelete', child: Text(l10n.commentsModUndelete)),
        if (!c.deleted)
          PopupMenuItem(value: c.hiddenByMod ? 'unhide' : 'hide',
              child: Text(c.hiddenByMod ? l10n.commonUnhide : l10n.commonHide)),
        if (c.deleted)
          PopupMenuItem(
              value: 'purge',
              child: Text(l10n.commentsModPurge, style: const TextStyle(color: Colors.redAccent))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.shield_outlined, size: 14, color: Colors.white54),
          const SizedBox(width: 4),
          Text(l10n.commentsModChip, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ]),
      ),
    );
  }

  void _toast(String? message) {
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _modDelete(Comment c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Scrolls on a small phone with a large font, where the explanation is taller than the dialog.
        scrollable: true,
        title: Text(ctx.l10n.commentsModDeleteTitle),
        content: Text(ctx.l10n.commentsModDeleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.commonDelete)),
        ],
      ),
    );
    if (yes != true) return;
    // The regular delete endpoint: the server detects the moderator case.
    await ref.read(commentsProvider(widget.postId).notifier).delete(c.id);
  }

  Future<void> _modUndelete(Comment c) async {
    _toast(await ref.read(commentsProvider(widget.postId).notifier).undelete(c.id));
  }

  Future<void> _modSetHidden(Comment c, bool hidden) async {
    _toast(await ref
        .read(commentsProvider(widget.postId).notifier)
        .setHiddenByMod(c.id, hidden));
  }

  /// Irreversible: two-step confirmation before discarding the preserved text.
  Future<void> _modPurge(Comment c) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.commentsPurgeTitle),
        content: Text(ctx.l10n.commentsPurgeBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.commentsPurge)),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.commentsPurgeFinalTitle),
        content: Text(ctx.l10n.commentsPurgeFinalBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commentsPurgeKeep)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.commentsPurgeForever),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;
    final purged = context.l10n.commentsPurged;
    final err = await ref.read(commentsProvider(widget.postId).notifier).purgeOriginal(c.id);
    _toast(err ?? purged);
  }

  Widget _miniBtn(IconData icon, String label,
          {required VoidCallback onTap, VoidCallback? onLongPress, bool active = false}) =>
      TextButton.icon(
        onPressed: onTap,
        onLongPress: onLongPress,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, size: 14, color: active ? Colors.redAccent : Colors.white54),
        label: Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.redAccent : Colors.white54)),
      );

  /// Who liked this comment (`GET /post/comments/{id}/like-users`) — the
  /// website's CommentLikeUsersOverlay as a bottom sheet.
  void _showLikeUsers(Comment c) {
    showAppSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Consumer(builder: (ctx, ref, _) {
          final async = ref.watch(commentLikeUsersProvider(c.id));
          return async.when(
            loading: () => const SizedBox(
                height: 140, child: Center(child: CircularProgressIndicator())),
            error: (_, _) => SizedBox(
                height: 140,
                child: Center(
                    child: Text(ctx.l10n.commentsLikesLoadError,
                        style: const TextStyle(color: Colors.white54)))),
            data: (users) => users.isEmpty
                ? SizedBox(
                    height: 140,
                    child: Center(
                        child: Text(ctx.l10n.commentsLikesEmpty,
                            style: const TextStyle(color: Colors.white54))))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: users.length,
                    itemBuilder: (ctx, i) {
                      final u = users[i];
                      final canOpen = u.sqid != null && u.sqid!.isNotEmpty;
                      return ListTile(
                        leading: HandleAvatar(url: u.avatarUrl, handle: u.handle, radius: 16),
                        title: Text('@${u.handle}', style: const TextStyle(fontSize: 14)),
                        trailing: Text(timeAgo(u.likedAt),
                            style: const TextStyle(fontSize: 11, color: Colors.white38)),
                        onTap: canOpen
                            ? () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => ProfilePage(sqid: u.sqid!)));
                              }
                            : null,
                      );
                    },
                  ),
          );
        }),
      ),
    );
  }
}
