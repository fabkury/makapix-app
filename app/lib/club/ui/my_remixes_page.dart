import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lineage.dart';
import '../state/lineage_providers.dart';
import 'artwork_detail_page.dart';
import 'widgets/common.dart';

/// The private "Remixes of my works" aggregate (`GET /me/remixes`, newest
/// first): every viewer-visible Remix of any of the signed-in user's posts,
/// each noting how many of their works it declares as Parents. Reached from
/// the account page; website parity with `/remixes`.
class MyRemixesPage extends ConsumerStatefulWidget {
  const MyRemixesPage({super.key});
  @override
  ConsumerState<MyRemixesPage> createState() => _MyRemixesPageState();
}

class _MyRemixesPageState extends ConsumerState<MyRemixesPage> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 400) {
        ref.read(myRemixesProvider.notifier).loadMore();
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
    final s = ref.watch(myRemixesProvider);
    final notifier = ref.read(myRemixesProvider.notifier);
    Widget body;
    if (!s.initialized && s.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (s.error != null && s.items.isEmpty) {
      body = ClubErrorRetry(message: s.error!, onRetry: notifier.refresh);
    } else if (s.items.isEmpty) {
      body = ListView(children: [
        SizedBox(
            height: 320,
            child: ClubEmpty(message: context.l10n.remixesEmpty, icon: Icons.alt_route)),
      ]);
    } else {
      body = ListView.builder(
        controller: _sc,
        itemCount: s.items.length + (s.atEnd ? 0 : 1),
        itemBuilder: (ctx, i) {
          if (i >= s.items.length) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                        height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))));
          }
          return _RemixRow(item: s.items[i]);
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.remixesOfMyWorks)),
      body: RefreshIndicator(onRefresh: notifier.refresh, child: body),
    );
  }
}

class _RemixRow extends StatelessWidget {
  final RemixReceivedItem item;
  const _RemixRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = item.post;
    final n = item.myParentSqids.length;
    return ListTile(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: p.sqid))),
      leading: SizedBox(
        width: 48,
        height: 48,
        child: Container(
          color: kArtworkBackdrop,
          child: PixelArtImage(url: p.artUrl, width: p.width, height: p.height),
        ),
      ),
      title: Text(p.title.isEmpty ? context.l10n.untitled : p.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        n > 1
            ? context.l10n.remixRowMany(p.owner.handle, n)
            : context.l10n.remixRowOne(p.owner.handle),
        style: const TextStyle(fontSize: 12, color: Colors.white54),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
    );
  }
}
