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
import 'about_dialog.dart';
import 'artist_dashboard_page.dart';
import 'artwork_detail_page.dart';
import 'auth/onboarding_wizard.dart';
import 'club_account_page.dart';
import 'club_welcome_page.dart';
import 'contribute_page.dart';
import 'moderation_hub_page.dart';
import 'my_players_page.dart';
import 'notifications_page.dart';
import 'post_management_page.dart';
import 'profile_page.dart';
import 'rules_gate_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'widgets/feed_filter.dart';
import 'widgets/feed_grid.dart';
import 'widgets/hashtag_bar.dart';
import 'widgets/send_target_binder.dart';

/// The social hub. Top bar (left → right): the Makapix Club menu · my profile · notifications,
/// then Contribute · Recommended · Recent · Following · Search. The selected page (Contribute, a
/// feed, or Search) fills the body, and horizontal swipes move between them.
class ClubHomePage extends ConsumerStatefulWidget {
  const ClubHomePage({super.key});
  @override
  ConsumerState<ClubHomePage> createState() => _ClubHomePageState();
}

class _ClubHomePageState extends ConsumerState<ClubHomePage> {
  // Swipeable pages, left → right matching the top-bar order. Page 0 is Contribute and the last
  // page is Search (both peers to the feeds); the feeds sit between. The body lands on Recent
  // ("New artworks", like the website), so a swipe reaches Recommended → Contribute one way and
  // Following → Search the other.
  static const List<FeedKind> _feeds = [FeedKind.promoted, FeedKind.recent, FeedKind.following];
  // PageView layout: Contribute(0) · Recommended(1) · Recent(2) · Following(3) · Search(4).
  // Feed i is at page i+1.
  static const int _initialPage = 2; // FeedKind.recent
  int get _searchPage => _feeds.length + 1;
  int get _pageCount => _feeds.length + 2;

  late final PageController _pages = PageController(initialPage: _initialPage);
  // Owned here (not by SearchView) so the top-bar Search icon can focus the query field.
  final FocusNode _searchFocus = FocusNode();
  // The active page. `_feed` derives from it: null on the Contribute and Search pages.
  int _page = _initialPage;
  FeedKind? get _feed => _page >= 1 && _page <= _feeds.length ? _feeds[_page - 1] : null;

  @override
  void dispose() {
    _pages.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // Keep the top-bar selection (`_page`) in sync with the PageView's real page.
  // When the view mounts *after* the onboarding wizard, the deferred first layout makes PageView
  // fire a spurious `onPageChanged(0)` (highlighting Contribute) while the controller actually
  // settles on `initialPage` (Recent). Re-assert `_page` from the controller's settled page after
  // the frame; only act on a settled (near-integer) page so an in-progress swipe isn't disturbed.
  void _syncFeedToPager() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pages.hasClients) return;
      final page = _pages.page;
      if (page == null || (page - page.roundToDouble()).abs() > 0.01) return;
      final p = page.round().clamp(0, _pageCount - 1);
      if (p != _page) setState(() => _page = p);
    });
  }

  // Jump to a page by its top-bar button (animated; keeps the swipe pager in sync).
  Future<void> _goToPage(int page) async {
    if (page == _page) return;
    await _pages.animateToPage(page,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  // The Search icon lands on the Search page AND pops the keyboard (focus after the page settles,
  // so the field is guaranteed to be built). Swipe arrivals deliberately don't focus.
  Future<void> _openSearch() async {
    await _goToPage(_searchPage);
    if (mounted) _searchFocus.requestFocus();
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
    final grid = FeedGrid(
        state: state,
        onLoadMore: n.loadMore,
        onRefresh: () async {
          // A pull-to-refresh also re-rolls the trending hashtag strip.
          ref.invalidate(topHashtagsProvider);
          await n.refresh();
        },
        superPostId: ref.watch(superPostIdProvider(kind)),
        onTap: (p) => _openPost(kind, p));
    // Only Recent is filterable (website parity: no FilterButton on the
    // Recommended page; the following-feed endpoint takes no filters).
    if (kind != FeedKind.recent) return grid;
    return FilterFabOverlay(filterKey: 'recent', child: grid);
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

  // The Contribute selector: like a feed icon, but its "feed" is the Contribute page (page 0).
  Widget _contributeIcon(ColorScheme cs) {
    final selected = _page == 0;
    return _navIcon(selected ? Icons.brush : Icons.brush_outlined, 'Contribute',
        () => _goToPage(0),
        color: selected ? cs.primary : null);
  }

  // The Search selector: highlighted while the Search page (the last page) is active.
  Widget _searchIcon(ColorScheme cs) {
    final selected = _page == _searchPage;
    return _navIcon(Icons.search, 'Search', _openSearch, color: selected ? cs.primary : null);
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
      case 'players':
        _push(const MyPlayersPage());
        break;
      case 'dashboard':
        final sqid = ref.read(authControllerProvider).me?.user.sub ?? '';
        if (sqid.isNotEmpty) _push(ArtistDashboardPage(userKey: sqid));
        break;
      case 'moderation':
        _push(const ModerationHubPage());
        break;
      case 'settings':
        _push(const SettingsPage());
        break;
      case 'about':
        showMakapixAboutDialog(context);
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
    final canModerate = ref.watch(isModeratorProvider);
    final cs = Theme.of(context).colorScheme;
    // Trending-hashtag strip below the top bar — feed pages only (hidden on
    // Contribute, `_feed == null`), and only once tags have loaded.
    final tags = ref.watch(topHashtagsProvider).valueOrNull ?? const <String>[];
    final showHashtags = _feed != null && tags.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 4,
        bottom: showHashtags ? HashtagBar(tags: tags) : null,
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
              _menuItem('players', Icons.cast_outlined, 'My Players'),
              _menuItem('dashboard', Icons.insights_outlined, 'Artist Dashboard'),
              if (canModerate) _menuItem('moderation', Icons.shield_outlined, 'Moderation'),
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
          _searchIcon(cs),
          const SizedBox(width: 4),
        ],
      ),
      // Swipe horizontally to move Contribute ↔ Recommended ↔ Recent ↔ Following ↔ Search; the
      // top-bar buttons jump to a page and stay in sync via onPageChanged. The Contribute and
      // Search pages have no player channel, so sending is disabled there.
      body: SendTargetBinder(
        target: _feed == null ? null : _channelFor(_feed!),
        child: PageView(
          controller: _pages,
          onPageChanged: (i) => setState(() => _page = i),
          children: [
            const ContributePage(),
            for (final kind in _feeds) _feedBody(kind),
            SearchView(searchFocus: _searchFocus),
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
