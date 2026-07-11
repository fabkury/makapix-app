import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../cache/artwork_cache.dart';
import '../models/club_error.dart';
import '../models/post.dart';
import '../models/report.dart';
import '../models/safety_copy.dart';
import '../models/server_config.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/edit_bridge.dart';
import '../state/feed_providers.dart';
import '../state/player_providers.dart';
import '../state/profile_providers.dart';
import '../state/publish_providers.dart';
import '../state/safety_providers.dart';
import 'artist_dashboard_page.dart';
import 'artwork_detail_page.dart';
import 'club_account_page.dart';
import 'edit_profile_page.dart';
import 'report_page.dart';
import 'widgets/common.dart';
import 'widgets/external_links.dart';
import 'widgets/feed_grid.dart';
import 'widgets/send_target_binder.dart';

/// A user's profile: header + stats + follow + gallery. When the moderation
/// feature is live, an overflow menu adds report + block/unblock; a blocked
/// user renders a header + banner (never a fake 404 — contract D14).
class ProfilePage extends ConsumerWidget {
  final String sqid;
  const ProfilePage({super.key, required this.sqid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider(sqid));
    // ref.watch so the menu appears once the config future resolves; the menu
    // needs the resolved profile (built before the fetch completes → hidden).
    final rules = ref.watch(serverConfigProvider).valueOrNull?.moderation;
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    final profile = async.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(profile == null ? 'Profile' : '@${profile.handle}'),
        actions: [
          if (profile != null && !profile.isBlockedByViewer) _shareButton(context, ref, profile),
          if (rules != null && profile != null && !profile.isOwnProfile)
            _menu(context, ref, profile, signedIn, rules),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ClubErrorRetry(
          message: e is ClubError ? e.message : 'Could not load profile.',
          onRetry: () => ref.read(profileProvider(sqid).notifier).load(),
        ),
        data: (p) => _Body(profile: p),
      ),
    );
  }

  /// Tap shares the profile's web link; long-press copies just the link
  /// (mirrors the artwork page's share affordance).
  Widget _shareButton(BuildContext context, WidgetRef ref, UserProfile p) {
    final url = '${ref.watch(clubConfigProvider).baseUrl}/u/${p.sqid}';
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Link copied')));
      },
      child: IconButton(
        icon: const Icon(Icons.share),
        tooltip: 'Share profile (long-press to copy link)',
        onPressed: () =>
            SharePlus.instance.share(ShareParams(text: '@${p.handle} on Makapix Club — $url')),
      ),
    );
  }

  Widget _menu(
      BuildContext context, WidgetRef ref, UserProfile p, bool signedIn, ModerationRules rules) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      onSelected: (v) {
        switch (v) {
          case 'report':
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => ReportPage(target: ReportTarget.user(p))));
          case 'block':
            _confirmBlock(context, ref, p, rules);
          case 'unblock':
            _unblock(context, ref, p, rules);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'report',
          child: Row(children: [
            Icon(Icons.flag_outlined, size: 18),
            SizedBox(width: 10),
            Text('Report user…'),
          ]),
        ),
        if (signedIn && !p.isBlockedByViewer)
          PopupMenuItem(
            value: 'block',
            child: Row(children: [
              const Icon(Icons.block, size: 18),
              const SizedBox(width: 10),
              Text('Block @${p.handle}…'),
            ]),
          ),
        if (signedIn && p.isBlockedByViewer)
          PopupMenuItem(
            value: 'unblock',
            child: Row(children: [
              const Icon(Icons.lock_open, size: 18),
              const SizedBox(width: 10),
              Text('Unblock @${p.handle}'),
            ]),
          ),
      ],
    );
  }

  Future<void> _confirmBlock(
      BuildContext context, WidgetRef ref, UserProfile p, ModerationRules rules) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Block @${p.handle}?'),
        content: const Text(
            "They won't be able to comment on your posts, react to them, or follow you — and you "
            "won't see their content. You can unblock them anytime in Settings → Blocked users."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Block')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await blockUser(ref, p.sqid);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Blocked @${p.handle}')));
      }
    } on ClubError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(blockErrorMessage(e, maxBlocksPerUser: rules.maxBlocksPerUser))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not update the block — try again.')));
      }
    }
  }

  Future<void> _unblock(
      BuildContext context, WidgetRef ref, UserProfile p, ModerationRules rules) async {
    try {
      await unblockUser(ref, p.sqid);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Unblocked @${p.handle}')));
      }
    } on ClubError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(blockErrorMessage(e, maxBlocksPerUser: rules.maxBlocksPerUser))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not update the block — try again.')));
      }
    }
  }
}

