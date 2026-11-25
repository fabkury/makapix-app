import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../state/account_providers.dart';
import '../state/auth_controller.dart';
import '../state/feed_providers.dart';
import '../state/notifications_providers.dart';
import '../state/player_providers.dart';
import '../state/pulse_providers.dart';
import '../state/rules_gate.dart';
import '../state/super_post_provider.dart';
import 'about_dialog.dart';
import 'artist_dashboard_page.dart';
import 'artwork_detail_page.dart';
import 'auth/onboarding_wizard.dart';
import 'club_account_page.dart';
import 'club_resolving_page.dart';
import 'club_welcome_page.dart';
import 'contribute_page.dart';
import 'moderation_hub_page.dart';
import 'my_players_page.dart';
import 'notifications_page.dart';
import 'post_management_page.dart';
import 'profile_page.dart';
import 'pulse_view.dart';
import 'rules_gate_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'widgets/feed_filter.dart';
import 'widgets/feed_grid.dart';
import 'widgets/hashtag_bar.dart';
import 'widgets/send_target_binder.dart';

/// The social hub. Top bar (left → right): the Makapix Club menu · my profile · notifications,
/// then Contribute · Recommended · Recent · Pulse · Following · Search. The selected page fills
/// the body, and horizontal swipes move between them.
/// The glyph size of the top bar's icon buttons.
const double _navIconSize = 22;

