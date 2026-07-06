import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/mkpx_api.dart';
import '../edit/club_edit_request.dart';
import '../models/club_error.dart';
import '../models/post.dart';
import '../models/report.dart';
import '../models/server_config.dart';
import '../state/api_providers.dart';
import '../state/auth_controller.dart';
import '../state/edit_bridge.dart';
import '../state/paged.dart';
import '../state/player_providers.dart';
import '../state/post_providers.dart';
import '../state/publish_providers.dart';
import 'hashtag_feed_page.dart';
import 'profile_page.dart';
import 'reactions_page.dart';
import 'report_page.dart';
import 'widgets/comments_section.dart';
import 'widgets/common.dart';
import 'widgets/mod_hashtags_sheet.dart';
import 'widgets/reactions_bar.dart';
import 'widgets/send_target_binder.dart';

/// The grid an artwork detail was opened from, so the page can swipe to its neighbours and
/// "inherit" its position. Built with [ArtworkFeedSource.fixed] for a flat list (search) or
/// [pagedArtworkSource] for a cursor-paged feed (home / hashtag / gallery — auto-loads more).
class ArtworkFeedSource {
  /// The grid's currently-loaded posts, in order. Called inside `build` (may `ref.watch`).
  final List<Post> Function(WidgetRef ref) watchItems;

  /// Ask the grid to load its next page (no-op when flat or already at the end).
  final void Function(WidgetRef ref) loadMore;

  const ArtworkFeedSource({required this.watchItems, required this.loadMore});

  /// A fixed, non-paginated list of posts (e.g. search results).
  factory ArtworkFeedSource.fixed(List<Post> posts) =>
      ArtworkFeedSource(watchItems: (_) => posts, loadMore: (_) {});
}

/// Build a feed source from a paged feed provider (the home feeds, a hashtag feed, a user gallery).
/// Pass the provider and its `.notifier`, e.g. `pagedArtworkSource(feedProvider(k), feedProvider(k).notifier)`.
ArtworkFeedSource pagedArtworkSource(
  ProviderListenable<PagedState<Post>> state,
  ProviderListenable<PagedNotifier<Post>> notifier,
) =>
    ArtworkFeedSource(
      watchItems: (ref) => ref.watch(state).items,
      loadMore: (ref) => ref.read(notifier).loadMore(),
    );

/// Full artwork view. When opened from a grid it becomes a horizontally-swipeable pager over that
/// grid's posts (swipe ← next, → previous); the back arrow returns to the grid. Opened without a
/// feed (deep link, notification, share) it shows a single, non-swipeable artwork.
class ArtworkDetailPage extends ConsumerStatefulWidget {
  final String sqid;
  final ArtworkFeedSource? feed;
  const ArtworkDetailPage({super.key, required this.sqid, this.feed});

  @override
  ConsumerState<ArtworkDetailPage> createState() => _ArtworkDetailPageState();
}

class _ArtworkDetailPageState extends ConsumerState<ArtworkDetailPage> {
  PageController? _controller;
  bool _resolved = false;
  int _index = 0; // current page in the feed pager, drives the "Send to Player" target

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    final items = feed?.watchItems(ref) ?? const <Post>[];

    final Widget body;
    Post? current;
    if (feed == null || items.isEmpty) {
      body = _ArtworkDetailView(sqid: widget.sqid);
      current = ref.watch(postDetailProvider(widget.sqid)).asData?.value;
    } else {
      // Lock in our starting position in the grid the first time we have its items.
      if (!_resolved) {
        final i = items.indexWhere((p) => p.sqid == widget.sqid);
        _index = i < 0 ? 0 : i;
        _controller = PageController(initialPage: _index);
        _resolved = true;
      }
      current = items[_index.clamp(0, items.length - 1)];
      body = PageView.builder(
        controller: _controller,
        itemCount: items.length,
        onPageChanged: (i) {
          setState(() => _index = i);
          if (i >= items.length - 3) feed.loadMore(ref); // pull the next page as we near the end
        },
        itemBuilder: (_, i) => _ArtworkDetailView(key: ValueKey(items[i].sqid), sqid: items[i].sqid),
      );
    }

    // Just a back arrow — no title — returning to the grid we came from.
    return SendTargetBinder(
      target: current == null
          ? null
          : ArtworkTarget(postId: current.id, title: current.title),
      child: Scaffold(
        appBar: AppBar(titleSpacing: 0, title: const SizedBox.shrink()),
        body: body,
      ),
    );
  }
}

/// One artwork's content: the owner+counts header, the artwork stage, then title/edit, technical
/// info, reactions, description, hashtags, and comments.
class _ArtworkDetailView extends ConsumerStatefulWidget {
  final String sqid;
  const _ArtworkDetailView({super.key, required this.sqid});