/// The profile's tab set. Gallery is always present; Reacted only for
/// signed-in viewers. Highlights are not a tab — they get the showcase
/// strip between the header and the tab bar.
enum ProfileTab { gallery, reacted }

List<ProfileTab> profileTabsFor({required bool signedIn}) => [
      ProfileTab.gallery,
      if (signedIn) ProfileTab.reacted,
    ];

class _Body extends ConsumerWidget {
  final UserProfile profile;
  const _Body({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    // Blocked: keep the header, but hide the gallery + follow behind a banner.
    if (profile.isBlockedByViewer) {
      return Column(children: [
        _header(context, ref, signedIn),
        const Divider(height: 1),
        Expanded(child: _blockedBanner(context, ref)),
      ]);
    }
    final tabs = profileTabsFor(signedIn: signedIn);
    return SendTargetBinder(
      target: ChannelTarget(
        displayName: profile.handle,
        userSqid: profile.sqid,
        userHandle: profile.handle,
      ),
      child: DefaultTabController(
        length: tabs.length,
        // Value-equal across rebuilds: the controller remounts only when the
        // tab set genuinely changes (sign-in/out) — not on ordinary rebuilds
        // or token refreshes.
        key: ValueKey('profile-tabs:${tabs.length}:$signedIn'),
        child: Builder(builder: (context) {
          return RefreshIndicator(
            // Grid pulls arrive at depth 2 (outer → TabBarView page → grid);
            // depth 0 keeps pulls on the expanded header working. The
            // indicator's own axis check filters the horizontal PageView.
            notificationPredicate: (n) => n.depth == 2 || n.depth == 0,
            onRefresh: () => _refresh(ref, tabs, DefaultTabController.of(context).index),
            child: NestedScrollView(
              // Nothing pinned here: the TabBar lives in the body, so no
              // sliver-overlap machinery is needed.
              headerSliverBuilder: (_, _) => [
                SliverToBoxAdapter(
                    child: Column(children: [
                  _header(context, ref, signedIn),
                  if (profile.highlights.isNotEmpty) _HighlightsStrip(profile: profile),
                  const Divider(height: 1),
                ])),
              ],
              body: Column(children: [
                if (tabs.length > 1) ...[
                  TabBar(
                    tabs: [for (final t in tabs) _tab(t)],
                    labelStyle: const TextStyle(fontSize: 13),
                  ),
                  const Divider(height: 1),
                ],
                Expanded(
                  child: TabBarView(children: [
                    for (final t in tabs)
                      switch (t) {
                        ProfileTab.gallery => _GalleryTab(profile: profile),
                        ProfileTab.reacted => _ReactedTab(profile: profile),
                      },
                  ]),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }

  Widget _tab(ProfileTab t) {
    final (icon, label) = switch (t) {
      ProfileTab.gallery => (Icons.grid_on, 'Gallery'),
      ProfileTab.reacted => (Icons.bolt, 'Reacted'),
    };
    return Tab(
      height: 40,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label),
      ]),
    );
  }

  /// Silent profile reload + refresh of only the active tab's feed. Never
  /// touches a notifier whose provider was never instantiated (creating an
  /// autoDispose provider just to refresh it double-fetches, then disposes
  /// mid-flight).
  Future<void> _refresh(WidgetRef ref, List<ProfileTab> tabs, int index) async {
    final futures = <Future<void>>[
      ref.read(profileProvider(profile.sqid).notifier).reload(),
    ];
    // The highlights strip rides along with the profile reload.
    switch (tabs[index]) {
      case ProfileTab.gallery:
        futures.add(ref.read(ownerFeedProvider(profile.userKey).notifier).refresh());
      case ProfileTab.reacted:
        futures.add(ref.read(reactedFeedProvider(profile.sqid).notifier).refresh());
    }
    await Future.wait(futures);
  }

  Widget _blockedBanner(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.block, size: 40, color: cs.outline),
          const SizedBox(height: 12),
          Text("You've blocked @${profile.handle}. They can't interact with you, and you won't "
              'see their content.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              try {
                await unblockUser(ref, profile.sqid);
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Unblocked @${profile.handle}')));
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not update the block — try again.')));
                }
              }
            },
            icon: const Icon(Icons.lock_open, size: 18),
            label: const Text('Unblock'),
          ),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref, bool signedIn) {
    final p = profile;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _avatar(context, p),
        const SizedBox(height: 8),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(p.handle,
                style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis),
          ),
          if (p.reputation > 0) ...[
            const SizedBox(width: 8),
            _RepChip(reputation: p.reputation),
          ],
        ]),
        if (p.tagline != null && p.tagline!.isNotEmpty)
          Text(p.tagline!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        if (p.bio != null && p.bio!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(p.bio!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          ),
        if (p.website != null && p.website!.isNotEmpty) _websiteLink(context, p.website!),
        if (p.tagBadges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, children: [
              for (final b in p.tagBadges)
                Chip(
                  avatar: b.iconUrl16 == null
                      ? null
                      : CircleAvatar(
                          backgroundColor: Colors.transparent,
                          backgroundImage: CachedNetworkImageProvider(b.iconUrl16!)),
                  label: Text(b.label, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
            ]),
          ),
        const SizedBox(height: 12),
        _statsRow(context, p),
        const SizedBox(height: 12),
        // Own profile → Edit; blocked → the banner owns Unblock (no button here);
        // otherwise → Follow.
        if (!p.isBlockedByViewer)
          SizedBox(
            width: 220,
            child: p.isOwnProfile
                ? OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => EditProfilePage(profile: p)));
                      // Avatar changes apply immediately and Save may have landed —
                      // re-fetch so the header reflects them (silently, so the
                      // tab selection and scroll survive the return).
                      ref.read(profileProvider(p.sqid).notifier).reload();
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit profile'),
                  )
                : _FollowButton(sqid: p.sqid, isFollowing: p.isFollowing, signedIn: signedIn),
          ),
      ]),
    );
  }

  /// The header avatar; when an image exists, tap opens a full-size
  /// nearest-neighbor viewer (pixel avatars deserve a crisp zoom).
  Widget _avatar(BuildContext context, UserProfile p) {
    final avatar = HandleAvatar(url: p.avatarUrl, handle: p.handle, radius: 36);
    if (p.avatarUrl == null || p.avatarUrl!.isEmpty) return avatar;
    final tag = 'profile-avatar-${p.sqid}';
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => _AvatarViewer(url: p.avatarUrl!, handle: p.handle, heroTag: tag))),
      child: Hero(tag: tag, child: avatar),
    );
  }

  Widget _websiteLink(BuildContext context, String website) {
    final cs = Theme.of(context).colorScheme;
    // Display without the scheme; launch with one (the field may omit it).
    final label = website.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');
    final url = website.startsWith(RegExp(r'https?://')) ? website : 'https://$website';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () => openExternalUrl(context, url),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.link, size: 14, color: cs.primary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: cs.primary),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
    );
  }

  /// Posts · Followers · Reactions · Views. On your own profile the row is
  /// tappable and opens the Artist Dashboard (the full stats surface).
  Widget _statsRow(BuildContext context, UserProfile p) {
    final row = Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _stat(context, 'Posts', p.stats.totalPosts),
      _stat(context, 'Followers', p.stats.followerCount),
      _stat(context, 'Reactions', p.stats.totalReactionsReceived),
      _stat(context, 'Views', p.stats.totalViews),
    ]);
    if (!p.isOwnProfile) return row;
    return Tooltip(
      message: 'View your stats',
      child: InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ArtistDashboardPage(userKey: p.sqid))),
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, int n) => Column(children: [
        Text(compactCount(n), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
}

/// Small reputation pill beside the handle; tap for the explainer tooltip.
class _RepChip extends StatelessWidget {
  final int reputation;
  const _RepChip({required this.reputation});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Reputation: $reputation — earned through activity in the Club',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, size: 12, color: cs.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(compactCount(reputation),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
        ]),
      ),
    );
  }
}

