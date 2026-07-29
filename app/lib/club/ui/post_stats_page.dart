import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/post.dart';
import '../models/post_stats.dart';
import '../state/stats_providers.dart';
import 'widgets/common.dart';

/// Per-post statistics (`GET /post/{id}/stats`), the website StatsPanel's
/// equivalent: summary cards, the 30-day daily-views trend, and country /
/// device / view-type / emoji breakdowns, with the same authenticated-only
/// toggle as the Artist Dashboard. Owner-only entry (server also allows mods).
class PostStatsPage extends ConsumerStatefulWidget {
  final Post post;
  const PostStatsPage({super.key, required this.post});

  @override
  ConsumerState<PostStatsPage> createState() => _PostStatsPageState();
}

class _PostStatsPageState extends ConsumerState<PostStatsPage> {
  bool _authOnly = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(postStatsProvider(widget.post.id));
    final ctrl = ref.read(postStatsProvider(widget.post.id).notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recompute now',
            onPressed: () => ctrl.load(refresh: true),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ClubErrorRetry(
          message: e is ClubError ? e.message : 'Could not load the statistics.',
          onRetry: ctrl.load,
        ),
        data: (s) => CenteredContent(child: _body(s)),
      ),
    );
  }

  Widget _body(PostStats s) {
    final daily = s.daily(_authOnly);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(widget.post.title.isEmpty ? 'Untitled' : widget.post.title,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _authOnly,
          onChanged: (v) => setState(() => _authOnly = v),
          title: const Text('Authenticated users only'),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _stat('Views', s.views(_authOnly)),
          _stat('Unique (7d)', s.uniques(_authOnly)),
          _stat('Reactions', s.reactions(_authOnly)),
          _stat('Comments', s.comments(_authOnly)),
        ]),
        if (daily.isNotEmpty) _dailyChart(daily),
        _breakdown('Views by country', s.countries(_authOnly)),
        _breakdown('Views by device', s.devices(_authOnly), label: _capitalize),
        _breakdown('Views by type', s.types(_authOnly), label: _capitalize),
        _breakdown('Reactions by emoji', s.emoji(_authOnly)),
        const SizedBox(height: 20),
        if (s.firstViewAt != null)
          _footerLine('First view', timeAgo(s.firstViewAt)),
        if (s.lastViewAt != null) _footerLine('Last view', timeAgo(s.lastViewAt)),
        if (s.computedAt != null) _footerLine('Computed', timeAgo(s.computedAt)),
        const SizedBox(height: 12),
      ],
    );
  }

  /// The last-30-days trend as a compact bar strip (weekends dimmed, like the
  /// website's chart). Bars scale to the visible maximum.
  Widget _dailyChart(List<DailyViews> daily) {
    final maxViews = daily.fold<int>(0, (m, d) => d.views > m ? d.views : m);
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('Daily views — last 30 days',
                  style: Theme.of(context).textTheme.titleSmall)),
          if (maxViews > 0)
            Text('max $maxViews',
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in daily) ...[
                Expanded(
                  child: Tooltip(
                    message: '${d.date}: ${d.views}',
                    child: FractionallySizedBox(
                      heightFactor:
                          maxViews == 0 ? 0 : (d.views / maxViews).clamp(0.0, 1.0),
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _isWeekend(d.date)
                              ? primary.withValues(alpha: 0.45)
                              : primary,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (daily.length > 1)
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(daily.first.date, style: const TextStyle(fontSize: 10, color: Colors.white38)),
            Text(daily.last.date, style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ]),
      ]),
    );
  }

  static bool _isWeekend(String isoDate) {
    final d = DateTime.tryParse(isoDate);
    return d != null && d.weekday >= DateTime.saturday;
  }

  Widget _stat(String label, int value) => Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1E22),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text(_fmt(value), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
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

  Widget _footerLine(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          SizedBox(
              width: 90,
              child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white38))),
          Text(value, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ]),
      );

  static String _capitalize(String key) =>
      key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

  static String _fmt(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}
