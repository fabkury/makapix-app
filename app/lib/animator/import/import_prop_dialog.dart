// The Whole/Parts card (design 02: the import-time choice that doubles as the discovery of
// "layers become limbs"). Shown ONLY for multi-layer .mkpx imports; single-layer files and
// rasters import silently. Previews are injected as ready ui.Images (the page renders them
// via a short-lived editor Engine — the DrawingLibraryGrid pattern), so this widget stays
// engine-free and widget-testable. Pops true = split into parts, false = whole, null = cancel.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Parsed `mkps_probe_import` JSON (tolerant; engine-free for tests).
class ImportProbe {
  final String kind; // 'mkpx' | 'raster' | 'error'
  final String? error;
  final int w, h, frames;
  final List<String> layerNames;
  const ImportProbe({
    required this.kind,
    this.error,
    this.w = 0,
    this.h = 0,
    this.frames = 1,
    this.layerNames = const [],
  });

  bool get isError => kind == 'error';
  bool get offersSplit => kind == 'mkpx' && layerNames.length > 1;

  static ImportProbe parse(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      if (m['error'] != null) {
        return ImportProbe(kind: 'error', error: m['error'] as String);
      }
      return ImportProbe(
        kind: m['kind'] as String? ?? 'raster',
        w: (m['w'] as num?)?.toInt() ?? 0,
        h: (m['h'] as num?)?.toInt() ?? 0,
        frames: (m['frames'] as num?)?.toInt() ?? 1,
        layerNames: [
          for (final l in (m['layers'] as List? ?? const []))
            (l as Map)['name'] as String? ?? '',
        ],
      );
    } catch (_) {
      return const ImportProbe(kind: 'error', error: 'unsupported');
    }
  }
}

class ImportPropDialog extends StatelessWidget {
  final ImportProbe probe;

  /// Composite preview of the whole drawing (frame 0), if available.
  final ui.Image? wholePreview;

  /// Per-layer previews aligned with [ImportProbe.layerNames], entries may be null.
  final List<ui.Image?> partPreviews;

  const ImportPropDialog({
    super.key,
    required this.probe,
    this.wholePreview,
    this.partPreviews = const [],
  });

  Widget _thumbBox(ui.Image? img, {double size = 56}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF101214),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black26),
        ),
        padding: const EdgeInsets.all(3),
        child: img != null
            ? RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.none)
            : const Icon(Icons.image_outlined, size: 20, color: Colors.white24),
      );

  Widget _option(BuildContext context,
      {required String title,
      required String subtitle,
      required Widget preview,
      required bool value}) {
    return Material(
      color: const Color(0xFF1A1C1F),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(context, value),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2D31)),
          ),
          child: Row(children: [
            preview,
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.white54, height: 1.3)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.white30),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parts = probe.layerNames.length;
    return AlertDialog(
      title: const Text('Import drawing'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'This drawing has $parts layers.',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          _option(
            context,
            title: 'Whole drawing',
            subtitle: 'One prop — the layers stay flattened together.',
            preview: _thumbBox(wholePreview),
            value: false,
          ),
          const SizedBox(height: 10),
          _option(
            context,
            title: 'Separate parts',
            subtitle:
                'One prop per layer — the parts arrive assembled and each moves on its own.',
            preview: SizedBox(
              width: 56,
              height: 56,
              child: GridView.count(
                crossAxisCount: 2,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                children: [
                  for (var i = 0; i < parts && i < 4; i++)
                    _thumbBox(i < partPreviews.length ? partPreviews[i] : null, size: 26),
                ],
              ),
            ),
            value: true,
          ),
          const SizedBox(height: 6),
          if (parts > 0)
            Text(
              probe.layerNames.take(6).join(' · ') + (parts > 6 ? ' …' : ''),
              style: const TextStyle(fontSize: 11, color: Colors.white38),
              overflow: TextOverflow.ellipsis,
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
