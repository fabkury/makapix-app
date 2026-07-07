import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../../state/auth_controller.dart';
import '../../state/paged.dart';
import '../../state/post_providers.dart';
import '../club_account_page.dart';
import '../comments_page.dart';
import 'common.dart';

/// Reusable infinite-scroll square grid of posts.
///
/// [nested] mounts the grid as the inner scrollable of a `NestedScrollView`
/// (the profile tabs): the grid uses the inner `PrimaryScrollController`
/// instead of its own, load-more triggers off scroll notifications, and the
/// internal `RefreshIndicator` is skipped — the host page owns refresh
/// (so `onRefresh` goes unused there; pass a no-op).
class FeedGrid extends StatefulWidget {
  final PagedState<Post> state;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRefresh;
  final void Function(Post) onTap;
  final String emptyMessage;
  final bool nested;
  const FeedGrid({
    super.key,
    required this.state,
    required this.onLoadMore,
    required this.onRefresh,
    required this.onTap,
    this.emptyMessage = 'Nothing here yet.',
    this.nested = false,
  });

  @override
  State<FeedGrid> createState() => _FeedGridState();
}

class _FeedGridState extends State<FeedGrid> {
  ScrollController? _sc;

  @override
  void initState() {
    super.initState();
    if (!widget.nested) {
      final sc = ScrollController();
      sc.addListener(() {
        if (sc.position.pixels > sc.position.maxScrollExtent - 600) widget.onLoadMore();
      });
      _sc = sc;
    }
  }

  @override
  void dispose() {
    _sc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (!s.initialized && s.loading) return const Center(child: CircularProgressIndicator());
    if (s.error != null && s.items.isEmpty) {
      return ClubErrorRetry(message: s.error!, onRetry: widget.onRefresh);
    }
    if (s.items.isEmpty) {
      final empty = ListView(
          primary: widget.nested ? true : null,
          children: [SizedBox(height: 240, child: ClubEmpty(message: widget.emptyMessage))]);
      if (widget.nested) return empty;
      return RefreshIndicator(onRefresh: widget.onRefresh, child: empty);
    }
    final cols = (MediaQuery.of(context).size.width / 132).floor().clamp(2, 8);
    final grid = GridView.builder(
      controller: _sc,
      primary: widget.nested ? true : null,
      padding: const EdgeInsets.all(4),
      // Cells are a little taller than wide to fit the info bar below a ~square artwork.
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 0.84),
      itemCount: s.items.length + (s.atEnd ? 0 : 1),
      itemBuilder: (ctx, i) {
        if (i >= s.items.length) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        return _PostTile(post: s.items[i], onTap: () => widget.onTap(s.items[i]));
      },
    );
    if (widget.nested) {
      // Wraps ONLY the grid, so notifications from the outer NestedScrollView /
      // TabBarView never pass through here (they bubble from ancestors).
      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0 &&
              n.metrics.axis == Axis.vertical &&
              n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
            widget.onLoadMore();
          }
          return false;
        },
        child: grid,
      );
    }
    return RefreshIndicator(onRefresh: widget.onRefresh, child: grid);
  }
}

class _PostTile extends ConsumerWidget {
  final Post post;
  final VoidCallback onTap;
  const _PostTile({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Animated and static artworks are displayed alike (no GIF badge).
    final like = ref.watch(gridLikesProvider.select((m) => m[post.id])) ??
        GridLikeState(post.userHasLiked, post.reactionCount);
    final likeColor = like.liked ? const Color(0xFF4DA3FF) : Colors.white60;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                PixelArtImage(
                    url: post.artUrl,
                    frameCount: post.frameCount,
                    width: post.width,
                    height: post.height),
                if (post.isPlaylist)
                  const Positioned(
                    top: 3,
                    left: 3,
                    child: Icon(Icons.playlist_play, size: 16, color: Colors.white70),
                  ),
              ]),
            ),
            // Solid info bar directly below the artwork: likes (left, tappable) · comments (right).
            Container(
              color: const Color(0xFF2A2D31),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleLike(context, ref),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(like.liked ? Icons.thumb_up : Icons.thumb_up_outlined, size: 14, color: likeColor),
                    const SizedBox(width: 4),
                    Text('${like.count}', style: TextStyle(fontSize: 11, color: likeColor)),
                  ]),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => CommentsPage(post: post))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.mode_comment_outlined, size: 13, color: Colors.white60),
                    const SizedBox(width: 4),
                    Text('${post.commentCount}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(BuildContext context, WidgetRef ref) async {
    if (!ref.read(authControllerProvider).isSignedIn) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubAccountPage()));
      return;
    }
    final err = await ref.read(gridLikesProvider.notifier).toggle(post);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}
