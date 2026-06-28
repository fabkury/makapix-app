import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:makapix_club/engine_ffi.dart';

import '../persistence/drawing_meta.dart';
import '../persistence/drawing_store.dart';
import '../widgets/painters.dart';

enum GalleryAction { open, newDrawing }

/// What the editor should do after the gallery closes.
class GalleryResult {
  final GalleryAction action;
  final String? id; // set for [GalleryAction.open]
  const GalleryResult.open(this.id) : action = GalleryAction.open;
  const GalleryResult.newDrawing()
      : id = null,
        action = GalleryAction.newDrawing;
}

/// "My Drawings" — the local working library. Lists every saved drawing (thumbnail + title + last
/// edited), and lets the user open one, start a new one, rename, or delete. Thumbnails are rendered
/// here from each `.mkpx` via a short-lived temp engine, so this page never touches the editor's
/// live engine.
class GalleryPage extends StatefulWidget {
  final DrawingStore store;
  final String? currentId;
  const GalleryPage({super.key, required this.store, this.currentId});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<DrawingMeta>? _items;
  final Map<String, ui.Image> _thumbs = {};
  bool _loading = true;

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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await widget.store.list();
    // One shared temp engine renders every thumbnail (cheap RLE loads); disposed when done.
    Engine? eng;
    for (final m in items) {
      try {
        final bytes = await widget.store.readDoc(m.id);
        if (bytes == null) continue;
        eng ??= Engine(8, 8);
        if (!eng.load(bytes)) continue;
        final w = eng.width, h = eng.height;
        const maxDim = 220;
        final scale = w >= h ? maxDim / w : maxDim / h;
        final tw = (w * scale).round().clamp(1, maxDim);
        final th = (h * scale).round().clamp(1, maxDim);
        final rgba = eng.frameThumb(0, tw, th);
        if (rgba.isEmpty) continue;
        final img = await _decodeRgba(rgba, tw, th);
        if (!mounted) {
          img.dispose();
          break;
        }
        _thumbs[m.id]?.dispose();
        _thumbs[m.id] = img;
      } catch (_) {/* skip an unreadable drawing */}
    }
    eng?.dispose();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<ui.Image> _decodeRgba(Uint8List bytes, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  Future<void> _rename(DrawingMeta m) async {
    final ctrl = TextEditingController(text: m.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename drawing'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Title'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == m.title) return;
    await widget.store.writeMeta(m.copyWith(title: name));
    await _load();
  }

  Future<void> _delete(DrawingMeta m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${m.title}"?'),
        content: const Text('This permanently removes the drawing from this device.'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Drawings'),
        actions: [
          IconButton(
            tooltip: 'New drawing',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).pop(const GalleryResult.newDrawing()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (items == null || items.isEmpty)
              ? _empty()
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 0.82,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _tile(items[i]),
                ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.brush_outlined, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('No drawings yet', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('New drawing'),
              onPressed: () => Navigator.of(context).pop(const GalleryResult.newDrawing()),
            ),
          ],
        ),
      );

  Widget _tile(DrawingMeta m) {
    final isCurrent = m.id == widget.currentId;
    final img = _thumbs[m.id];
    return InkWell(
      onTap: () => Navigator.of(context).pop(GalleryResult.open(m.id)),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const CustomPaint(painter: CheckerPainter()),
                  if (img != null)
                    RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.none)
                  else
                    const Center(child: Icon(Icons.image_outlined, color: Colors.white24)),
                  if (isCurrent)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xCC30A050),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Open', style: TextStyle(fontSize: 10, color: Colors.white)),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18, color: Colors.white70),
                      onSelected: (v) {
                        if (v == 'rename') _rename(m);
                        if (v == 'delete') _delete(m);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'rename', child: Text('Rename')),
                        // The open drawing can't be deleted from here (autosave would recreate it).
                        if (!isCurrent) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          Text('${m.width}×${m.height} · ${_ago(m.updatedAt)}',
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
