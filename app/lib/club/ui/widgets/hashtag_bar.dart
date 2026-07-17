import 'package:flutter/material.dart';

import '../hashtag_feed_page.dart';

/// A thin strip of trending `#hashtag` links under the home top bar, mirroring
/// the website's header bottom row. Horizontally scrollable, no wrapping, no
/// animation — the set changes only when the parent supplies fresh [tags]
/// (server-driven rotation). Tapping a tag opens its feed.
///
/// Implements [PreferredSizeWidget] so it can sit in `AppBar.bottom`. The parent
/// only mounts it when there are tags to show, so this never renders empty.
class HashtagBar extends StatelessWidget implements PreferredSizeWidget {
  final List<String> tags;
  const HashtagBar({super.key, required this.tags});

  static const double _height = 36;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: _height,
      alignment: Alignment.centerLeft,
      color: cs.surfaceContainerHighest,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (ctx, i) {
          final tag = tags[i];
          return InkWell(
            onTap: () => Navigator.push(
                ctx, MaterialPageRoute(builder: (_) => HashtagFeedPage(tag: tag))),
            child: Center(
              child: Text(
                '#$tag',
                softWrap: false,
                overflow: TextOverflow.fade,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
              ),
            ),
          );
        },
      ),
    );
  }
}
