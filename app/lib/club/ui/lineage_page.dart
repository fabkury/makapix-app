import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lineage.dart';
import '../models/post.dart';
import '../state/auth_controller.dart';
import '../state/lineage_providers.dart';
import 'artwork_detail_page.dart';
import 'club_account_page.dart';
import 'widgets/common.dart';
import 'widgets/feed_grid.dart';

/// A post's public lineage (artwork-provenance 0002): the "Original artworks"
/// it declared as Parents (up to 8 slots, in declaration order, including
/// anonymous unavailable / deleted placeholders) above its viewer-visible
/// Remixes as an infinite-scroll grid. The lists are login-gated server-side
/// (the badge/counts on the detail page are the public half), so signed-out
/// viewers get the standard sign-in prompt.
class LineagePage extends ConsumerWidget {
  final Post post;
  const LineagePage({super.key, required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    return Scaffold(
      appBar: AppBar(title: Text('Lineage — ${post.title.isEmpty ? 'Untitled' : post.title}')),
      body: !signedIn
          ? SignInPrompt(
              message: 'Sign in to browse originals and remixes.',
              onSignIn: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ClubAccountPage())),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (post.parentCount > 0) ...[
                _sectionHeader(
                    post.parentCount == 1 ? 'Original artwork' : 'Original artworks'),
                _ParentsStrip(postId: post.id),
              ],
              _sectionHeader(post.childCount > 0
                  ? 'Remixes (${post.childCount})'
                  : 'Remixes'),
              Expanded(child: _ChildrenGrid(postId: post.id)),
            ]),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, color: Colors.white54, fontWeight: FontWeight.w600)),
      );
}

/// The Parent slots as a compact horizontal strip: available parents are
/// tappable artwork tiles; unavailable/deleted slots render as anonymous
/// placeholders in their declared position (L10 — no identity leaked).
class _ParentsStrip extends ConsumerWidget {
  final int postId;
  const _ParentsStrip({required this.postId});

  static const double _tile = 104;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parents = ref.watch(lineageParentsProvider(postId));
    return SizedBox(
      height: _tile + 40,
      child: parents.when(
        loading: () => const Center(
            child: SizedBox(
                height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(lineageParentsProvider(postId)),
            child: const Text('Could not load the originals — retry'),
          ),
        ),
        data: (slots) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: slots.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _ParentTile(slot: slots[i]),
        ),
      ),
    );
  }
}

class _ParentTile extends StatelessWidget {
  final LineageParentSlot slot;
  const _ParentTile({required this.slot});

  @override
  Widget build(BuildContext context) {
    const double side = _ParentsStrip._tile;
    final post = slot.post;
    if (!slot.isAvailable || post == null) {
      // Anonymous placeholder: the parent exists but isn't visible to this
      // viewer, or is deleted (tombstone). Same footprint as a real tile.
      return SizedBox(
        width: side,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: side,
            decoration: BoxDecoration(
                color: kArtworkBackdrop, borderRadius: BorderRadius.circular(4)),
            child: Icon(slot.isDeleted ? Icons.delete_outline : Icons.visibility_off_outlined,
                size: 28, color: Colors.white24),
          ),
          const SizedBox(height: 4),
          Text(slot.isDeleted ? 'Deleted artwork' : 'Not available',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
              overflow: TextOverflow.ellipsis),
        ]),
      );
    }
    return SizedBox(
      width: side,
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: post.sqid))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: side,
            decoration: BoxDecoration(
                color: kArtworkBackdrop, borderRadius: BorderRadius.circular(4)),
            clipBehavior: Clip.antiAlias,
            child: PixelArtImage(
                url: post.artUrl,
                frameCount: post.frameCount,
                width: post.width,
                height: post.height),
          ),
          const SizedBox(height: 4),
          Text(post.title.isEmpty ? 'Untitled' : post.title,
              style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
          Text('@${post.owner.handle}',
              style: const TextStyle(fontSize: 10, color: Colors.white54),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

class _ChildrenGrid extends ConsumerWidget {
  final int postId;
  const _ChildrenGrid({required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lineageChildrenProvider(postId));
    final notifier = ref.read(lineageChildrenProvider(postId).notifier);
    return FeedGrid(
      state: state,
      onLoadMore: notifier.loadMore,
      onRefresh: notifier.refresh,
      emptyMessage: 'No remixes yet.',
      onTap: (p) => Navigator.push(
          context, MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: p.sqid))),
    );
  }
}
