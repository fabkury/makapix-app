import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../state/auth_controller.dart';
import '../state/feed_providers.dart';
import '../state/notifications_providers.dart';
import 'artwork_detail_page.dart';
import 'club_account_page.dart';
import 'club_welcome_page.dart';
import 'notifications_page.dart';
import 'search_page.dart';
import 'widgets/feed_grid.dart';

/// The social hub: tabbed feeds (Recent / Recommended / Following) plus search,
/// notifications, and account. Entry point from the editor.
class ClubHomePage extends ConsumerStatefulWidget {
  const ClubHomePage({super.key});
  @override
  ConsumerState<ClubHomePage> createState() => _ClubHomePageState();
}

class _ClubHomePageState extends ConsumerState<ClubHomePage> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _openPost(Post p) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: p.sqid)));

  Widget _feed(FeedKind kind) {
    final state = ref.watch(feedProvider(kind));
    final n = ref.read(feedProvider(kind).notifier);
    return FeedGrid(state: state, onLoadMore: n.loadMore, onRefresh: n.refresh, onTap: _openPost);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Makapix Club'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
          _NotifAction(
            unread: unread,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Account',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubAccountPage())),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Recent'), Tab(text: 'Recommended'), Tab(text: 'Following')],
        ),
      ),
      body: TabBarView(controller: _tab, children: [
        _feed(FeedKind.recent),
        _feed(FeedKind.promoted),
        _feed(FeedKind.following),
      ]),
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
      IconButton(icon: const Icon(Icons.notifications_none), tooltip: 'Notifications', onPressed: onTap),
      if (unread > 0)
        Positioned(
          top: 8,
          right: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
            constraints: const BoxConstraints(minWidth: 16),
            child: Text(unread > 99 ? '99+' : '$unread',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        ),
    ]);
  }
}
