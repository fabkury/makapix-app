import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../state/account_providers.dart';
import '../state/auth_controller.dart';
import '../state/feed_providers.dart';
import '../state/notifications_providers.dart';
import '../state/player_providers.dart';
import '../state/rules_gate.dart';
import '../state/super_post_provider.dart';
import 'artist_dashboard_page.dart';
import 'artwork_detail_page.dart';
import 'auth/onboarding_wizard.dart';
import 'club_account_page.dart';
import 'club_welcome_page.dart';
import 'contribute_page.dart';
import 'notifications_page.dart';
import 'post_management_page.dart';
import 'profile_page.dart';
import 'rules_gate_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'widgets/feed_grid.dart';
import 'widgets/send_target_binder.dart';

/// The social hub. Top bar (left → right): the Makapix Club menu · my profile · notifications,
/// then Contribute · Recommended · Recent · Following · Search. The selected page (Contribute or a
/// feed) fills the body, and horizontal swipes move between them.
class ClubHomePage extends ConsumerStatefulWidget {
  const ClubHomePage({super.key});
  @override
  ConsumerState<ClubHomePage> createState() => _ClubHomePageState();
}

class _ClubHomePageState extends ConsumerState<ClubHomePage> {
  // Swipeable pages, left → right matching the top-bar order. Page 0 is Contribute (a peer to the
  // feeds); the feeds follow. The body lands on Recent ("New artworks", like the website), so a
  // swipe reaches Recommended → Contribute one way and Following the other.
  static const List<FeedKind> _feeds = [FeedKind.promoted, FeedKind.recent, FeedKind.following];
  // PageView layout: Contribute(0) · Recommended(1) · Recent(2) · Following(3). Feed i is at page i+1.
  static const int _initialPage = 2; // FeedKind.recent
  int get _pageCount => _feeds.length + 1;

  late final PageController _pages = PageController(initialPage: _initialPage);
  // The active page's feed, or null while the Contribute page (page 0) is showing.
  FeedKind? _feed = _feedForPage(_initialPage);

