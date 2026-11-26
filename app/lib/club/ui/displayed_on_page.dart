import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:makapix_club/ui/layout.dart';

import '../models/impression_user.dart';
import '../models/post.dart';
import '../state/auth_controller.dart';
import '../state/post_providers.dart';
import 'club_account_page.dart';
import 'profile_page.dart';
import 'widgets/artwork_list_header.dart';
import 'widgets/common.dart';

/// "Displayed on": the members whose screens showed an artwork, reached from the 📺
/// impressions count on the artwork detail page, the way ⚡ opens the Reactions page. Mirrors
/// the website's overlay (server thread `messages/0009-impression-list/`): a small artwork
/// header, one row per member (most recently shown first, loaded page by page), and a fixed
/// note saying who is and is not listed.
///
/// Signed-in members only: the server answers 401 otherwise, so a signed-out visitor gets a
/// sign-in prompt and no request is made.
class DisplayedOnPage extends ConsumerWidget {
  final Post post;
  const DisplayedOnPage({super.key, required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.displayedOnTitle)),
      body: signedIn
          ? _MemberList(post: post)
          : SignInPrompt(
              message: l10n.displayedOnSignIn,
              onSignIn: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ClubAccountPage())),
            ),
    );
  }
}

class _MemberList extends ConsumerStatefulWidget {
  final Post post;
  const _MemberList({required this.post});

  @override
  ConsumerState<_MemberList> createState() => _MemberListState();
}

class _MemberListState extends ConsumerState<_MemberList> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _sc.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  // Also run after each build: a first page shorter than the screen never scrolls, so the
  // scroll listener alone would leave the rest of the list unreachable.
  void _maybeLoadMore() {
    if (!mounted || !_sc.hasClients) return;
    if (_sc.position.pixels > _sc.position.maxScrollExtent - 400) {
      ref.read(impressionUsersProvider(widget.post.id).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = impressionUsersProvider(widget.post.id);
    final s = ref.watch(provider);
    final n = ref.read(provider.notifier);
    if (s.error != null && s.items.isEmpty) {
      return ClubErrorRetry(message: s.error!, onRetry: n.refresh);
    }
    if (!s.initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!s.atEnd) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    return CenteredContent(
      child: RefreshIndicator(
        onRefresh: n.refresh,
        child: ListView(
          controller: _sc,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            ArtworkListHeader(post: widget.post),
            const Divider(height: 24),
            if (s.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: ClubEmpty(message: l10n.displayedOnEmpty, icon: Icons.tv_outlined),
              )
            else
              for (final m in s.items) _MemberRow(m: m),
            if (!s.atEnd)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))))
            else ...[
              const Divider(height: 24),
              // The fixed note (server decision L8): the rows never add up to the 📺 number,
              // and this says why instead of doing arithmetic against it.
              Text(l10n.displayedOnFooter,
                  style: const TextStyle(fontSize: 12, color: Colors.white38)),
            ],
          ],
        ),
      ),
    );
  }
}

/// One member: avatar · handle (tap → profile) · day last shown, and under the handle where it
/// was shown (player models, Web Player, app) and how many times.
class _MemberRow extends StatelessWidget {
  final ImpressionUser m;
  const _MemberRow({required this.m});

  /// "p3a, Pixel Jukebox, Web Player"; a member with no model, no Web Player and no app is a
  /// player that did not report its model, shown as a generic "Player".
  static String sources(ImpressionUser m) {
    final l10n = appL10n;
    final parts = [
      ...m.deviceModels,
      if (m.webPlayer) l10n.displayedOnWebPlayer,
      if (m.app) l10n.displayedOnApp,
    ];
    return parts.isEmpty ? l10n.displayedOnPlayer : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sqid = m.sqid;
    final open = sqid == null
        ? null
        : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(sqid: sqid)));
    return InkWell(
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: HandleAvatar(url: m.avatarUrl, handle: m.handle, radius: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    m.handle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                Text(shownDayLabel(m.lastShownOn),
                    style: const TextStyle(fontSize: 12, color: Colors.white38)),
              ]),
              const SizedBox(height: 2),
              // Wraps freely: several player models plus a long count phrase need two lines
              // on a narrow phone.
              Text(
                '${sources(m)} · ${l10n.displayedOnCount(m.count, compactCount(m.count))}',
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
