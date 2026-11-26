import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

import '../../models/post.dart';
import '../artwork_detail_page.dart';
import '../profile_page.dart';
import 'common.dart';

/// The small artwork header above a list about one artwork (who reacted, whose screens
/// displayed it): thumbnail on the left, title and owner to its right. Tapping the thumbnail
/// opens the full artwork; tapping the owner handle opens their profile.
class ArtworkListHeader extends StatelessWidget {
  final Post post;
  const ArtworkListHeader({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final title = post.title.trim().isEmpty ? context.l10n.untitled : post.title.trim();
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
            child: PixelArtImage(
                url: post.artUrl,
                frameCount: post.frameCount,
                width: post.width,
                height: post.height),
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
            child: Text(context.l10n.byHandle(post.owner.handle),
                style: const TextStyle(fontSize: 13, color: Colors.white54)),
          ),
        ]),
      ),
    ]);
  }
}
