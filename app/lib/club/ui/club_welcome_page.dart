import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../state/feed_providers.dart';
import 'artwork_detail_page.dart';
import 'club_account_page.dart';
import 'widgets/feed_grid.dart';

/// Shown to signed-out users (mirrors the website's `/welcome` funnel): a
/// featured promoted-art teaser + a sign-in CTA. The full Recent/Following feeds
/// and all engagement unlock after sign-in. Individual public artworks remain
/// viewable from the teaser (as on the website).
class ClubWelcomePage extends ConsumerWidget {
  const ClubWelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promoted = ref.watch(feedProvider(FeedKind.promoted));
    final n = ref.read(feedProvider(FeedKind.promoted).notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Makapix Club')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(children: [
              const Text('Welcome to Makapix Club',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              const Text(
                'A pixel-art social network — discover art, react, comment, follow, and publish your own.',
                style: TextStyle(color: Colors.white60, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: FilledButton.icon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const ClubAccountPage())),
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in / Create account'),
                ),
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Featured', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
            ),
          ),
          Expanded(
            child: FeedGrid(
              state: promoted,
              onLoadMore: n.loadMore,
              onRefresh: n.refresh,
              emptyMessage: 'Sign in to explore the community.',
              onTap: (Post p) => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: p.sqid))),
            ),
          ),
        ],
      ),
    );
  }
}
