import 'package:flutter/material.dart';

import '../models/post.dart';
import 'artwork_detail_page.dart';
import 'profile_page.dart';
import 'widgets/comments_section.dart';
import 'widgets/common.dart';

/// Full-screen comments for one artwork: a small artwork thumbnail + its title up top, then the
/// reusable threaded comments section (likes, replies up to two levels deep, author profile links).
/// Reached from the comment icon/count on an artwork-grid tile.
class CommentsPage extends StatelessWidget {
  final Post post;
  const CommentsPage({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comments')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ArtworkHeader(post: post),
          const Divider(height: 24),
          CommentsSection(postId: post.id),
        ]),
      ),
    );
  }
}

/// (a) artwork thumbnail on the left, (b) title (and owner) to its right. Tapping the thumbnail
/// opens the full artwork; tapping the owner handle opens their profile.
class _ArtworkHeader extends StatelessWidget {
  final Post post;
  const _ArtworkHeader({required this.post});

  @override
  Widget build(BuildContext context) {
    final title = post.title.trim().isEmpty ? 'Untitled' : post.title.trim();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: post.sqid))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 76,
            height: 76,
            color: const Color(0xFF15171A),
            child: PixelArtImage(url: post.artUrl),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(sqid: post.owner.sqid))),
            child: Text('by @${post.owner.handle}', style: const TextStyle(fontSize: 13, color: Colors.white54)),
          ),
        ]),
      ),
    ]);
  }
}
