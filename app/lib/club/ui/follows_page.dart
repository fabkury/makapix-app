import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../state/paged.dart';
import '../state/profile_providers.dart';
import 'profile_page.dart';
import 'widgets/common.dart';

/// A profile's follow graph: Followers and Following tabs, opened by tapping
/// the Followers stat on the profile page. Rows open the person's profile.
class FollowsPage extends StatelessWidget {
  final String sqid;
  final String handle;
  const FollowsPage({super.key, required this.sqid, required this.handle});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('@$handle'),
          bottom: const TabBar(tabs: [Tab(text: 'Followers'), Tab(text: 'Following')]),
        ),
        body: TabBarView(children: [
          _PeopleList(
            provider: followersProvider(sqid),
            emptyMessage: 'No followers yet.',
          ),
          _PeopleList(
            provider: followingProvider(sqid),
            emptyMessage: 'Not following anyone yet.',
          ),
        ]),
      ),
    );
  }
}

class _PeopleList extends ConsumerStatefulWidget {
  final AutoDisposeStateNotifierProvider<PagedNotifier<PostOwner>, PagedState<PostOwner>>
      provider;
  final String emptyMessage;
  const _PeopleList({required this.provider, required this.emptyMessage});

  @override
  ConsumerState<_PeopleList> createState() => _PeopleListState();
}

class _PeopleListState extends ConsumerState<_PeopleList>
    with AutomaticKeepAliveClientMixin {
  final _sc = ScrollController();

  @override
  bool get wantKeepAlive => true; // keep scroll/state across tab switches

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 400) {
        ref.read(widget.provider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = ref.watch(widget.provider);
    final n = ref.read(widget.provider.notifier);
    Widget body;
    if (s.error != null && s.items.isEmpty) {
      body = ClubErrorRetry(message: s.error!, onRetry: n.refresh);
    } else if (!s.initialized && s.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (s.items.isEmpty) {
      body = ClubEmpty(message: widget.emptyMessage, icon: Icons.people_outline);
    } else {
      body = RefreshIndicator(
        onRefresh: n.refresh,
        child: ListView.separated(
          controller: _sc,
          itemCount: s.items.length + (s.atEnd ? 0 : 1),
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            if (i >= s.items.length) {
              return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))));
            }
            return _row(s.items[i]);
          },
        ),
      );
    }
    return CenteredContent(child: body);
  }

  Widget _row(PostOwner u) => ListTile(
        leading: HandleAvatar(url: u.avatarUrl, handle: u.handle, radius: 18),
        title: Text('@${u.handle}'),
        subtitle: (u.tagline != null && u.tagline!.isNotEmpty)
            ? Text(u.tagline!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11))
            : null,
        trailing: u.reputation > 0
            ? Text('rep ${u.reputation}',
                style: const TextStyle(fontSize: 11, color: Colors.white38))
            : null,
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ProfilePage(sqid: u.sqid))),
      );
}