/// The top bar's icon buttons, all one explicit size. Nine of them sit side by side (the menu
/// included), which is more than a phone fits at Material's 40 px: each gets a ninth of the bar
/// (less the bar's own spacing), capped at 40 — 38 px on a 360 px phone, 33 px on a 320 px one.
/// The size is set outright (no minimum, no padded tap target) so the row is exactly nine slots.
ButtonStyle _navIconStyle(BuildContext context) {
  final slot = ((MediaQuery.sizeOf(context).width - 16) / 9).floorToDouble().clamp(30.0, 40.0);
  return IconButton.styleFrom(
    fixedSize: Size(slot, 40),
    minimumSize: Size.zero,
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class ClubHomePage extends ConsumerStatefulWidget {
  const ClubHomePage({super.key});
  @override
  ConsumerState<ClubHomePage> createState() => _ClubHomePageState();
}

class _ClubHomePageState extends ConsumerState<ClubHomePage> {
  // Swipeable pages, left → right matching the top-bar order:
  // Contribute(0) · Recommended(1) · Recent(2) · Pulse(3) · Following(4) · Search(5).
  // Contribute, Pulse and Search are peers of the three artwork feeds.
  static const List<FeedKind?> _pageFeeds = [
    null, // Contribute
    FeedKind.promoted,
    FeedKind.recent,
    null, // Pulse
    FeedKind.following,
    null, // Search
  ];
  static const int _contributePage = 0;
  static const int _recentPage = 2;
  static const int _pulsePage = 3;
  static const int _searchPage = 5;
  int get _pageCount => _pageFeeds.length;

  // The home opens on Pulse once this install has seen the server answer for it, and on Recent
  // ("New artworks", like the website) until then — a server from before Pulse would only have
  // an empty page to land on. Decided from what the last session learned, never from a
  // request (ADR 0035). Set in initState, not lazily: a home that never shows its pages (signed
  // out) is still disposed, and a lazy read of the provider there would come too late.
  late final int _initialPage;
  late final PageController _pages;
  // Owned here (not by SearchView) so the top-bar Search icon can focus the query field.
  final FocusNode _searchFocus = FocusNode();
  // The active page. `_feed` derives from it: null on the Contribute, Pulse and Search pages.
  late int _page;
  FeedKind? get _feed => _pageFeeds[_page];

  // Coming back from the background counts as coming back to Pulse.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _initialPage = ref.read(pulseLandingProvider) ? _pulsePage : _recentPage;
    _page = _initialPage;
    _pages = PageController(initialPage: _initialPage);
    _lifecycle = AppLifecycleListener(onResume: () {
      if (mounted && _page == _pulsePage) refreshPulseIfStale(ref);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _pages.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // Keep the top-bar selection (`_page`) in sync with the PageView's real page.
  // When the view mounts *after* the onboarding wizard, the deferred first layout makes PageView
  // fire a spurious `onPageChanged(0)` (highlighting Contribute) while the controller actually
  // settles on `initialPage`. Re-assert `_page` from the controller's settled page after
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

  void _selectFeed(FeedKind kind) => _goToPage(_pageFeeds.indexOf(kind));

  void _openPost(FeedKind kind, Post p) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArtworkDetailPage(
            sqid: p.sqid,
            feed: pagedArtworkSource(
              feedProvider(kind),
              feedProvider(kind).notifier,
              name: switch (kind) {
                FeedKind.promoted => context.l10n.feedRecommended,
                FeedKind.recent => context.l10n.feedRecent,
                FeedKind.following => context.l10n.feedFollowing,
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

  // Back from a pushed page onto Pulse: refetch it if what it shows has grown old.
  Future<void> _push(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted && _page == _pulsePage) refreshPulseIfStale(ref);
  }

  // What "Send to Player" targets per feed. Recent/Recommended map to player channels; the
  // Following feed has no server channel, so sending is disabled there (until an artwork is opened).
  PlayerSendTarget? _channelFor(FeedKind kind) => switch (kind) {
        FeedKind.recent =>
          ChannelTarget(displayName: context.l10n.feedRecent, channelName: 'all'),
        FeedKind.promoted =>
          ChannelTarget(displayName: context.l10n.feedRecommended, channelName: 'promoted'),
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

  // A compact top-bar icon button (nine sit side by side, so they're tight).
  Widget _navIcon(IconData icon, String tip, VoidCallback onTap, {Color? color}) {
    return IconButton(
      icon: Icon(icon),
      iconSize: _navIconSize,
      color: color,
      tooltip: tip,
      style: _navIconStyle(context),
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
    final selected = _page == _contributePage;
    return _navIcon(selected ? Icons.brush : Icons.brush_outlined, context.l10n.contribute,
        () => _goToPage(_contributePage),
        color: selected ? cs.primary : null);
  }

  // The Pulse selector, between Recent and Following.
  Widget _pulseIcon(ColorScheme cs) {
    final selected = _page == _pulsePage;
    return _navIcon(selected ? kPulseIcon : kPulseIconOutlined, context.l10n.pulseTitle,
        () => _goToPage(_pulsePage),
        color: selected ? cs.primary : null);
  }

  // The Search selector: highlighted while the Search page (the last page) is active.
  Widget _searchIcon(ColorScheme cs) {
    final selected = _page == _searchPage;
    return _navIcon(Icons.search, context.l10n.search, _openSearch,
        color: selected ? cs.primary : null);
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) => PopupMenuItem<String>(
        value: value,
        // The label wraps rather than overflow the menu (long translations, large fonts).
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 10), Flexible(child: Text(label))]),
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
    // While the sign-in state resolves, a surface with the editor and the local library one tap
    // away — never a blocking spinner. Installs with a cached identity skip this state entirely
    // (they enter signed-in from the cache and revalidate behind the home; see AuthController).
    if (auth.status == AuthStatus.loading) {
      return const ClubResolvingPage();
    }
    // Match the website: signed-out users get a welcome/sign-in funnel, not the feeds.
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
    // before the feeds, unless they chose "Skip for now" this session. Not on a cached
    // (unrevalidated) identity: the wizard's steps all need the server, so it waits for the
    // revalidated `/auth/me` to say the flag still stands.
    if ((auth.me?.needsWelcome ?? false) && !auth.stale && !ref.watch(welcomeDismissedProvider)) {
      return const OnboardingWizard();
    }
    // Reaching the feed view (notably right after the wizard) — re-assert the
    // top-bar selection from the pager's real page once this frame lays out.
    _syncFeedToPager();
    final unread = ref.watch(unreadCountProvider);
    final mySqid = auth.me?.user.sub;
    final canModerate = ref.watch(isModeratorProvider);
    final cs = Theme.of(context).colorScheme;
    // Pulse is fetched as soon as the home shows, whichever page it opened on: that answer is
    // what lets the next launch open on Pulse (pulseLandingProvider).
    ref.listen(pulseProvider, (_, _) {});
    // Trending-hashtag strip below the top bar — the feed pages and Pulse (hidden on
    // Contribute and Search), and only once tags have loaded.
    final tags = ref.watch(topHashtagsProvider).valueOrNull ?? const <String>[];
    final showHashtags = (_feed != null || _page == _pulsePage) && tags.isNotEmpty;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 4,
        bottom: showHashtags ? HashtagBar(tags: tags) : null,
        // Left group: Makapix Club menu · my profile · notifications.
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          PopupMenuButton<String>(
            tooltip: 'Makapix Club', // l10n-ignore: brand name
            icon: const Icon(Icons.menu, size: _navIconSize),
            padding: EdgeInsets.zero,
            // Sized like its neighbors: at Material's 48 px minimum it pushes the row past the bar.
            style: _navIconStyle(context),
            onSelected: _onMenu,
            itemBuilder: (_) => [
              _menuItem('account', Icons.account_circle_outlined, l10n.accountTitle),
              _menuItem('my-posts', Icons.grid_view_outlined, l10n.menuMyPosts),
              _menuItem('players', Icons.cast_outlined, l10n.myPlayers),
              _menuItem('dashboard', Icons.insights_outlined, l10n.menuArtistDashboard),
              if (canModerate)
                _menuItem('moderation', Icons.shield_outlined, l10n.menuModeration),
              _menuItem('settings', Icons.settings_outlined, l10n.settingsTitle),
              _menuItem('about', Icons.info_outline, l10n.menuAbout),
              const PopupMenuDivider(),
              _menuItem('signout', Icons.logout, l10n.commonSignOut),
            ],
          ),
          _navIcon(Icons.person_outline, l10n.myProfile,
              mySqid == null ? () {} : () => _push(ProfilePage(sqid: mySqid))),
          _NotifAction(unread: unread, onTap: () => _push(const NotificationsPage())),
        ]),
        // Right group: Contribute · Recommended · Recent · Pulse · Following · Search.
        actions: [
          _contributeIcon(cs),
          _feedIcon(Icons.diamond_outlined, Icons.diamond, l10n.feedRecommended, FeedKind.promoted, cs),
          _feedIcon(Icons.visibility_outlined, Icons.visibility, l10n.feedRecent, FeedKind.recent, cs),
          _pulseIcon(cs),
          _feedIcon(Icons.people_outline, Icons.people, l10n.feedFollowing, FeedKind.following, cs),
          _searchIcon(cs),
          const SizedBox(width: 4),
        ],
      ),
      // Swipe horizontally to move Contribute ↔ Recommended ↔ Recent ↔ Pulse ↔ Following ↔
      // Search; the top-bar buttons jump to a page and stay in sync via onPageChanged. The
      // Contribute, Pulse and Search pages have no player channel, so sending is disabled there.
      body: Column(children: [
        // Signed in from the cached identity and the server can't be reached: say so, and offer
        // one retry that revalidates the sign-in and refetches the feeds together.
        if (auth.isOfflineSignedIn) _OfflineStrip(onRetry: _retryOffline),
        Expanded(
          child: SendTargetBinder(
            target: _feed == null ? null : _channelFor(_feed!),
            child: PageView(
              controller: _pages,
              onPageChanged: (i) {
                setState(() => _page = i);
                if (i == _pulsePage) refreshPulseIfStale(ref);
              },
              children: [
                for (final (i, kind) in _pageFeeds.indexed)
                  if (kind != null)
                    _feedBody(kind)
                  else if (i == _contributePage)
                    const ContributePage()
                  else if (i == _pulsePage)
                    const PulseView()
                  else
                    SearchView(searchFocus: _searchFocus),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _retryOffline() async {
    // Feeds first (they refetch on rebuild), then the identity — the strip stays until the
    // revalidation lands, so a retry that fails again reads as exactly that.
    for (final kind in FeedKind.values) {
      ref.invalidate(feedProvider(kind));
    }
    ref.invalidate(pulseProvider);
    ref.invalidate(topHashtagsProvider);
    await ref.read(authControllerProvider.notifier).reloadMe();
  }
}

/// The thin "showing your saved sign-in" strip under the top bar while the server is unreachable.
class _OfflineStrip extends StatefulWidget {
  final Future<void> Function() onRetry;
  const _OfflineStrip({required this.onRetry});

  @override
  State<_OfflineStrip> createState() => _OfflineStripState();
}

class _OfflineStripState extends State<_OfflineStrip> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        child: Row(children: [
          Icon(Icons.cloud_off, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(context.l10n.homeOffline,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(onPressed: _retry, child: Text(context.l10n.commonRetry)),
        ]),
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
        iconSize: _navIconSize,
        tooltip: context.l10n.notifications,
        style: _navIconStyle(context),
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