/// Full-screen avatar viewer: black backdrop, pinch-zoom with chunky pixels
/// (nearest-neighbor), tap anywhere to dismiss.
class _AvatarViewer extends StatelessWidget {
  final String url;
  final String handle;
  final String heroTag;
  const _AvatarViewer({required this.url, required this.handle, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: SafeArea(
          child: Stack(children: [
            Center(
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  maxScale: 16,
                  child: Image(
                    image: CachedNetworkImageProvider(url, cacheManager: avatarImageCache),
                    filterQuality: FilterQuality.none,
                    fit: BoxFit.contain,
                    semanticLabel: "@$handle's avatar",
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image, color: Colors.white24, size: 40),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Each tab watches its own provider, so a feed is fetched only when its tab
/// actually builds (opening a profile never eagerly fetches reacted-posts).
class _GalleryTab extends ConsumerWidget {
  final UserProfile profile;
  const _GalleryTab({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ownerFeedProvider(profile.userKey));
    final n = ref.read(ownerFeedProvider(profile.userKey).notifier);
    return FeedGrid(
      key: const PageStorageKey('profile-gallery'),
      nested: true,
      state: state,
      onLoadMore: n.loadMore,
      onRefresh: () async {}, // the page owns refresh
      emptyMessage: 'No posts yet.',
      // Your own empty gallery is the best moment to start creating.
      empty: profile.isOwnProfile ? const _CreateFirstArtEmpty() : null,
      onTap: (Post p) => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ArtworkDetailPage(
                    sqid: p.sqid,
                    feed: pagedArtworkSource(ownerFeedProvider(profile.userKey),
                        ownerFeedProvider(profile.userKey).notifier),
                  ))),
    );
  }
}

/// Empty-state CTA for your own gallery: jump straight into the editor.
class _CreateFirstArtEmpty extends ConsumerWidget {
  const _CreateFirstArtEmpty();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.brush_outlined, size: 40, color: cs.outline),
        const SizedBox(height: 12),
        Text('Your gallery is waiting.', style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => ref.read(openEditorProvider.notifier).state++,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Create your first pixel art'),
        ),
      ]),
    );
  }
}

