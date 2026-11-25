import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:makapix_club/l10n/rich.dart';
import 'package:makapix_club/ui/layout.dart';

import '../config/club_config.dart';
import '../models/badge_text.dart';
import '../models/post.dart';
import '../models/pulse_card.dart';
import '../state/paged.dart';
import '../state/pulse_providers.dart';
import 'artwork_detail_page.dart';
import 'profile_page.dart';
import 'widgets/common.dart';

/// The icon of the Pulse page, in the top bar and wherever the page is named.
const IconData kPulseIcon = Icons.local_fire_department;
const IconData kPulseIconOutlined = Icons.local_fire_department_outlined;

/// The Pulse page of the Club home: a timeline of what members do, one card per member, kind
/// of activity, and burst (messages/0008-pulse/). Filter chips on top narrow it by kind; pull
/// to refresh, and coming back to it after a minute refetches quietly.
class PulseView extends ConsumerStatefulWidget {
  const PulseView({super.key});
  @override
  ConsumerState<PulseView> createState() => _PulseViewState();
}

class _PulseViewState extends ConsumerState<PulseView> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 600) {
        ref.read(pulseProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  /// Open a page from a card; back on Pulse, refetch if what is shown has grown old.
  Future<void> _push(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) refreshPulseIfStale(ref);
  }

  void _openProfile(String sqid) => _push(ProfilePage(sqid: sqid));

  /// An artwork of a card, swipeable through that card's other artworks.
  void _openPost(Post post, List<Post> among) => _push(ArtworkDetailPage(
        sqid: post.sqid,
        feed: among.length > 1
            ? ArtworkFeedSource.fixed(among, name: context.l10n.pulseTitle, icon: kPulseIcon)
            : null,
      ));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(pulseProvider);
    final n = ref.read(pulseProvider.notifier);
    final l10n = context.l10n;

    // A server from before Pulse: say so, with nothing to filter.
    if (ref.watch(pulseAvailableProvider) == false && s.items.isEmpty) {
      return _scrollable(n, [
        SizedBox(height: 280, child: ClubEmpty(message: l10n.pulseComingSoon, icon: kPulseIconOutlined)),
      ]);
    }

    final Widget? placeholder = !s.initialized && s.loading
        ? const Center(child: CircularProgressIndicator())
        : s.error != null && s.items.isEmpty
            ? ClubErrorRetry(message: s.error!, onRetry: n.refresh)
            : s.items.isEmpty
                ? ClubEmpty(message: l10n.feedEmpty, icon: kPulseIconOutlined)
                : null;
    if (placeholder != null) {
      return _scrollable(n, [const _FilterChips(), SizedBox(height: 280, child: placeholder)]);
    }

    return RefreshIndicator(
      onRefresh: n.refresh,
      child: ListView.builder(
        controller: _sc,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 12),
        // Chips, then the cards, then the load-more spinner while there are more pages.
        itemCount: s.items.length + 1 + (s.atEnd ? 0 : 1),
        // Cards are matched by id, not by slot: a refresh that puts new cards on top moves
        // the old ones down with their decoded artwork.
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final ix = s.items.indexWhere((c) => c.id == key.value);
          return ix >= 0 ? ix + 1 : null;
        },
        itemBuilder: (ctx, i) {
          if (i == 0) return const _FilterChips();
          final ix = i - 1;
          if (ix >= s.items.length) {
            return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                    child: SizedBox(
                        height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))));
          }
          final card = s.items[ix];
          return CenteredContent(
            key: ValueKey<String>(card.id),
            child: PulseCardTile(card: card, onProfile: _openProfile, onPost: _openPost),
          );
        },
      ),
    );
  }

  // The non-list states still scroll, so pull-to-refresh works on them.
  Widget _scrollable(PagedNotifier<PulseCard> n, List<Widget> children) => RefreshIndicator(
        onRefresh: n.refresh,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: children),
      );
}

/// The row of filter chips above the timeline: one choice at a time, scrolls sideways.
class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selected = ref.watch(pulseFilterProvider);
    String label(PulseFilter f) => switch (f) {
          PulseFilter.all => l10n.pulseFilterAll,
          PulseFilter.artworks => l10n.searchTabArtworks,
          PulseFilter.reactions => l10n.statReactions,
          PulseFilter.comments => l10n.commentsTitle,
          PulseFilter.recommended => l10n.feedRecommended,
          PulseFilter.players => l10n.pulseFilterPlayers,
          PulseFilter.badges => l10n.badgesTitle,
          PulseFilter.reputation => l10n.pulseFilterReputation,
        };
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: PulseFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = PulseFilter.values[i];
          return Center(
            child: ChoiceChip(
              label: Text(label(f)),
              selected: f == selected,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => ref.read(pulseFilterProvider.notifier).state = f,
            ),
          );
        },
      ),
    );
  }
}

