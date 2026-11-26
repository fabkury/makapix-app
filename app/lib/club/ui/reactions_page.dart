import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../models/reactions.dart';
import '../state/post_providers.dart';
import 'profile_page.dart';
import 'widgets/artwork_list_header.dart';
import 'widgets/common.dart';

/// Full-screen list of everyone who reacted to an artwork (newest first), reached from the ⚡
/// reactions count on the artwork detail page. Mirrors the website's reactions overlay: a small
/// artwork header, a per-emoji summary, then one row per authenticated reactor — anonymous
/// reactions are not shown, and the server returns only the 200 most recent (unpaginated).
class ReactionsPage extends ConsumerWidget {
  final Post post;
  const ReactionsPage({super.key, required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reactionUsersProvider(post.id));
    final count = async.maybeWhen(data: (r) => r.length, orElse: () => null);
    return Scaffold(
      appBar: AppBar(
          title: Text(count == null
              ? context.l10n.reactionsTitle
              : context.l10n.reactionsTitleCount(count))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ClubErrorRetry(
          message: context.l10n.reactionsLoadError,
          onRetry: () async => ref.invalidate(reactionUsersProvider(post.id)),
        ),
        data: (reactors) => CenteredContent(child: _Body(post: post, reactors: reactors)),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Post post;
  final List<ReactionUser> reactors;
  const _Body({required this.post, required this.reactors});

  @override
  Widget build(BuildContext context) {
    // Counts derived from the fetched rows (authenticated only), so the summary stays consistent
    // with the list below — unlike the post's ReactionTotals, which also include anonymous reactions.
    final counts = ReactionTotals.countEmojis(reactors);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        ArtworkListHeader(post: post),
        const SizedBox(height: 12),
        if (counts.isNotEmpty) _SummaryBar(counts: counts),
        const Divider(height: 24),
        if (reactors.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: ClubEmpty(message: context.l10n.profileNoReactions, icon: Icons.bolt),
          )
        else
          for (final r in reactors) _ReactionRow(r: r),
      ],
    );
  }
}

/// Per-emoji count chips (👍 5  ❤️ 3 …), curated emojis first.
class _SummaryBar extends StatelessWidget {
  final Map<String, int> counts;
  const _SummaryBar({required this.counts});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in counts.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D21),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(e.key, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Text('${e.value}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ]),
          ),
      ],
    );
  }
}

/// One reactor: avatar · handle (tap → profile) · relative time · emoji.
class _ReactionRow extends StatelessWidget {
  final ReactionUser r;
  const _ReactionRow({required this.r});

  @override
  Widget build(BuildContext context) {
    final sqid = r.sqid;
    final open = sqid == null
        ? null
        : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(sqid: sqid)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        GestureDetector(
          onTap: open,
          child: HandleAvatar(url: r.avatarUrl, handle: r.handle, radius: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: open,
            child: Text(
              r.handle.isEmpty ? context.l10n.commentsGuest : r.handle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(timeAgo(r.createdAt), style: const TextStyle(fontSize: 12, color: Colors.white38)),
        const SizedBox(width: 10),
        Text(r.emoji, style: const TextStyle(fontSize: 18)),
      ]),
    );
  }
}
