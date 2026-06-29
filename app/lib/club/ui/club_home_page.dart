import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../state/auth_controller.dart';
import '../state/edit_bridge.dart';
import '../state/feed_providers.dart';
import '../state/notifications_providers.dart';
import '../state/player_providers.dart';
import 'artist_dashboard_page.dart';
import 'artwork_detail_page.dart';
import 'club_account_page.dart';
import 'club_welcome_page.dart';
import 'notifications_page.dart';
import 'post_management_page.dart';
import 'profile_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'widgets/feed_grid.dart';
import 'widgets/send_target_binder.dart';

/// The social hub. Top bar (left → right): the Makapix Club menu · my profile · notifications,
/// then Contribute (opens the editor) · Recommended · Recent · Following · Search. The selected
/// feed fills the body.
class ClubHomePage extends ConsumerStatefulWidget {
  const ClubHomePage({super.key});
  @override
  ConsumerState<ClubHomePage> createState() => _ClubHomePageState();
}

class _ClubHomePageState extends ConsumerState<ClubHomePage> {
  // Swipeable feed pages, left → right matching the top-bar order. The body lands on Recent
  // ("New artworks", like the website), which sits in the middle so a swipe either way reaches
  // a neighbouring feed.
  static const List<FeedKind> _feeds = [FeedKind.promoted, FeedKind.recent, FeedKind.following];
  static const int _initialPage = 1; // FeedKind.recent

  late final PageController _pages = PageController(initialPage: _initialPage);
  FeedKind _feed = _feeds[_initialPage];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  // Jump to a feed by its top-bar button (animated; keeps the swipe pager in sync).
  void _selectFeed(FeedKind kind) {
    final i = _feeds.indexOf(kind);
    if (i < 0 || i == _feeds.indexOf(_feed)) return;
    _pages.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _openPost(Post p) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArtworkDetailPage(
            sqid: p.sqid,
            feed: pagedArtworkSource(feedProvider(_feed), feedProvider(_feed).notifier),
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
    return FeedGrid(state: state, onLoadMore: n.loadMore, onRefresh: n.refresh, onTap: _openPost);
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
    if (!auth.isSignedIn) {
      return const ClubWelcomePage();
    }
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
          _navIcon(Icons.add_circle_outline, 'Contribute (open the editor)',
              () => ref.read(openEditorProvider.notifier).state++),
          _feedIcon(Icons.diamond_outlined, Icons.diamond, 'Recommended', FeedKind.promoted, cs),
          _feedIcon(Icons.visibility_outlined, Icons.visibility, 'Recent', FeedKind.recent, cs),
          _feedIcon(Icons.people_outline, Icons.people, 'Following', FeedKind.following, cs),
          _navIcon(Icons.search, 'Search', () => _push(const SearchPage())),
          const SizedBox(width: 4),
        ],
      ),
      // Swipe horizontally to move Recommended ↔ Recent ↔ Following; the top-bar buttons jump
      // to a page and stay in sync via onPageChanged.
      body: SendTargetBinder(
        target: _channelFor(_feed),
        child: PageView(
          controller: _pages,
          onPageChanged: (i) => setState(() => _feed = _feeds[i]),
          children: [for (final kind in _feeds) _feedBody(kind)],
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
