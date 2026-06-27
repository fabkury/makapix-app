import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../state/paged.dart';
import 'common.dart';

/// Reusable infinite-scroll square grid of posts.
class FeedGrid extends StatefulWidget {
  final PagedState<Post> state;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRefresh;
  final void Function(Post) onTap;
  final String emptyMessage;
  const FeedGrid({
    super.key,
    required this.state,
    required this.onLoadMore,
    required this.onRefresh,
    required this.onTap,
    this.emptyMessage = 'Nothing here yet.',
  });

  @override
  State<FeedGrid> createState() => _FeedGridState();
}

class _FeedGridState extends State<FeedGrid> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 600) widget.onLoadMore();
    });
  }

  @override
  void dispose() {
    _sc.dispose();
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
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(children: [SizedBox(height: 240, child: ClubEmpty(message: widget.emptyMessage))]),
      );
    }
    final cols = (MediaQuery.of(context).size.width / 132).floor().clamp(2, 8);
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: GridView.builder(
        controller: _sc,
        padding: const EdgeInsets.all(4),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols, mainAxisSpacing: 4, crossAxisSpacing: 4),
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
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  const _PostTile({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(fit: StackFit.expand, children: [
          PixelArtImage(url: post.artUrl),
          if (post.isAnimated)
            const Positioned(
              top: 3,
              right: 3,
              child: Icon(Icons.gif_box_outlined, size: 16, color: Colors.white70),
            ),
          if (post.isPlaylist)
            const Positioned(
              top: 3,
              left: 3,
              child: Icon(Icons.playlist_play, size: 16, color: Colors.white70),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: const Color(0x99000000),
              child: Row(children: [
                const Icon(Icons.bolt, size: 11, color: Colors.amberAccent),
                Text(' ${post.reactionCount}', style: const TextStyle(fontSize: 10)),
                const SizedBox(width: 6),
                const Icon(Icons.mode_comment_outlined, size: 11, color: Colors.white70),
                Text(' ${post.commentCount}', style: const TextStyle(fontSize: 10)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
