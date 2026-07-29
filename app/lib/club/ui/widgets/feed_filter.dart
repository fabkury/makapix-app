import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/feed_filters.dart';
import '../../state/feed_providers.dart';

/// Overlays a filterable feed with the filter/sort button (docs/club-gap A4 —
/// the website FilterButton's equivalent). [filterKey] is the feed identity
/// used by [feedFiltersProvider] (`'recent'` · `'tag:<tag>'` ·
/// `'owner:<user_key>'`). A badge dot marks non-default filters.
class FilterFabOverlay extends ConsumerWidget {
  final String filterKey;
  final Widget child;
  const FilterFabOverlay({super.key, required this.filterKey, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = !ref.watch(feedFiltersProvider(filterKey)).isDefault;
    return Stack(children: [
      child,
      Positioned(
        right: 12,
        bottom: 12,
        child: FloatingActionButton.small(
          heroTag: null, // several feeds can be alive in one route stack
          tooltip: 'Filter & sort',
          onPressed: () => showFeedFilterSheet(context, ref, filterKey),
          child: Badge(
            isLabelVisible: active,
            child: const Icon(Icons.tune),
          ),
        ),
      ),
    ]);
  }
}

/// Opens the draft-then-apply filter sheet; writes the result back into
/// [feedFiltersProvider] (which makes the watching feed refetch).
Future<void> showFeedFilterSheet(BuildContext context, WidgetRef ref, String filterKey) async {
  final current = ref.read(feedFiltersProvider(filterKey));
  final result = await showAppSheet<FeedFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(initial: current),
  );
  if (result != null) {
    ref.read(feedFiltersProvider(filterKey).notifier).state = result;
  }
}

class _FilterSheet extends StatefulWidget {
  final FeedFilters initial;
  const _FilterSheet({required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _sort = widget.initial.sort;
  late String _order = widget.initial.order;
  late int? _base = widget.initial.base;
  late Set<int> _sizes = {...widget.initial.sizes};
  late Set<String> _kinds = {...widget.initial.kinds};
  late RangeValues _bytesRange = RangeValues(
    _sliderFromBytes(widget.initial.fileBytesMin ?? 0),
    _sliderFromBytes(widget.initial.fileBytesMax ?? kFilterFileBytesCap),
  );

  // Exponential slider (power 4, like the website): fine resolution at the
  // small end where pixel-art files actually live.
  static double _sliderFromBytes(int bytes) =>
      math.pow((bytes.clamp(0, kFilterFileBytesCap)) / kFilterFileBytesCap, 1 / 4.0).toDouble();
  static int _bytesFromSlider(double t) =>
      (kFilterFileBytesCap * math.pow(t.clamp(0.0, 1.0), 4.0)).round();

  static String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
    return '${(bytes / 1024).toStringAsFixed(0)} KiB';
  }

  FeedFilters _build() {
    final min = _bytesFromSlider(_bytesRange.start);
    final max = _bytesFromSlider(_bytesRange.end);
    return FeedFilters(
      sort: _sort,
      order: _order,
      base: _base,
      sizes: _sizes,
      fileBytesMin: min > 0 ? min : null,
      fileBytesMax: max < kFilterFileBytesCap ? max : null,
      kinds: _kinds,
    );
  }

  void _clearAll() => setState(() {
        _sort = 'created_at';
        _order = 'desc';
        _base = null;
        _sizes = {};
        _kinds = {};
        _bytesRange = const RangeValues(0, 1);
      });

  Widget _section(String title, Widget body) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          body,
        ]),
      );

  Widget _chips<T>({
    required List<(T, String)> options,
    required bool Function(T) selected,
    required void Function(T) onTap,
    bool Function(T)? disabled,
  }) =>
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (v, label) in options)
          FilterChip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
            selected: selected(v),
            visualDensity: VisualDensity.compact,
            onSelected: (disabled?.call(v) ?? false) ? null : (_) => onTap(v),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final minBytes = _bytesFromSlider(_bytesRange.start);
    final maxBytes = _bytesFromSlider(_bytesRange.end);
    final dims = [
      for (final v in kFilterDimensionBadges) (v, v >= 128 ? '128+' : '$v'),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 4, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Filter & sort', style: Theme.of(context).textTheme.titleMedium),
          _section(
            'Sort by',
            _chips<String>(
              options: const [
                ('created_at', 'Creation date'),
                ('reactions', 'Reactions'),
                ('file_bytes', 'File size'),
              ],
              selected: (v) => _sort == v,
              onTap: (v) => setState(() => _sort = v),
            ),
          ),
          _section(
            'Order',
            _chips<String>(
              options: const [('desc', 'Descending'), ('asc', 'Ascending')],
              selected: (v) => _order == v,
              onTap: (v) => setState(() => _order = v),
            ),
          ),
          _section(
            'Base — smaller side',
            _chips<int>(
              options: dims,
              selected: (v) => _base == v,
              onTap: (v) => setState(() => _base = _base == v ? null : v),
            ),
          ),
          _section(
            'Size — larger side (up to $kFilterMaxSizeBadges)',
            _chips<int>(
              options: dims,
              selected: _sizes.contains,
              disabled: (v) => !_sizes.contains(v) && _sizes.length >= kFilterMaxSizeBadges,
              onTap: (v) => setState(
                  () => _sizes.contains(v) ? _sizes.remove(v) : _sizes.add(v)),
            ),
          ),
          _section(
            'File size',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_fmtBytes(minBytes)} – ${_fmtBytes(maxBytes)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
              RangeSlider(
                values: _bytesRange,
                onChanged: (v) => setState(() => _bytesRange = v),
              ),
            ]),
          ),
          _section(
            'Animation',
            _chips<String>(
              options: const [('static', 'Static'), ('animated', 'Animated')],
              selected: _kinds.contains,
              onTap: (v) => setState(
                  () => _kinds.contains(v) ? _kinds.remove(v) : _kinds.add(v)),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            TextButton(onPressed: _clearAll, child: const Text('Clear all')),
            const Spacer(),
            TextButton(
                onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, _build()),
              child: const Text('Apply'),
            ),
          ]),
        ]),
      ),
    );
  }
}