/// One card of the timeline: who, what, when, and the kind's own content under it.
class PulseCardTile extends StatelessWidget {
  final PulseCard card;
  final void Function(String sqid) onProfile;
  final void Function(Post post, List<Post> among) onPost;
  const PulseCardTile({super.key, required this.card, required this.onProfile, required this.onPost});

  static const double _thumb = 72;

  String _sentence(AppLocalizations l10n) {
    // notifActor adds the honorific where the language wants one (Japanese さん).
    final who = l10n.notifActor(card.actor.handle);
    return switch (card.kind) {
      PulseKind.likes => l10n.pulseLikes(card.count, who),
      PulseKind.posts => l10n.pulsePosts(card.count, who),
      PulseKind.remixes => l10n.pulseRemixes(card.count, who),
      PulseKind.comments => l10n.pulseComments(card.count, who),
      PulseKind.player => l10n.pulsePlayer(who),
      PulseKind.badge => l10n.pulseBadges(card.count, who),
      PulseKind.reputation => l10n.pulseReputation(who),
      PulseKind.promoted => l10n.pulsePromoted(card.count, who),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final body = _body(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Who did what, when. The whole line opens the member's profile.
          InkWell(
            onTap: () => onProfile(card.actor.sqid),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                HandleAvatar(url: card.actor.avatarUrl, handle: card.actor.handle, radius: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text.rich(TextSpan(children: boldSpans(_sentence(l10n))),
                        style: const TextStyle(fontSize: 14, height: 1.25)),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(timeAgo(card.updatedAt),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ),
              ]),
            ),
          ),
          if (body != null) ...[const SizedBox(height: 10), body],
        ]),
      ),
    );
  }

  Widget? _body(BuildContext context) => switch (card.kind) {
        PulseKind.likes || PulseKind.posts || PulseKind.remixes || PulseKind.promoted => _thumbRow(context),
        PulseKind.comments => _commentList(context),
        PulseKind.player => _playerLine(context),
        PulseKind.badge => _badgeWrap(context),
        PulseKind.reputation => _reputationLine(context),
      };

  /// "+N more", for the events a card counts but does not carry.
  Widget _more(BuildContext context) => Text(context.l10n.pulseMore(card.more),
      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant));

  // One row of square thumbnails that scrolls sideways; "+N more" closes it and leads to the
  // member's profile, where the rest can be found.
  Widget _thumbRow(BuildContext context) {
    final posts = card.posts;
    final more = card.more;
    return SizedBox(
      height: _thumb,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: posts.length + (more > 0 ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          if (i >= posts.length) {
            return InkWell(
              onTap: () => onProfile(card.actor.sqid),
              child: Container(
                constraints: const BoxConstraints(minWidth: _thumb),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: _more(ctx),
              ),
            );
          }
          final p = posts[i];
          return GestureDetector(
            onTap: () => onPost(p, posts),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: _thumb,
                height: _thumb,
                color: kArtworkBackdrop,
                child: PixelArtImage(
                    url: p.artUrl, frameCount: p.frameCount, width: p.width, height: p.height),
              ),
            ),
          );
        },
      ),
    );
  }

  // Up to three comments: the artwork each is on, and what was said.
  Widget _commentList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final c in card.comments)
        InkWell(
          onTap: () => onPost(c.post, const []),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 40,
                  height: 40,
                  color: kArtworkBackdrop,
                  child: PixelArtImage(
                      url: c.post.artUrl,
                      frameCount: c.post.frameCount,
                      width: c.post.width,
                      height: c.post.height),
                ),
              ),
              const SizedBox(width: 10),
              if (c.isReply) ...[
                Icon(Icons.subdirectory_arrow_right, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(c.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ),
            ]),
          ),
        ),
      if (card.more > 0)
        Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: _more(context)),
    ]);
  }

  // The device's model, when it reports one (the name its owner typed is not public).
  Widget? _playerLine(BuildContext context) {
    final model = card.playerModel;
    if (model == null || model.isEmpty) return null;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(Icons.cast, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(model, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
      ]),
    );
  }

  Widget _badgeWrap(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 14, runSpacing: 8, children: [
          for (final b in card.badges)
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (b.iconUrl64.isEmpty)
                const Icon(Icons.shield_outlined, size: 32)
              else
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CachedNetworkImage(
                      imageUrl: resolveClubUrl(b.iconUrl64),
                      filterQuality: FilterQuality.none,
                      errorWidget: (_, _, _) => const Icon(Icons.shield_outlined, size: 32)),
                ),
              const SizedBox(width: 8),
              Flexible(child: Text(badgeLabel(b.badge, b.label), style: const TextStyle(fontSize: 13))),
            ]),
        ]),
      );

  Widget _reputationLine(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = card.reputationTotal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        // A signed number reads the same in every language.
        Text('+${compactCount(card.reputationDelta)}', // l10n-ignore: a number
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary)),
        if (total != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(context.l10n.pulseReputationTotal(compactCount(total)),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
        ],
      ]),
    );
  }
}
