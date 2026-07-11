import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../state/feed_providers.dart';
import '../state/player_providers.dart';
import 'artwork_detail_page.dart';
import 'widgets/feed_grid.dart';
import 'widgets/send_target_binder.dart';

/// Posts for a single hashtag.
class HashtagFeedPage extends ConsumerWidget {
  final String tag;
  const HashtagFeedPage({super.key, required this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hashtagFeedProvider(tag));
    final n = ref.read(hashtagFeedProvider(tag).notifier);
    return SendTargetBinder(
      target: ChannelTarget(displayName: '#$tag', hashtag: tag),
      child: Scaffold(
        appBar: AppBar(title: Text('#$tag')),
        body: FeedGrid(
          state: state,
          onLoadMore: n.loadMore,
          onRefresh: n.refresh,
          emptyMessage: 'No artworks tagged #$tag.',
          onTap: (Post p) => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ArtworkDetailPage(
                        sqid: p.sqid,
                        feed: pagedArtworkSource(
                            hashtagFeedProvider(tag), hashtagFeedProvider(tag).notifier,
                            name: tag, icon: Icons.tag),
                      ))),
        ),
      ),
    );
  }
}
