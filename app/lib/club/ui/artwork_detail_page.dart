import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../edit/club_edit_request.dart';
import '../models/club_error.dart';
import '../models/post.dart';
import '../state/api_providers.dart';
import '../state/auth_controller.dart';
import '../state/edit_bridge.dart';
import '../state/post_providers.dart';
import 'hashtag_feed_page.dart';
import 'profile_page.dart';
import 'widgets/comments_section.dart';
import 'widgets/common.dart';
import 'widgets/reactions_bar.dart';

/// Full artwork view: image, metadata, owner, reactions, and comments.
class ArtworkDetailPage extends ConsumerWidget {
  final String sqid;
  const ArtworkDetailPage({super.key, required this.sqid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(postDetailProvider(sqid));
    final base = ref.watch(clubConfigProvider).baseUrl;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artwork'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Copy link',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$base/p/$sqid'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ClubErrorRetry(
          message: e is ClubError ? e.message : 'Could not load this artwork.',
          onRetry: () async => ref.invalidate(postDetailProvider(sqid)),
        ),
        data: (post) => _DetailBody(post: post),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final Post post;
  const _DetailBody({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        // Artwork on a dark stage: stretched (aspect-ratio preserved) to 94% of the width,
        // leaving only a thin 3% margin on each side, but never taller than 70% of the screen
        // (tall/portrait pieces letterbox within that cap instead of dominating the page).
        Container(
          color: const Color(0xFF0E1012),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width * 0.03, vertical: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.70),
            child: AspectRatio(
              aspectRatio: post.height > 0 ? post.width / post.height : 1,
              child: PixelArtImage(url: post.artUrl),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(post.title.isEmpty ? 'Untitled' : post.title,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            // Owner
            InkWell(
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ProfilePage(sqid: post.owner.sqid))),
              child: Row(children: [
                HandleAvatar(url: post.owner.avatarUrl, handle: post.owner.handle, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(post.owner.handle, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (post.owner.tagline != null && post.owner.tagline!.isNotEmpty)
                      Text(post.owner.tagline!,
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ]),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openInEditor(context, ref),
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Edit in Makapix'),
            ),
            const SizedBox(height: 16),
            if (post.description != null && post.description!.isNotEmpty) ...[
              Text(post.description!, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
            ],
            if (post.hashtags.isNotEmpty)
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  // Borderless, vivid-coloured text — reads as a tappable link, not a badge.
                  for (final tag in post.hashtags)
                    GestureDetector(
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => HashtagFeedPage(tag: tag))),
                      child: Text('#$tag',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary)),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            _meta(post),
            const Divider(height: 24),
            ReactionsBar(postId: post.id),
            const Divider(height: 24),
            CommentsSection(postId: post.id),
          ]),
        ),
      ],
    );
  }

  /// Download the artwork and hand it to the editor (root) for remix/replace.
  Future<void> _openInEditor(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Loading artwork into the editor…')));
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
      );
      nav.popUntil((r) => r.isFirst); // surface the editor (app root)
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(e is ClubError ? e.message : 'Could not load artwork.')));
    }
  }

  Widget _meta(Post post) {
    final parts = <String>[
      '${post.width}×${post.height}',
      post.isAnimated ? '${post.frameCount} frames' : 'static',
      if (post.uniqueColors != null) '${post.uniqueColors} colors',
      if (post.license != null) post.license!.identifier,
    ];
    return Text(parts.join('  ·  '), style: const TextStyle(fontSize: 12, color: Colors.white38));
  }
}
