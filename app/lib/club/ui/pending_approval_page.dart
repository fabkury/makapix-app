import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/post.dart';
import '../state/api_providers.dart';
import '../state/moderation_providers.dart';
import 'artwork_detail_page.dart';
import 'widgets/common.dart';

/// The pending-approval queue (the website dashboard's default tab): artworks
/// from non-trusted users waiting for a moderator before they can appear in
/// Recent Artworks and search. Approve/Reject act in place; tapping a row
/// opens the full artwork page for closer inspection.
class PendingApprovalPage extends ConsumerStatefulWidget {
  const PendingApprovalPage({super.key});

  @override
  ConsumerState<PendingApprovalPage> createState() => _PendingApprovalPageState();
}

class _PendingApprovalPageState extends ConsumerState<PendingApprovalPage> {
  /// Posts approved/rejected this session — dropped from the display without
  /// refetching (the website removes them from the list the same way).
  final Set<int> _handled = {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pendingApprovalProvider);
    final notifier = ref.read(pendingApprovalProvider.notifier);
    final items = [for (final p in state.items) if (!_handled.contains(p.id)) p];

    final Widget body;
    if (!state.initialized && state.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.error != null && items.isEmpty) {
      body = ClubErrorRetry(message: state.error!, onRetry: notifier.refresh);
    } else if (items.isEmpty && state.atEnd) {
      body = ClubEmpty(message: context.l10n.pendingEmpty, icon: Icons.fact_check_outlined);
    } else {
      body = RefreshIndicator(
        onRefresh: () async {
          _handled.clear();
          await notifier.refresh();
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items.length + (state.atEnd ? 0 : 1),
          itemBuilder: (context, i) {
            if (i == items.length) {
              // Tail slot: the Load More affordance (also covers "everything
              // on this page was handled but the server has more").
              return Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton(
                  onPressed: state.loading ? null : notifier.loadMore,
                  child: Text(
                      state.loading ? context.l10n.commonLoading : context.l10n.commonLoadMore),
                ),
              );
            }
            return _row(items[i]);
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.pendingTitle)),
      body: body,
    );
  }

  Widget _row(Post p) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 56,
          height: 56,
          child: PixelArtImage(
              url: p.artUrl, frameCount: p.frameCount, width: p.width, height: p.height),
        ),
      ),
      title: Text(p.title.isEmpty ? context.l10n.untitled : p.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('@${p.owner.handle}  ·  ${timeAgo(p.createdAt)}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: p.sqid))),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
          tooltip: context.l10n.pendingApprove,
          onPressed: () => _decide(p, approve: true),
        ),
        IconButton(
          icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
          tooltip: context.l10n.pendingReject,
          onPressed: () => _decide(p, approve: false),
        ),
      ]),
    );
  }

  Future<void> _decide(Post p, {required bool approve}) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await ref.read(moderationApiProvider).setPublicVisibility(p.id, approve);
      setState(() => _handled.add(p.id));
      messenger.showSnackBar(SnackBar(
          content: Text(approve
              ? l10n.pendingApproved(p.title.isEmpty ? l10n.untitled : p.title)
              : l10n.pendingRejected)));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(approve ? l10n.modApproveFailed : l10n.pendingRejectFailed)));
    }
  }
}