  // Page ⇄ feed mapping: page 0 is Contribute (no feed); page p≥1 is `_feeds[p-1]`.
  static FeedKind? _feedForPage(int page) =>
      page <= 0 ? null : _feeds[(page - 1).clamp(0, _feeds.length - 1)];
  int get _currentPage => _feed == null ? 0 : _feeds.indexOf(_feed!) + 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  // Keep the top-bar selection (`_feed`) in sync with the PageView's real page.
  // When the view mounts *after* the onboarding wizard, the deferred first layout makes PageView
  // fire a spurious `onPageChanged(0)` (highlighting Contribute) while the controller actually
  // settles on `initialPage` (Recent). Re-assert `_feed` from the controller's settled page after
  // the frame; only act on a settled (near-integer) page so an in-progress swipe isn't disturbed.
  void _syncFeedToPager() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pages.hasClients) return;
      final page = _pages.page;
      if (page == null || (page - page.roundToDouble()).abs() > 0.01) return;
      final kind = _feedForPage(page.round().clamp(0, _pageCount - 1));
      if (kind != _feed) setState(() => _feed = kind);
    });
  }

  // Jump to a page by its top-bar button (animated; keeps the swipe pager in sync).
  void _goToPage(int page) {
    if (page == _currentPage) return;
    _pages.animateToPage(page, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _selectFeed(FeedKind kind) => _goToPage(_feeds.indexOf(kind) + 1);

  void _openPost(FeedKind kind, Post p) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArtworkDetailPage(
            sqid: p.sqid,
            feed: pagedArtworkSource(
              feedProvider(kind),
              feedProvider(kind).notifier,
              name: switch (kind) {
                FeedKind.promoted => 'Recommended',
                FeedKind.recent => 'Recent',
                FeedKind.following => 'Following',
              },
              icon: switch (kind) {
                FeedKind.promoted => Icons.diamond,
                FeedKind.recent => Icons.visibility,
                FeedKind.following => null,
              },
            ),
          ),
        ),
      );

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  // What "Send to Player" targets per feed. Recent/Recommended map to player channels; the
  // Following feed has no server channel, so sending is disabled there (until an artwork is opened).
  PlayerSendTarget? _channelFor(FeedKind kind) => switch (kind) {
        FeedKind.recent => const ChannelTarget(displayName: 'Recent', channelName: 'all'),
        FeedKind.promoted =>
          const ChannelTarget(displayName: 'Recommended', channelName: 'promoted'),
        FeedKind.following => null,
      };

  Widget _feedBody(FeedKind kind) {
    final state = ref.watch(feedProvider(kind));
    final n = ref.read(feedProvider(kind).notifier);
    return FeedGrid(
        state: state,
        onLoadMore: n.loadMore,
        onRefresh: n.refresh,
        superPostId: ref.watch(superPostIdProvider(kind)),
        onTap: (p) => _openPost(kind, p));
  }

  // A compact top-bar icon button (8 sit side-by-side, so they're tight).
  Widget _navIcon(IconData icon, String tip, VoidCallback onTap, {Color? color}) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 22,
      color: color,
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      constraints: const BoxConstraints(),
      onPressed: onTap,
    );
  }

  // A feed selector: tinted + filled-icon when its feed is the active one.
  Widget _feedIcon(IconData icon, IconData selectedIcon, String tip, FeedKind kind, ColorScheme cs) {
    final selected = _feed == kind;
    return _navIcon(selected ? selectedIcon : icon, tip, () => _selectFeed(kind),
        color: selected ? cs.primary : null);
  }

  // The Contribute selector: like a feed icon, but its "feed" is the Contribute page (page 0),
  // so it's highlighted whenever no feed is active.
  Widget _contributeIcon(ColorScheme cs) {
    final selected = _feed == null;
    return _navIcon(selected ? Icons.add_circle : Icons.add_circle_outline, 'Contribute',
        () => _goToPage(0),
        color: selected ? cs.primary : null);
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) => PopupMenuItem<String>(
        value: value,
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)]),
      );

  void _onMenu(String value) {
    switch (value) {
      case 'account':
        _push(const ClubAccountPage());
        break;
      case 'my-posts':
        _push(const PostManagementPage());
        break;
      case 'dashboard':
        final sqid = ref.read(authControllerProvider).me?.user.sub ?? '';
        if (sqid.isNotEmpty) _push(ArtistDashboardPage(userKey: sqid));
        break;
      case 'settings':
        _push(const SettingsPage());
        break;
      case 'about':
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Makapix Club'),
            content: const Text('A native client for the Makapix Club pixel-art social network.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
          ),
        );
        break;
      case 'signout':
        ref.read(authControllerProvider.notifier).logout();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    // Match the website: signed-out users get a welcome/sign-in funnel, not the feeds.
    if (auth.status == AuthStatus.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // First-run community-rules gate — covers signed-in and signed-out users
    // (ugc-safety A1). Reactive: interposes once config resolves with the
    // `moderation` key; otherwise a no-op.
    if (ref.watch(rulesGateProvider) == RulesGate.show) {
      return const RulesGatePage();
    }
    if (!auth.isSignedIn) {
      return const ClubWelcomePage();
    }
    // New accounts (and any not-yet-welcomed sign-in) get the onboarding wizard
    // before the feeds, unless they chose "Skip for now" this session.
    if ((auth.me?.needsWelcome ?? false) && !ref.watch(welcomeDismissedProvider)) {
      return const OnboardingWizard();
    }
    // Reaching the feed view (notably right after the wizard) — re-assert the
    // top-bar selection from the pager's real page once this frame lays out.
    _syncFeedToPager();
    final unread = ref.watch(unreadCountProvider);
    final mySqid = auth.me?.user.sub;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 4,
        // Left group: Makapix Club menu · my profile · notifications.
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          PopupMenuButton<String>(
            tooltip: 'Makapix Club',
            icon: const Icon(Icons.menu, size: 22),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onSelected: _onMenu,
            itemBuilder: (_) => [
              _menuItem('account', Icons.account_circle_outlined, 'Account'),
              _menuItem('my-posts', Icons.grid_view_outlined, 'My Posts'),
              _menuItem('dashboard', Icons.insights_outlined, 'Artist Dashboard'),
              _menuItem('settings', Icons.settings_outlined, 'Settings'),
              _menuItem('about', Icons.info_outline, 'About Makapix Club'),
              const PopupMenuDivider(),
              _menuItem('signout', Icons.logout, 'Sign out'),
            ],
          ),
          _navIcon(Icons.person_outline, 'My profile',
              mySqid == null ? () {} : () => _push(ProfilePage(sqid: mySqid))),
          _NotifAction(unread: unread, onTap: () => _push(const NotificationsPage())),
        ]),
        // Right group: Contribute · Recommended · Recent · Following · Search.
        actions: [
          _contributeIcon(cs),
          _feedIcon(Icons.diamond_outlined, Icons.diamond, 'Recommended', FeedKind.promoted, cs),
          _feedIcon(Icons.visibility_outlined, Icons.visibility, 'Recent', FeedKind.recent, cs),
          _feedIcon(Icons.people_outline, Icons.people, 'Following', FeedKind.following, cs),
          _navIcon(Icons.search, 'Search', () => _push(const SearchPage())),
          const SizedBox(width: 4),
        ],
      ),
      // Swipe horizontally to move Contribute ↔ Recommended ↔ Recent ↔ Following; the top-bar
      // buttons jump to a page and stay in sync via onPageChanged. The Contribute page has no
      // player channel, so sending is disabled there.
      body: SendTargetBinder(
        target: _feed == null ? null : _channelFor(_feed!),
        child: PageView(
          controller: _pages,
          onPageChanged: (i) => setState(() => _feed = _feedForPage(i)),
          children: [
            const ContributePage(),
            for (final kind in _feeds) _feedBody(kind),
          ],
        ),
      ),
    );
  }
}

class _NotifAction extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;
  const _NotifAction({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      IconButton(
        icon: const Icon(Icons.notifications_none),
        iconSize: 22,
        tooltip: 'Notifications',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        constraints: const BoxConstraints(),
        onPressed: onTap,
      ),
      if (unread > 0)
        Positioned(
          top: 2,
          right: 0,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
              constraints: const BoxConstraints(minWidth: 15),
              child: Text(unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
    ]);
  }
}