class _ReactedTab extends ConsumerWidget {
  final UserProfile profile;
  const _ReactedTab({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reactedFeedProvider(profile.sqid));
    final n = ref.read(reactedFeedProvider(profile.sqid).notifier);
    return FeedGrid(
      key: const PageStorageKey('profile-reacted'),
      nested: true,
      state: state,
      onLoadMore: n.loadMore,
      onRefresh: () async {}, // the page owns refresh
      emptyMessage: 'No reactions yet.',
      onTap: (Post p) => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ArtworkDetailPage(
                    sqid: p.sqid,
                    feed: pagedArtworkSource(reactedFeedProvider(profile.sqid),
                        reactedFeedProvider(profile.sqid).notifier),
                  ))),
    );
  }
}

/// The artist's self-curated best work, showcased as a horizontal strip
/// between the header and the tab bar (display-only, §14: the highlights ride
/// in the profile payload; pin/unpin management is C4 backlog). The
/// RefreshIndicator's axis check keeps this horizontal scroll from
/// triggering pull-to-refresh.
class _HighlightsStrip extends StatelessWidget {
  final UserProfile profile;
  const _HighlightsStrip({required this.profile});

  static const double _tile = 108;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Icon(Icons.diamond_outlined, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text('HIGHLIGHTS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: cs.onSurfaceVariant)),
        ]),
      ),
      SizedBox(
        height: _tile,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: profile.highlights.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _HighlightTile(
            post: profile.highlights[i],
            size: _tile,
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ArtworkDetailPage(
                          sqid: profile.highlights[i].sqid,
                          feed: ArtworkFeedSource.fixed(profile.highlights),
                        ))),
          ),
        ),
      ),
      const SizedBox(height: 12),
    ]);
  }
}

class _HighlightTile extends StatelessWidget {
  final Post post;
  final double size;
  final VoidCallback onTap;
  const _HighlightTile({required this.post, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: PixelArtImage(
          url: post.artUrl,
          fit: BoxFit.cover,
          frameCount: post.frameCount,
          width: post.width,
          height: post.height,
        ),
      ),
    );
  }
}

class _FollowButton extends ConsumerWidget {
  final String sqid;
  final bool isFollowing;
  final bool signedIn;
  const _FollowButton({required this.sqid, required this.isFollowing, required this.signedIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      onPressed: () async {
        if (!signedIn) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubAccountPage()));
          return;
        }
        final err = await ref.read(profileProvider(sqid).notifier).toggleFollow();
        if (err != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        }
      },
      style: isFollowing
          ? FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: Theme.of(context).colorScheme.onSurface)
          : null,
      icon: Icon(isFollowing ? Icons.check : Icons.person_add_alt_1, size: 18),
      label: Text(isFollowing ? 'Following' : 'Follow'),
    );
  }
}
