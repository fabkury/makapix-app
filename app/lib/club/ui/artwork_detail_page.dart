import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/mkpx_api.dart';
import '../edit/club_edit_request.dart';
import '../models/club_error.dart';
import '../models/post.dart';
import '../models/report.dart';
import '../models/server_config.dart';
import '../state/animation_settings.dart';
import '../state/api_providers.dart';
import '../state/auth_controller.dart';
import '../state/edit_bridge.dart';
import '../state/feed_providers.dart';
import '../state/paged.dart';
import '../state/player_providers.dart';
import '../state/pmd_providers.dart';
import '../state/post_providers.dart';
import '../state/publish_providers.dart';
import 'edit_post_details_page.dart';
import 'widgets/mention_text.dart';
import 'lineage_page.dart';
import 'hashtag_feed_page.dart';
import 'post_stats_page.dart';
import 'profile_page.dart';
import 'reactions_page.dart';
import 'report_page.dart';
import 'widgets/comments_section.dart';
import 'widgets/common.dart';
import 'widgets/download_sheet.dart';
import 'widgets/mod_hashtags_sheet.dart';
import 'widgets/reactions_bar.dart';
import 'widgets/send_target_binder.dart';
import 'package:makapix_club/share/image_share.dart';

/// The grid an artwork detail was opened from, so the page can swipe to its neighbors and
/// "inherit" its position. Built with [ArtworkFeedSource.fixed] for a flat list (search) or
/// [pagedArtworkSource] for a cursor-paged feed (home / hashtag / gallery — auto-loads more).
class ArtworkFeedSource {
  /// The grid's currently-loaded posts, in order. Called inside `build` (may `ref.watch`).
  final List<Post> Function(WidgetRef ref) watchItems;

  /// Ask the grid to load its next page (no-op when flat or already at the end).
  final void Function(WidgetRef ref) loadMore;

  /// Shown in the detail page's top bar (next to the back arrow) so the user knows which
  /// feed they're swiping through, e.g. "Recommended", "#pixelart", "@handle · Reacted".
  final String? name;

  /// Optional glyph before [name] (the diamond/eye/hashtag feed identities).
  final IconData? icon;

  const ArtworkFeedSource(
      {required this.watchItems, required this.loadMore, this.name, this.icon});

  /// A fixed, non-paginated list of posts (e.g. search results).
  factory ArtworkFeedSource.fixed(List<Post> posts, {String? name, IconData? icon}) =>
      ArtworkFeedSource(watchItems: (_) => posts, loadMore: (_) {}, name: name, icon: icon);
}

