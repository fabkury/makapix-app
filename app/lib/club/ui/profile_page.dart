import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/post.dart';
import '../models/report.dart';
import '../models/safety_copy.dart';
import '../models/server_config.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/feed_providers.dart';
import '../state/paged.dart';
import '../state/player_providers.dart';
import '../state/profile_providers.dart';
import '../state/publish_providers.dart';
import '../state/safety_providers.dart';
import 'artwork_detail_page.dart';
import 'club_account_page.dart';
import 'edit_profile_page.dart';
import 'report_page.dart';
import 'widgets/common.dart';
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
        title: const Text('Profile'),
        actions: [
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
/// signed-in viewers; Highlights only when the profile has any.
enum ProfileTab { gallery, reacted, highlights }

List<ProfileTab> profileTabsFor({required bool signedIn, required bool hasHighlights}) => [
      ProfileTab.gallery,
      if (signedIn) ProfileTab.reacted,
      if (hasHighlights) ProfileTab.highlights,
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
    final tabs = profileTabsFor(signedIn: signedIn, hasHighlights: profile.highlights.isNotEmpty);
    return SendTargetBinder(
      target: ChannelTarget(
        displayName: profile.handle,
        userSqid: profile.sqid,
        userHandle: profile.handle,
      ),
      child: DefaultTabController(
        length: tabs.length,
        // Value-equal across rebuilds: the controller remounts only when the
        // tab set genuinely changes (sign-in/out, highlights appearing) — not
        // on ordinary rebuilds or token refreshes.
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
                        ProfileTab.highlights => _HighlightsTab(profile: profile),
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
      ProfileTab.highlights => (Icons.diamond_outlined, 'Highlights'),
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
    switch (tabs[index]) {
      case ProfileTab.gallery:
        futures.add(ref.read(ownerFeedProvider(profile.userKey).notifier).refresh());
      case ProfileTab.reacted:
        futures.add(ref.read(reactedFeedProvider(profile.sqid).notifier).refresh());
      case ProfileTab.highlights:
        break; // rides along with the profile reload
    }
    await Future.wait(futures);
  }

  Widget _blockedBanner(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.block, size: 40, color: Colors.white30),
          const SizedBox(height: 12),
          Text("You've blocked @${profile.handle}. They can't interact with you, and you won't "
              'see their content.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        HandleAvatar(url: p.avatarUrl, handle: p.handle, radius: 36),
        const SizedBox(height: 8),
        Text(p.handle, style: Theme.of(context).textTheme.titleLarge),
        if (p.tagline != null && p.tagline!.isNotEmpty)
          Text(p.tagline!, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        if (p.bio != null && p.bio!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(p.bio!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          ),
        if (p.tagBadges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, children: [
              for (final b in p.tagBadges)
                Chip(label: Text(b.label, style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
            ]),
          ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _stat('Posts', p.stats.totalPosts),
          _stat('Followers', p.stats.followerCount),
          _stat('Views', p.stats.totalViews),
          _stat('Rep', p.reputation),
        ]),
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

  Widget _stat(String label, int n) => Column(children: [
        Text('$n', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ]);
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

/// Display-only (§14): the highlights ride in the profile payload; pin/unpin
/// management is C4 backlog.
class _HighlightsTab extends ConsumerWidget {
  final UserProfile profile;
  const _HighlightsTab({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FeedGrid(
      key: const PageStorageKey('profile-highlights'),
      nested: true,
      state: PagedState<Post>(items: profile.highlights, atEnd: true, initialized: true),
      onLoadMore: () async {},
      onRefresh: () async {},
      emptyMessage: 'No highlights.',
      onTap: (Post p) => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ArtworkDetailPage(
                    sqid: p.sqid,
                    feed: ArtworkFeedSource.fixed(profile.highlights),
                  ))),
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
      style: isFollowing ? FilledButton.styleFrom(backgroundColor: const Color(0xFF2A2D31)) : null,
      icon: Icon(isFollowing ? Icons.check : Icons.person_add_alt_1, size: 18),
      label: Text(isFollowing ? 'Following' : 'Follow'),
    );
  }
}
