import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/artist_stats.dart';
import '../models/club_error.dart';
import '../state/stats_providers.dart';
import 'artwork_detail_page.dart';
import 'widgets/common.dart';

/// Artist dashboard (`SPEC-CLUB.md` §19, aggregate). Totals + breakdowns (country
/// / device / emoji) + a paged per-post table, with an authenticated-only toggle.
/// Mirrors the website's `/u/{sqid}/dashboard`. (The per-post `/post/{id}/stats`
/// drill-in is deferred.)
class ArtistDashboardPage extends ConsumerStatefulWidget {
  final String userKey; // public_sqid or UUID — the dashboard endpoint accepts either
  const ArtistDashboardPage({super.key, required this.userKey});
  @override
  ConsumerState<ArtistDashboardPage> createState() => _ArtistDashboardPageState();
}

class _ArtistDashboardPageState extends ConsumerState<ArtistDashboardPage> {
  bool _authOnly = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(artistDashboardProvider(widget.userKey));
    final ctrl = ref.read(artistDashboardProvider(widget.userKey).notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Artist Dashboard')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ClubErrorRetry(
          message: e is ClubError ? e.message : 'Could not load your dashboard.',
          onRetry: ctrl.load,
        ),
        data: (d) => CenteredContent(child: _body(d, ctrl)),
      ),
    );
  }

  Widget _body(ArtistDashboard d, ArtistDashboardController ctrl) {
    final s = d.stats;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SwitchListTile(
          value: _authOnly,
          onChanged: (v) => setState(() => _authOnly = v),
          title: const Text('Authenticated users only'),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _stat('Posts', s.totalPosts),
          _stat('Views', s.views(_authOnly)),
          _stat('Unique', s.uniques(_authOnly)),
          _stat('Reactions', s.reactions(_authOnly)),
          _stat('Comments', s.comments(_authOnly)),
        ]),
        _breakdown('Views by country', s.countries(_authOnly)),
        _breakdown('Views by device', s.devices(_authOnly), label: _deviceLabel),
        _breakdown('Reactions by emoji', s.emoji(_authOnly)),
        const SizedBox(height: 16),
        Text('Posts', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (d.posts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: ClubEmpty(message: 'No posts yet.'),
          )
        else ...[
          _postHeader(),
          for (final p in d.posts) _postRow(p),
        ],
        const SizedBox(height: 12),
        _pager(d, ctrl),
      ],
    );
  }

  Widget _stat(String label, int value) => Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1E22),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text(_fmt(value),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      );

  Widget _breakdown(String title, Map<String, int> data, {String Function(String)? label}) {
    if (data.isEmpty) return const SizedBox.shrink();
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(label?.call(e.key) ?? e.key)),
              Text(_fmt(e.value), style: const TextStyle(color: Colors.white70)),
            ]),
          ),
      ]),
    );
  }

  Widget _postHeader() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text('Title', style: TextStyle(color: Colors.white54, fontSize: 12))),
          _MetricHead('Views'),
          _MetricHead('React'),
          _MetricHead('Comm'),
        ]),
      );

  Widget _postRow(PostStatsListItem p) => InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: p.sqid)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title.isEmpty ? '(untitled)' : p.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(timeAgo(p.createdAt),
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
            ),
            _metric(p.views(_authOnly)),
            _metric(p.reactions(_authOnly)),
            _metric(p.comments(_authOnly)),
          ]),
        ),
      );

  Widget _metric(int v) =>
      SizedBox(width: 56, child: Text(_fmt(v), textAlign: TextAlign.end));

  Widget _pager(ArtistDashboard d, ArtistDashboardController ctrl) {
    if (d.page <= 1 && !d.hasMore) return const SizedBox.shrink();
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      TextButton(
        onPressed: d.page > 1 ? () => ctrl.goToPage(d.page - 1) : null,
        child: const Text('Previous'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('Page ${d.page}', style: const TextStyle(color: Colors.white60)),
      ),
      TextButton(
        onPressed: d.hasMore ? () => ctrl.goToPage(d.page + 1) : null,
        child: const Text('Next'),
      ),
    ]);
  }

  static String _deviceLabel(String key) =>
      key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

  static String _fmt(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

class _MetricHead extends StatelessWidget {
  final String label;
  const _MetricHead(this.label);
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 56,
        child: Text(label,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      );
}