  @override
  ConsumerState<_ArtworkDetailView> createState() => _ArtworkDetailViewState();
}

class _ArtworkDetailViewState extends ConsumerState<_ArtworkDetailView> {
  final _commentsKey = GlobalKey();

  void _scrollToComments() {
    final ctx = _commentsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(postDetailProvider(widget.sqid));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ClubErrorRetry(
        message: e is ClubError ? e.message : 'Could not load this artwork.',
        onRetry: () async => ref.invalidate(postDetailProvider(widget.sqid)),
      ),
      data: (post) => _body(context, post),
    );
  }

  Widget _body(BuildContext context, Post post) {
    final base = ref.watch(clubConfigProvider).baseUrl;
    // Live engagement counts: reactions/comments follow the optimistic providers so the header
    // matches the reactions row and the comments list as the user interacts.
    final reactionTotal = ref.watch(reactionsProvider(post.id)).maybeWhen(
        data: (t) => t.totals.values.fold<int>(0, (a, b) => a + b), orElse: () => post.reactionCount);
    final commentTotal = ref
        .watch(commentsProvider(post.id))
        .maybeWhen(data: countComments, orElse: () => post.commentCount);

    return ListView(
      children: [
        _header(context, post, base, reactionTotal, commentTotal),
        _stage(context, post),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Title (left) + Edit-in-Makapix (a single icon, right). The icon turns
            // golden (with a glow) when the post has a layers (.mkpx) file the
            // signed-in user can open — then it loads the full layered document.
            Row(children: [
              Expanded(
                child: Text(post.title.isEmpty ? 'Untitled' : post.title,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              _editButton(context, post),
              ..._overflowMenu(context, post),
            ]),
            const SizedBox(height: 4),
            _meta(post),
            const Divider(height: 24),
            ReactionsBar(postId: post.id),
            if (post.description != null && post.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(post.description!, style: const TextStyle(color: Colors.white70)),
            ],
            if (post.hashtags.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._hashtagWrap(context, post),
            ],
            const Divider(height: 24),
            Container(key: _commentsKey, child: CommentsSection(postId: post.id)),
          ]),
        ),
      ],
    );
  }

  /// The tappable hashtag row + (for moderators and the artist) the mod-tag
  /// shield markers and a persistent legend. Public/other users see mod tags
  /// as perfectly normal tags (contract D2) — the marker branch never runs
  /// for them.
  List<Widget> _hashtagWrap(BuildContext context, Post post) {
    final tagStyle = TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary);
    final canModerate = ref.watch(authControllerProvider).me?.canModerate ?? false;
    final showModMarker = post.modHashtags.isNotEmpty && (canModerate || _isOwner(post));
    return [
      Wrap(spacing: 10, runSpacing: 6, children: [
        // Borderless, vivid-coloured text — reads as a tappable link, not a badge.
        for (final tag in post.hashtags)
          GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => HashtagFeedPage(tag: tag))),
            child: (showModMarker && post.isModTag(tag))
                ? Tooltip(
                    message: 'Added by moderators',
                    child: Semantics(
                      // Keep the tag itself the primary label for screen readers.
                      label: '#$tag, added by moderators',
                      excludeSemantics: true,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.shield,
                            size: 13, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 2),
                        Text('#$tag', style: tagStyle),
                      ]),
                    ),
                  )
                : Text('#$tag', style: tagStyle),
          ),
      ]),
      // Long-press tooltips are undiscoverable; give the artist an always-visible
      // explanation of why those tags exist (and, implicitly, who controls them).
      if (showModMarker)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shield, size: 12, color: Colors.white38),
            SizedBox(width: 4),
            Text('Tagged by a moderator',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          ]),
        ),
    ];
  }

  /// Above the artwork: owner (avatar + handle + tagline) on the left; views, reactions, comments
  /// counts and the share button on the right. Tapping the owner opens their profile; tapping the
  /// reactions count opens the Reactions page; tapping the comments count scrolls down to the comments.
  Widget _header(BuildContext context, Post post, String base, int reactionTotal, int commentTotal) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ProfilePage(sqid: post.owner.sqid))),
            child: Row(children: [
              HandleAvatar(url: post.owner.avatarUrl, handle: post.owner.handle, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(post.owner.handle,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (post.owner.tagline != null && post.owner.tagline!.isNotEmpty)
                        Text(post.owner.tagline!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.white54)),
                    ]),
              ),
            ]),
          ),
        ),
        _stat(Icons.visibility_outlined, post.viewCount),
        _stat(Icons.bolt, reactionTotal,
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ReactionsPage(post: post)))),
        _stat(Icons.mode_comment_outlined, commentTotal, onTap: _scrollToComments),
        IconButton(
          icon: const Icon(Icons.share),
          tooltip: 'Copy link',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: '$base/p/${post.sqid}'));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Link copied')));
          },
        ),
      ]),
    );
  }

  // One icon + count cluster in the header (optionally tappable).
  Widget _stat(IconData icon, int value, {VoidCallback? onTap}) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: Colors.white60),
        const SizedBox(width: 3),
        Text('$value', style: const TextStyle(fontSize: 13, color: Colors.white70)),
      ]),
    );
    return onTap == null
        ? child
        : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: child);
  }

  // The artwork on a dark stage: ~94% of the width, but never taller than 70% of the screen
  // (tall/portrait pieces letterbox within that cap instead of dominating the page).
  Widget _stage(BuildContext context, Post post) => Container(
        color: const Color(0xFF0E1012),
        alignment: Alignment.center,
        padding:
            EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width * 0.03, vertical: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.70),
          child: AspectRatio(
            aspectRatio: post.height > 0 ? post.width / post.height : 1,
            child: PixelArtImage(url: post.artUrl),
          ),
        ),
      );

  Widget _meta(Post post) {
    final parts = <String>[
      '${post.width}×${post.height}',
      post.isAnimated ? '${post.frameCount} frames' : 'static',
      if (post.uniqueColors != null) '${post.uniqueColors} colors',
      if (post.license != null) post.license!.identifier,
    ];
    return Text(parts.join('  ·  '), style: const TextStyle(fontSize: 12, color: Colors.white38));
  }

  // ---- mkpx-upload: golden Edit button, layers download, author attach/detach ----

  /// The layers-file capability advertised by `GET /config` (`upload.mkpx`).
  /// Absent or disabled → all mkpx affordances hidden.
  MkpxRules get _mkpxRules =>
      ref.watch(serverConfigProvider).valueOrNull?.upload.mkpx ?? MkpxRules.disabled;

  bool _isOwner(Post post) {
    final mySub = ref.read(authControllerProvider).me?.user.sub;
    return mySub != null && mySub == post.owner.sqid;
  }

  /// Golden + glowing when the post has a layers file the signed-in user can
  /// open (opens the .mkpx); the regular icon otherwise (imports the render).
  Widget _editButton(BuildContext context, Post post) {
    final golden =
        _mkpxRules.enabled && post.hasMkpx && ref.watch(authControllerProvider).isSignedIn;
    if (!golden) {
      return IconButton(
        icon: const Icon(Icons.edit),
        tooltip: 'Edit in Makapix',
        onPressed: () => _openInEditor(context, post),
      );
    }
    const gold = Color(0xFFFFC94D);
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0x66FFC94D), blurRadius: 14, spreadRadius: 1)],
      ),
      child: IconButton(
        icon: const Icon(Icons.edit, color: gold),
        tooltip: 'Open with layers in Makapix',
        onPressed: () => _openLayersInEditor(context, post),
      ),
    );
  }

  /// Single combined overflow menu: the author's layers-file entries plus the
  /// moderator's mod-hashtags entry — merged so a moderator viewing their own
  /// post gets one kebab, not two. No applicable entries → no button.
  List<Widget> _overflowMenu(BuildContext context, Post post) {
    final showMkpx = _mkpxRules.enabled && !post.isPlaylist && _isOwner(post);
    // ref.watch (not read): the entry must appear when the config future
    // resolves. Null while loading / on fallback keeps it hidden — correct
    // failure mode against a server without the feature (contract §2).
    final cfg = ref.watch(serverConfigProvider).valueOrNull;
    final modEnabled = cfg?.modHashtagsEnabled ?? false;
    final canModerate = ref.watch(authControllerProvider).me?.canModerate ?? false;
    final showMod = modEnabled && canModerate && !post.isPlaylist;
    // Report is visible to everyone (incl. signed-out) once the moderation key
    // is live, except on your own post and on playlists (D6/A14/A16).
    final showReport = cfg?.moderationEnabled == true && !post.isPlaylist && !_isOwner(post);
    if (!showMkpx && !showMod && !showReport) return const [];
    return [
      PopupMenuButton<String>(
        tooltip: 'More actions',
        onSelected: (v) {
          if (v == 'attach') _attachMkpx(context, post);
          if (v == 'detach') _detachMkpx(context, post);
          if (v == 'mod_hashtags') _editModHashtags(context, post);
          if (v == 'report') {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => ReportPage(target: ReportTarget.post(post))));
          }
        },
        itemBuilder: (_) => [
          if (showMkpx)
            PopupMenuItem(
              value: 'attach',
              child: Text(post.hasMkpx ? 'Replace layers file…' : 'Attach layers file…'),
            ),
          if (showMkpx && post.hasMkpx)
            const PopupMenuItem(value: 'detach', child: Text('Remove layers file')),
          if (showMkpx && showMod) const PopupMenuDivider(),
          if (showMod)
            const PopupMenuItem(
              value: 'mod_hashtags',
              child: Row(children: [
                Icon(Icons.shield, size: 16),
                SizedBox(width: 8),
                Text('Edit mod hashtags…'),
              ]),
            ),
          if (showReport && (showMkpx || showMod)) const PopupMenuDivider(),
          if (showReport)
            const PopupMenuItem(
              value: 'report',
              child: Row(children: [
                Icon(Icons.flag_outlined, size: 16),
                SizedBox(width: 8),
                Text('Report post…'),
              ]),
            ),
        ],
      ),
    ];
  }

  void _editModHashtags(BuildContext context, Post post) {
    // ref.read: event handler. The 16 fallback is unreachable in practice —
    // the entry only renders when the config key is present.
    final cap = ref.read(serverConfigProvider).valueOrNull?.maxModHashtagsPerPost ?? 16;
    showModHashtagsSheet(context, post: post, cap: cap);
  }

  /// Golden-button action: download the post's .mkpx and open it in the editor
  /// as a full layered document.
  Future<void> _openLayersInEditor(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Downloading the layers file…')));
    try {
      final bytes = await ref.read(mkpxApiProvider).download(post.sqid);
      final mySub = ref.read(authControllerProvider).me?.user.sub;
      ref.read(pendingClubEditProvider.notifier).state = ClubEditRequest(
        bytes: bytes,
        width: post.width,
        height: post.height,
        sourcePostId: post.id,
        sourceSqid: post.sqid,
        sourceTitle: post.title,
        sourceOwnerHandle: post.owner.handle,
        isOwner: mySub != null && mySub == post.owner.sqid,
        isMkpx: true,
        sourceHasMkpx: true,
      );
      nav.popUntil((r) => r.isFirst); // surface the editor (app root)
    } on ClubError catch (e) {
      if (e.isAuth) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Your session expired — sign in again to download the layers file.')));
      } else if (e.status == 404) {
        // Detached or dropped (artwork replaced) since this payload was fetched.
        messenger.showSnackBar(
            const SnackBar(content: Text('The layers file is no longer available.')));
        ref.invalidate(postDetailProvider(widget.sqid));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Could not download the layers file.')));
    }
  }

  /// Attach (or silently replace) the post's layers file from a picked .mkpx.
  /// Pre-checks the magic bytes and the config size cap locally — a rejected
  /// attach would still burn an upload rate-limit token server-side.
  Future<void> _attachMkpx(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    // ref.read (not the watch-based getter): this runs from an event handler.
    final rules = ref.read(serverConfigProvider).valueOrNull?.upload.mkpx ?? MkpxRules.disabled;
    final res = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['mkpx'], withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return; // cancelled
    if (!MkpxApi.looksLikeMkpx(bytes)) {
      messenger.showSnackBar(const SnackBar(content: Text('Not a valid .mkpx file.')));
      return;
    }
    if (bytes.length > rules.maxFileBytes) {
      messenger.showSnackBar(SnackBar(
          content: Text('Too large — the layers file limit is '
              '${(rules.maxFileBytes / (1024 * 1024)).toStringAsFixed(0)} MiB.')));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Uploading the layers file…')));
    try {
      await ref.read(mkpxApiProvider).attach(post.id, bytes);
      ref.invalidate(postDetailProvider(widget.sqid));
      messenger.showSnackBar(SnackBar(
          content: Text(post.hasMkpx ? 'Layers file replaced.' : 'Layers file attached.')));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not upload the layers file.')));
    }
  }

  Future<void> _detachMkpx(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove layers file?'),
        content: const Text(
            'Members will no longer be able to open this artwork with its layers. '
            'The post itself is unaffected. You can attach a new layers file later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (go != true) return;
    try {
      await ref.read(mkpxApiProvider).detach(post.id);
      ref.invalidate(postDetailProvider(widget.sqid));
      messenger.showSnackBar(const SnackBar(content: Text('Layers file removed.')));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not remove the layers file.')));
    }
  }

  /// Download the artwork and hand it to the editor (root) for remix/replace.
  Future<void> _openInEditor(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final bytes = await ref.read(editApiProvider).downloadArtwork(post.artUrl);
      final mySub = ref.read(authControllerProvider).me?.user.sub;
      ref.read(pendingClubEditProvider.notifier).state = ClubEditRequest(
        bytes: bytes,
        width: post.width,
        height: post.height,
        sourcePostId: post.id,
        sourceSqid: post.sqid,
        sourceTitle: post.title,
        sourceOwnerHandle: post.owner.handle,
        isOwner: mySub != null && mySub == post.owner.sqid,
        sourceHasMkpx: post.hasMkpx,
      );
      nav.popUntil((r) => r.isFirst); // surface the editor (app root)
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(e is ClubError ? e.message : 'Could not load artwork.')));
    }
  }
}