/// Build a feed source from a paged feed provider (the home feeds, a hashtag feed, a user gallery).
/// Pass the provider and its `.notifier`, e.g. `pagedArtworkSource(feedProvider(k), feedProvider(k).notifier)`.
ArtworkFeedSource pagedArtworkSource(
  ProviderListenable<PagedState<Post>> state,
  ProviderListenable<PagedNotifier<Post>> notifier, {
  String? name,
  IconData? icon,
}) =>
    ArtworkFeedSource(
      watchItems: (ref) => ref.watch(state).items,
      loadMore: (ref) => ref.read(notifier).loadMore(),
      name: name,
      icon: icon,
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

    // The back arrow returns to the grid we came from; next to it, that feed's name
    // (muted — it's context, not a page title) when we know it.
    return SendTargetBinder(
      target: current == null
          ? null
          : ArtworkTarget(postId: current.id, title: current.title),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: feed?.name == null
              ? const SizedBox.shrink()
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (feed!.icon != null) ...[
                    Icon(feed.icon, size: 18, color: Colors.white54),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(feed.name!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, color: Colors.white70)),
                  ),
                ]),
        ),
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

  /// Play-despite-animations-off override for THIS artwork, while its page is open.
  bool _playOverride = false;

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
        message: e is ClubError ? e.message : context.l10n.artworkLoadError,
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

    // One source of truth for the info block (title/meta/reactions/description/hashtags/comments):
    // below the stage on phones, in the right-hand pane on wide viewports.
    Widget infoBlock() => Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Title (left) + Edit-in-Makapix (a single icon, right). The icon turns
            // golden (with a glow) when the post has a layers (.mkpx) file the
            // signed-in user can open — then it loads the full layered document.
            Row(children: [
              Expanded(
                child: Text(post.title.isEmpty ? context.l10n.untitled : post.title,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              _editButton(context, post),
              ..._overflowMenu(context, post),
            ]),
            const SizedBox(height: 4),
            _meta(post),
            ?_remixLine(post),
            if (_isOwner(post) && post.hiddenByUser)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.visibility_off_outlined, size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(context.l10n.artworkHiddenByYou,
                        style: const TextStyle(fontSize: 12, color: Colors.amber)),
                  ),
                ]),
              ),
            if (ref.watch(isModeratorProvider)) _modStatusChips(post),
            const Divider(height: 24),
            ReactionsBar(postId: post.id),
            if (post.description != null && post.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              MentionText(
                markup: post.descriptionMarkup,
                plain: post.description!,
                mentions: post.mentions,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            if (post.hashtags.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._hashtagWrap(context, post),
            ],
            const Divider(height: 24),
            Container(key: _commentsKey, child: CommentsSection(postId: post.id)),
          ]),
        );

    return LayoutBuilder(builder: (context, constraints) {
      // Two-pane on wide viewports (tablet landscape, desktop): the artwork fills a dark stage on
      // the left; owner header, title, reactions and comments scroll in a fixed-width right pane.
      // Vertical drags stay inside the pane's ListView; horizontal drags still bubble up to the
      // feed's PageView, so swiping between artworks keeps working from either pane.
      if (constraints.maxWidth >= kWideDetailBreakpoint) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _stage(context, post, fillPane: true)),
          SizedBox(
            width: 400,
            child: ListView(children: [
              _header(context, post, base, reactionTotal, commentTotal),
              infoBlock(),
            ]),
          ),
        ]);
      }
      return ListView(
        children: [
          _header(context, post, base, reactionTotal, commentTotal),
          _stage(context, post),
          infoBlock(),
        ],
      );
    });
  }

  /// The tappable hashtag row + (for moderators and the artist) the mod-tag
  /// shield markers and a persistent legend. Public/other users see mod tags
  /// as perfectly normal tags (contract D2) — the marker branch never runs
  /// for them.
  List<Widget> _hashtagWrap(BuildContext context, Post post) {
    final tagStyle = TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary);
    final canModerate = ref.watch(isModeratorProvider);
    final showModMarker = post.modHashtags.isNotEmpty && (canModerate || _isOwner(post));
    return [
      Wrap(spacing: 10, runSpacing: 6, children: [
        // Borderless, vivid-colored text — reads as a tappable link, not a badge.
        for (final tag in post.hashtags)
          GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => HashtagFeedPage(tag: tag))),
            child: (showModMarker && post.isModTag(tag))
                ? Tooltip(
                    message: context.l10n.artworkTagByMods,
                    child: Semantics(
                      // Keep the tag itself the primary label for screen readers.
                      label: context.l10n.artworkTagByModsLabel(tag),
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
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.shield, size: 12, color: Colors.white38),
            const SizedBox(width: 4),
            Flexible(
              child: Text(context.l10n.artworkTaggedByMod,
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ),
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
        // Tap shares the pixels (+ URL caption); long-press copies just the link.
        GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: '$base/p/${post.sqid}'));
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(context.l10n.linkCopiedShort)));
          },
          child: IconButton(
            icon: const Icon(Icons.share),
            tooltip: context.l10n.artworkShareTooltip,
            visualDensity: VisualDensity.compact,
            onPressed: () => _shareArtwork(context, post, base),
          ),
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
  //
  // When animations are off (the autoplay setting or OS reduce-motion), an animated post
  // shows its first frame with a small play/stop overlay — playback started here joins the
  // shared clock, so it is in phase with every other playing tile.
  // `fillPane` (wide two-pane layout): the stage fills its bounded left pane instead of sizing
  // from the screen — the AspectRatio grows the art as large as the pane allows.
  Widget _stage(BuildContext context, Post post, {bool fillPane = false}) {
    final motionOff = post.isAnimated &&
        (!ref.watch(animationAutoplayProvider) || MediaQuery.disableAnimationsOf(context));
    Widget art = PixelArtImage(
      url: post.artUrl,
      frameCount: post.frameCount,
      width: post.width,
      height: post.height,
      forcePlay: _playOverride,
    );
    if (motionOff) {
      art = Stack(children: [
        Positioned.fill(child: art),
        Positioned(
          right: 8,
          bottom: 8,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: IconButton(
              icon: Icon(_playOverride ? Icons.stop : Icons.play_arrow, color: Colors.white),
              tooltip: _playOverride
                  ? context.l10n.artworkStopAnimation
                  : context.l10n.artworkPlayAnimation,
              onPressed: () => setState(() => _playOverride = !_playOverride),
            ),
          ),
        ),
      ]);
    }
    final ratio = post.height > 0 ? post.width / post.height : 1.0;
    if (fillPane) {
      return Container(
        color: const Color(0xFF0E1012),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: AspectRatio(aspectRatio: ratio, child: art),
      );
    }
    return Container(
      color: const Color(0xFF0E1012),
      alignment: Alignment.center,
      padding:
          EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width * 0.03, vertical: 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.70),
        child: AspectRatio(
          aspectRatio: ratio,
          child: art,
        ),
      ),
    );
  }

  Widget _meta(Post post) {
    final native = post.nativeFile;
    final l10n = context.l10n;
    final parts = <String>[
      '${post.width}×${post.height}',
      post.isAnimated ? l10n.artworkFrames(post.frameCount) : l10n.artworkStatic,
      if (post.uniqueColors != null) l10n.artworkColorsPerFrame(post.uniqueColors!),
      if (native != null) '${formatFileSize(native.fileBytes)} ${native.format.toUpperCase()}',
      if (post.license != null) post.license!.identifier,
    ];
    return Text(parts.join('  ·  '), style: const TextStyle(fontSize: 12, color: Colors.white38));
  }

  /// Discreet public-lineage line (0002 §2): the Remix badge when this post has
  /// Parents, and its visible-remixes count. Absent for lineage-less posts.
  /// Tapping opens the Lineage page (originals + remixes) — the page itself
  /// carries the sign-in prompt for signed-out viewers (the lists are
  /// login-gated; this line stays public).
  Widget? _remixLine(Post post) {
    if (post.parentCount == 0 && post.childCount == 0) return null;
    final parts = <String>[
      if (post.parentCount > 0) context.l10n.artworkIsRemix,
      if (post.childCount > 0) context.l10n.artworkRemixCount(post.childCount),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => LineagePage(post: post))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.alt_route, size: 14, color: Colors.white38),
            const SizedBox(width: 5),
            Text(parts.join('  ·  '),
                style: const TextStyle(fontSize: 12, color: Colors.white38)),
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right, size: 14, color: Colors.white38),
          ]),
        ),
      ),
    );
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
  /// Gated on the post's public `remixable` flag for non-owners (0002 §2): the
  /// server would refuse the download (403) and the publish (422) anyway.
  Widget _editButton(BuildContext context, Post post) {
    if (!post.remixable && !_isOwner(post)) {
      return IconButton(
        icon: const Icon(Icons.edit_off),
        tooltip: context.l10n.artworkNoRemixes,
        onPressed: null,
      );
    }
    final golden =
        _mkpxRules.enabled && post.hasMkpx && ref.watch(authControllerProvider).isSignedIn;
    if (!golden) {
      return IconButton(
        icon: const Icon(Icons.edit),
        tooltip: context.l10n.artworkEdit,
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
        tooltip: context.l10n.artworkEditLayers,
        onPressed: () => _openLayersInEditor(context, post),
      ),
    );
  }

  /// Single combined overflow menu: the owner's post-management entries, the
  /// author's layers-file entries, plus the moderator's mod-hashtags entry —
  /// merged so a moderator viewing their own post gets one kebab, not two.
  /// No applicable entries → no button.
  List<Widget> _overflowMenu(BuildContext context, Post post) {
    // Owner post management (edit details / hide / delete) — the single-post
    // counterpart of the bulk PMD actions, same endpoints family.
    final showOwner = _isOwner(post) && !post.isPlaylist;
    final showMkpx = _mkpxRules.enabled && !post.isPlaylist && _isOwner(post);
    // ref.watch (not read): the entry must appear when the config future
    // resolves. Null while loading / on fallback keeps it hidden — correct
    // failure mode against a server without the feature (contract §2).
    final cfg = ref.watch(serverConfigProvider).valueOrNull;
    final modEnabled = cfg?.modHashtagsEnabled ?? false;
    final canModerate = ref.watch(isModeratorProvider);
    final showMod = modEnabled && canModerate && !post.isPlaylist;
    // Post-level moderator actions (hide/promote/approve/delete) are gated on
    // the role alone — they predate the moderation config key, like the
    // website's `p/{sqid}` moderator block.
    final showModTools = canModerate && !post.isPlaylist;
    // Report is visible to everyone (incl. signed-out) once the moderation key
    // is live, except on your own post and on playlists (D6/A14/A16).
    final showReport = cfg?.moderationEnabled == true && !post.isPlaylist && !_isOwner(post);
    // Any signed-in user may snapshot any viewable artwork as their avatar
    // (server copies the bytes — not ownership-gated by design).
    final showUseAvatar = ref.watch(authControllerProvider).me != null &&
        !post.isPlaylist &&
        post.artUrl.isNotEmpty;
    // Save-to-device downloads: public `/d/{sqid}*` endpoints, so everyone
    // (signed-out included) gets the entry on artwork posts.
    final showDownload = !post.isPlaylist;
    if (!showOwner &&
        !showMkpx &&
        !showMod &&
        !showModTools &&
        !showReport &&
        !showUseAvatar &&
        !showDownload) {
      return const [];
    }
    final anyModEntry = showMod || showModTools;
    final l10n = context.l10n;
    return [
      PopupMenuButton<String>(
        tooltip: l10n.commonMoreActions,
        onSelected: (v) {
          if (v == 'edit_details') _editDetails(context, post);
          if (v == 'stats') {
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => PostStatsPage(post: post)));
          }
          if (v == 'toggle_hidden') _toggleHidden(context, post);
          if (v == 'delete_post') _deletePost(context, post);
          if (v == 'attach') _attachMkpx(context, post);
          if (v == 'detach') _detachMkpx(context, post);
          if (v == 'download') showDownloadSheet(context, ref, post: post);
          if (v == 'mod_hashtags') _editModHashtags(context, post);
          if (v == 'mod_hide') _modSetHidden(context, post, true);
          if (v == 'mod_unhide') _modSetHidden(context, post, false);
          if (v == 'mod_promote') _modPromote(context, post);
          if (v == 'mod_demote') _modDemote(context, post);
          if (v == 'mod_approve') _modApprovePublic(context, post);
          if (v == 'mod_delete') _modDeletePermanently(context, post);
          if (v == 'use_avatar') _useAsProfilePhoto(context, post);
          if (v == 'report') {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => ReportPage(target: ReportTarget.post(post))));
          }
        },
        itemBuilder: (_) => [
          if (showOwner) ...[
            PopupMenuItem(
              value: 'edit_details',
              child: Row(children: [
                const Icon(Icons.edit_note, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(l10n.artworkMenuEditDetails)),
              ]),
            ),
            PopupMenuItem(
              value: 'stats',
              child: Row(children: [
                const Icon(Icons.insights, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(l10n.artworkMenuStats)),
              ]),
            ),
            PopupMenuItem(
              value: 'toggle_hidden',
              child: Row(children: [
                Icon(
                    post.hiddenByUser
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(post.hiddenByUser ? l10n.artworkMenuUnhide : l10n.artworkMenuHide)),
              ]),
            ),
            PopupMenuItem(
              value: 'delete_post',
              child: Row(children: [
                const Icon(Icons.delete_outline, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(l10n.artworkMenuDelete)),
              ]),
            ),
          ],
          if (showOwner && (showMkpx || showDownload || showMod || showUseAvatar || showReport))
            const PopupMenuDivider(),
          if (showMkpx)
            PopupMenuItem(
              value: 'attach',
              child: Text(
                  post.hasMkpx ? l10n.artworkMenuReplaceLayers : l10n.artworkMenuAttachLayers),
            ),
          if (showMkpx && post.hasMkpx)
            PopupMenuItem(value: 'detach', child: Text(l10n.artworkMenuRemoveLayers)),
          // (The owner group's divider above already separates when mkpx is off.)
          if (showDownload && showMkpx) const PopupMenuDivider(),
          if (showDownload)
            PopupMenuItem(
              value: 'download',
              child: Row(children: [
                const Icon(Icons.download_outlined, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(l10n.artworkMenuDownload)),
              ]),
            ),
          if (anyModEntry && (showDownload || showMkpx || showOwner)) const PopupMenuDivider(),
          if (showMod)
            PopupMenuItem(
              value: 'mod_hashtags',
              child: Row(children: [
                const Icon(Icons.shield, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(l10n.artworkMenuModTags)),
              ]),
            ),
          if (showModTools) ...[
            PopupMenuItem(
              value: post.hiddenByMod ? 'mod_unhide' : 'mod_hide',
              child: Row(children: [
                Icon(
                    post.hiddenByMod
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(post.hiddenByMod ? l10n.artworkMenuModUnhide : l10n.artworkMenuModHide)),
              ]),
            ),
            PopupMenuItem(
              value: post.promoted ? 'mod_demote' : 'mod_promote',
              child: Row(children: [
                Icon(post.promoted ? Icons.star_outline : Icons.star, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(post.promoted ? l10n.artworkMenuDemote : l10n.artworkMenuPromote)),
              ]),
            ),
            if (!post.publicVisibility)
              PopupMenuItem(
                value: 'mod_approve',
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, size: 16),
                  const SizedBox(width: 8),
                  Flexible(child: Text(l10n.artworkMenuApprove)),
                ]),
              ),
            // Same gate as the website: permanent delete only once the post is
            // already off the public surfaces (mod- or owner-hidden).
            if (post.hiddenByMod || post.hiddenByUser)
              PopupMenuItem(
                value: 'mod_delete',
                child: Row(children: [
                  const Icon(Icons.delete_forever_outlined, size: 16, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(l10n.artworkMenuDeleteForever,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                ]),
              ),
          ],
          if (showUseAvatar && (showOwner || showMkpx || showDownload || anyModEntry))
            const PopupMenuDivider(),
          if (showUseAvatar)
            PopupMenuItem(
              value: 'use_avatar',
              child: Row(children: [
                const Icon(Icons.account_circle_outlined, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(l10n.artworkMenuUseAvatar)),
              ]),
            ),
          if (showReport &&
              (showOwner || showMkpx || showDownload || anyModEntry || showUseAvatar))
            const PopupMenuDivider(),
          if (showReport)
            PopupMenuItem(
              value: 'report',
              child: Row(children: [
                const Icon(Icons.flag_outlined, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(l10n.artworkMenuReport)),
              ]),
            ),
        ],
      ),
    ];
  }

  /// Open the owner metadata editor; on save it invalidates the detail/feeds
  /// itself, so this just surfaces the confirmation.
  Future<void> _editDetails(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => EditPostDetailsPage(post: post)));
    if (saved == true) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.artworkDetailsSaved)));
    }
  }

  /// Toggle the owner's hide flag (`POST`/`DELETE /post/{id}/hide`), then
  /// refetch the surfaces that filter on it.
  Future<void> _toggleHidden(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final hide = !post.hiddenByUser;
    try {
      await ref.read(postApiProvider).setHidden(post.id, hide);
      ref.invalidate(postDetailProvider(widget.sqid));
      ref.invalidate(feedProvider);
      ref.invalidate(ownerFeedProvider);
      ref.invalidate(hashtagFeedProvider);
      ref.invalidate(pmdListProvider);
      messenger.showSnackBar(SnackBar(
          content: Text(hide ? l10n.artworkHiddenToast : l10n.artworkVisibleToast)));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(hide ? l10n.artworkHideFailed : l10n.artworkUnhideFailed)));
    }
  }

  /// Confirm, then soft-delete the post (7-day grace, like the bulk PMD
  /// delete) and leave the detail page — the post is gone from every feed.
  Future<void> _deletePost(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.artworkDeleteTitle),
        content: Text(ctx.l10n.artworkDeleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.commonDelete)),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref.read(postApiProvider).deletePost(post.id);
      ref.invalidate(feedProvider);
      ref.invalidate(ownerFeedProvider);
      ref.invalidate(hashtagFeedProvider);
      ref.invalidate(pmdListProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.artworkDeleted)));
      nav.pop(); // close the detail view; the grids refetch without it
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.artworkDeleteFailed)));
    }
  }

  void _editModHashtags(BuildContext context, Post post) {
    // ref.read: event handler. The 16 fallback is unreachable in practice —
    // the entry only renders when the config key is present.
    final cap = ref.read(serverConfigProvider).valueOrNull?.maxModHashtagsPerPost ?? 16;
    showModHashtagsSheet(context, post: post, cap: cap);
  }

  // ---- moderator post actions (the website's `p/{sqid}` moderator block) ----

  /// Display name for a `promoted_category` slug, or null for an unknown one —
  /// **read-only**: the app promotes to `frontpage` only (2026-09-17). The
  /// server still accepts the other three slugs, but nothing server-side reads
  /// them (the promoted feed filters on the `promoted` boolean alone; category
  /// follows never shipped), so the app stopped offering them. The names stay
  /// so posts promoted elsewhere into a legacy category still render by name.
  static String? promoteCategoryName(AppLocalizations l10n, String? slug) => switch (slug) {
        'frontpage' => l10n.feedRecommended,
        'editor-pick' => l10n.promoteEditorsPick,
        'weekly-pack' => l10n.promoteWeeklyPack,
        "daily's-best" => l10n.promoteDailysBest,
        _ => null,
      };

  /// Moderation-state chips under the meta line, visible to moderators only —
  /// they carry the state the kebab entries act on (a menu of "Unhide" with no
  /// visible reason reads as a bug).
  Widget _modStatusChips(Post post) {
    Widget chip(IconData icon, String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Flexible(
                child: Text(label,
                    style: TextStyle(fontSize: 11, color: color), overflow: TextOverflow.ellipsis)),
          ]),
        );
    final l10n = context.l10n;
    final chips = <Widget>[
      if (post.hiddenByMod) chip(Icons.visibility_off, l10n.modChipHidden, Colors.redAccent),
      if (!post.publicVisibility) chip(Icons.hourglass_empty, l10n.modChipAwaiting, Colors.amber),
      if (post.promoted)
        chip(
            Icons.star,
            l10n.modChipPromoted(promoteCategoryName(l10n, post.promotedCategory) ??
                post.promotedCategory ??
                '—'),
            Theme.of(context).colorScheme.primary),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  /// Refetch every surface a moderator action can change (detail + feeds).
  void _refreshAfterModAction() {
    ref.invalidate(postDetailProvider(widget.sqid));
    ref.invalidate(feedProvider);
    ref.invalidate(ownerFeedProvider);
    ref.invalidate(hashtagFeedProvider);
  }

  Future<void> _modSetHidden(BuildContext context, Post post, bool hide) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    if (hide) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.modHideTitle),
          content: Text(ctx.l10n.modHideBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.commonHide)),
          ],
        ),
      );
      if (yes != true) return;
    }
    try {
      await ref.read(moderationApiProvider).setModHidden(post.id, hide);
      _refreshAfterModAction();
      messenger.showSnackBar(
          SnackBar(content: Text(hide ? l10n.modHiddenToast : l10n.artworkVisibleToast)));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(hide ? l10n.artworkHideFailed : l10n.artworkUnhideFailed)));
    }
  }

  Future<void> _modPromote(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    // Plain confirmation (the artist is notified). Recommended is the only
    // promotion the app offers — see the note on [promoteCategoryName].
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.modPromoteTitle),
        content: Text(ctx.l10n.modPromoteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.modPromoteAction)),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref.read(moderationApiProvider).promotePost(post.id);
      _refreshAfterModAction();
      messenger.showSnackBar(SnackBar(content: Text(l10n.modPromotedToast)));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.modPromoteFailed)));
    }
  }

  Future<void> _modDemote(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final category = promoteCategoryName(ctx.l10n, post.promotedCategory);
        return AlertDialog(
          title: Text(ctx.l10n.modDemoteTitle),
          content: Text(category != null
              ? ctx.l10n.modDemoteBody(category)
              : ctx.l10n.modDemoteBodyUnknown),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.modDemoteAction)),
          ],
        );
      },
    );
    if (yes != true) return;
    try {
      await ref.read(moderationApiProvider).demotePost(post.id);
      _refreshAfterModAction();
      messenger.showSnackBar(SnackBar(content: Text(l10n.modDemotedToast)));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.modDemoteFailed)));
    }
  }

  Future<void> _modApprovePublic(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await ref.read(moderationApiProvider).setPublicVisibility(post.id, true);
      _refreshAfterModAction();
      messenger.showSnackBar(SnackBar(content: Text(l10n.modApprovedToast)));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.modApproveFailed)));
    }
  }

  /// Irreversible: two-step confirmation (dialog, then a "cannot be undone"
  /// dialog) before `DELETE /post/{id}/permanent`.
  Future<void> _modDeletePermanently(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final l10n = context.l10n;
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.modDeleteForeverTitle),
        content: Text(ctx.l10n.modDeleteForeverBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.commonDelete)),
        ],
      ),
    );
    if (first != true || !context.mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.commentsPurgeFinalTitle),
        content: Text(ctx.l10n
            .modDeleteForeverFinalBody(post.title.isEmpty ? ctx.l10n.untitled : post.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.modKeepPost)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.modDeleteForever),
          ),
        ],
      ),
    );
    if (second != true) return;
    try {
      await ref.read(moderationApiProvider).deletePostPermanently(post.id);
      _refreshAfterModAction();
      messenger.showSnackBar(SnackBar(content: Text(l10n.modDeletedForeverToast)));
      nav.pop(); // leave the detail view — the post no longer exists
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.artworkDeleteFailed)));
    }
  }

  /// Preview-confirm, then have the server snapshot this post's artwork into
  /// the avatar vault (`POST /user/{key}/avatar/from-post`). The 201 returns a
  /// fresh-UUID `avatar_url`, so a plain `reloadMe()` refreshes every avatar
  /// surface — the URL-keyed image cache refetches naturally, no purge needed.
  Future<void> _useAsProfilePhoto(BuildContext context, Post post) async {
    final me = ref.read(authControllerProvider).me;
    if (me == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final go = await showUseAsProfilePhotoDialog(context,
        artUrl: post.artUrl, handle: me.user.handle);
    if (go != true) return;
    try {
      await ref.read(clubApiClientProvider).avatarFromPost(me.user.userKey, post.sqid);
      await ref.read(authControllerProvider.notifier).reloadMe();
      messenger.showSnackBar(SnackBar(content: Text(l10n.avatarFromPostDone)));
    } on ClubError catch (e) {
      if (e.isAuth) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.sessionExpired)));
      } else if (e.isRateLimited) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.avatarFromPostRateLimited)));
      } else if (e.status == 507) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.serverStorageFull)));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.avatarFromPostFailed)));
    }
  }

  /// Golden-button action: download the post's .mkpx and open it in the editor
  /// as a full layered document.
  Future<void> _openLayersInEditor(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final l10n = context.l10n;
    messenger.showSnackBar(SnackBar(content: Text(l10n.layersDownloading)));
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
        messenger.showSnackBar(SnackBar(content: Text(l10n.layersSessionExpired)));
      } else if (e.status == 403 && e.code == 'not_remixable') {
        // The owner turned Remixable off since this page loaded.
        messenger.showSnackBar(SnackBar(content: Text(l10n.layersNotRemixable)));
        ref.invalidate(postDetailProvider(widget.sqid));
      } else if (e.status == 404) {
        // Detached or dropped (artwork replaced) since this payload was fetched.
        messenger.showSnackBar(SnackBar(content: Text(l10n.layersGone)));
        ref.invalidate(postDetailProvider(widget.sqid));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.layersDownloadFailed)));
    }
  }

  /// Attach (or silently replace) the post's layers file from a picked .mkpx.
  /// Pre-checks the magic bytes and the config size cap locally — a rejected
  /// attach would still burn an upload rate-limit token server-side.
  Future<void> _attachMkpx(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    // ref.read (not the watch-based getter): this runs from an event handler.
    final rules = ref.read(serverConfigProvider).valueOrNull?.upload.mkpx ?? MkpxRules.disabled;
    final res = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['mkpx'], withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return; // canceled
    if (!MkpxApi.looksLikeMkpx(bytes)) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.layersNotMkpx)));
      return;
    }
    if (bytes.length > rules.maxFileBytes) {
      messenger.showSnackBar(SnackBar(
          content: Text(l10n
              .layersTooLarge((rules.maxFileBytes / (1024 * 1024)).toStringAsFixed(0)))));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.layersUploading)));
    try {
      await ref.read(mkpxApiProvider).attach(post.id, bytes);
      ref.invalidate(postDetailProvider(widget.sqid));
      messenger.showSnackBar(SnackBar(
          content: Text(post.hasMkpx ? l10n.layersReplaced : l10n.layersAttached)));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.layersUploadFailed)));
    }
  }

  Future<void> _detachMkpx(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.layersRemoveTitle),
        content: Text(ctx.l10n.layersRemoveBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.commonRemove)),
        ],
      ),
    );
    if (go != true) return;
    try {
      await ref.read(mkpxApiProvider).detach(post.id);
      ref.invalidate(postDetailProvider(widget.sqid));
      messenger.showSnackBar(SnackBar(content: Text(l10n.layersRemoved)));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.layersRemoveFailed)));
    }
  }

  /// Share the artwork's PIXELS (not just its link): the scale/format dialog and progress UI are the
  /// same as the editor's ☰ → Share, and the post's URL rides along as the caption. Downloading the
  /// render + re-encoding happen under the shared flow's progress dialog. The engine work lives in
  /// the neutral lib/share module, keeping this social code engine-free.
  Future<void> _shareArtwork(BuildContext context, Post post, String base) async {
    final messenger = ScaffoldMessenger.of(context);
    await shareRasterArtwork(
      context: context,
      fetchRaster: () => ref.read(editApiProvider).downloadArtwork(post.artUrl),
      width: post.width,
      height: post.height,
      frameCount: post.frameCount,
      title: post.title,
      linkUrl: '$base/p/${post.sqid}',
      onError: (m) => messenger.showSnackBar(SnackBar(content: Text(m))),
      onNotice: (m) => messenger.showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 4))),
    );
  }

  /// Download the artwork and hand it to the editor (root) for remix/replace.
  Future<void> _openInEditor(BuildContext context, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final l10n = context.l10n;
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
          SnackBar(content: Text(e is ClubError ? e.message : l10n.artworkOpenFailed)));
    }
  }
}

/// "Use as profile photo" confirmation: previews the artwork rendered
/// avatar-size next to the user's handle — exactly how it will look once set.
/// Pops `true` on confirm. Top-level (not a page method) so it's widget-testable.
Future<bool?> showUseAsProfilePhotoDialog(BuildContext context,
    {required String artUrl, required String handle}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.avatarFromPostTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            HandleAvatar(url: artUrl, handle: handle, radius: 24),
            const SizedBox(width: 12),
            Flexible(child: Text(handle, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 12),
          Text(ctx.l10n.avatarFromPostBody),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.avatarFromPostAction)),
      ],
    ),
  );
}
