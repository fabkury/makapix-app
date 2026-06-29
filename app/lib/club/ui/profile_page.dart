import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/feed_providers.dart';
import '../state/player_providers.dart';
import '../state/profile_providers.dart';
import 'artwork_detail_page.dart';
import 'club_account_page.dart';
import 'widgets/common.dart';
import 'widgets/feed_grid.dart';
import 'widgets/send_target_binder.dart';

/// A user's profile: header + stats + follow + gallery.
class ProfilePage extends ConsumerWidget {
  final String sqid;
  const ProfilePage({super.key, required this.sqid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider(sqid));
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
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
}

class _Body extends ConsumerWidget {
  final UserProfile profile;
  const _Body({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gallery = ref.watch(ownerFeedProvider(profile.userKey));
    final gn = ref.read(ownerFeedProvider(profile.userKey).notifier);
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    return SendTargetBinder(
      target: ChannelTarget(
        displayName: profile.handle,
        userSqid: profile.sqid,
        userHandle: profile.handle,
      ),
      child: Column(children: [
      _header(context, ref, signedIn),
      const Divider(height: 1),
      Expanded(
        child: FeedGrid(
          state: gallery,
          onLoadMore: gn.loadMore,
          onRefresh: gn.refresh,
          emptyMessage: 'No posts yet.',
          onTap: (Post p) => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ArtworkDetailPage(
                        sqid: p.sqid,
                        feed: pagedArtworkSource(ownerFeedProvider(profile.userKey),
                            ownerFeedProvider(profile.userKey).notifier),
                      ))),
        ),
      ),
    ]),
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
        if (!p.isOwnProfile)
          SizedBox(
            width: 220,
            child: _FollowButton(sqid: p.sqid, isFollowing: p.isFollowing, signedIn: signedIn),
          ),
      ]),
    );
  }

  Widget _stat(String label, int n) => Column(children: [
        Text('$n', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ]);
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
