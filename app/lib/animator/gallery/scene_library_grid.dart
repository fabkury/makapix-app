// The Scene library grid — DrawingLibraryGrid's twin over SceneStore (host-agnostic: pure
// StatefulWidget + callbacks, no Riverpod, no navigation). Tiles decode `doc.mkps` through a
// short-lived SceneEngine and render frame 0 on the checkerboard; rename/delete flows match
// the drawing grid so both libraries feel identical.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:makapix_club/animator/model/scene_rules.dart';
import 'package:makapix_club/animator/persistence/scene_meta.dart';
import 'package:makapix_club/animator/persistence/scene_store.dart';
import 'package:makapix_club/editor/widgets/painters.dart' show CheckerPainter;
import 'package:makapix_club/engine_ffi.dart' show premultiplyRgbaInPlace;
import 'package:makapix_club/scene_ffi.dart';

class SceneLibraryGrid extends StatefulWidget {
  final SceneStore store;
  final void Function(String id) onOpen;
  final VoidCallback onNew;

  /// The scene currently open in the Animator (gets the badge; Delete suppressed).
  final String? currentId;

  const SceneLibraryGrid({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onNew,
    this.currentId,
  });

  @override
  State<SceneLibraryGrid> createState() => _SceneLibraryGridState();
}

class _SceneLibraryGridState extends State<SceneLibraryGrid> {
  List<SceneMeta>? _items;
  final Map<String, ui.Image> _thumbs = {};
  final Set<String> _inFlight = {};
  static const int _thumbCap = 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final img in _thumbs.values) {
      img.dispose();
    }
    _thumbs.clear();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await widget.store.list();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _ensureThumb(SceneMeta m) async {
    if (_thumbs.containsKey(m.id) || _inFlight.contains(m.id)) return;
    _inFlight.add(m.id);
    try {
      final bytes = await widget.store.readDoc(m.id);
      if (bytes == null) return;
      // A short-lived session per decode (the DrawingLibraryGrid pattern): load, composite
      // frame 0, convert synchronously (the scratch-buffer contract), dispose before awaits.
      final eng = SceneEngine.forLoad();
      ui.Image? img;
      try {
        if (eng.load(bytes)) {
          final w = eng.width, h = eng.height;
          final rgba = eng.compositeFrame(0);
          if (rgba.isNotEmpty) {
            premultiplyRgbaInPlace(rgba);
            img = await _decodeRgba(rgba, w, h);
          }
        }
      } finally {
        eng.dispose();
      }
      if (img == null) return;
      if (!mounted) {
        img.dispose();
        return;
      }
      // FIFO cap eviction, matching the drawing grid.
      if (_thumbs.length >= _thumbCap) {
        final victim = _thumbs.keys.first;
        _thumbs.remove(victim)?.dispose();
      }
      setState(() => _thumbs[m.id] = img!);
    } finally {
      _inFlight.remove(m.id);
    }
  }

  static Future<ui.Image> _decodeRgba(Uint8List rgba, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  Future<void> _rename(SceneMeta m) async {
    final ctrl = TextEditingController(text: m.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename scene'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (s) => Navigator.pop(ctx, s.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Rename')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await widget.store.writeMeta(m.copyWith(title: name, updatedAt: DateTime.now().toUtc()));
    await _load();
  }

  Future<void> _delete(SceneMeta m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete scene?'),
        content: Text('"${m.title}" will be deleted permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.delete(m.id);
    _thumbs.remove(m.id)?.dispose();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) return _empty();
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.82,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _tile(items[i]),
    );
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.movie_filter_outlined, size: 48, color: Colors.white24),
          const SizedBox(height: 10),
          const Text('No scenes yet', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.onNew,
            icon: const Icon(Icons.add),
            label: const Text('New scene'),
          ),
        ]),
      );

  String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Widget _tile(SceneMeta m) {
    _ensureThumb(m);
    final img = _thumbs[m.id];
    final isCurrent = m.id == widget.currentId;
    return Material(
      color: const Color(0xFF1A1C1F),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onOpen(m.id),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF101214),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CustomPaint(
                      painter: const CheckerPainter(),
                      child: img != null
                          ? RawImage(
                              image: img,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.none)
                          : const Center(
                              child:
                                  Icon(Icons.image_outlined, size: 24, color: Colors.white24)),
                    ),
                  ),
                ),
                if (isCurrent)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xCC30A050),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Open',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: PopupMenuButton<String>(
                    iconSize: 18,
                    onSelected: (v) => v == 'rename' ? _rename(m) : _delete(m),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      if (!isCurrent)
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            Text(m.title,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(
              '${m.width}×${m.height} · ${fpsLabel(m.fpsMilli)} · ${_ago(m.updatedAt)}',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
      ),
    );
  }
}
