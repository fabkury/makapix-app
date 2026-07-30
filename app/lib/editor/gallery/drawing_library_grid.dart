import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:makapix_club/engine_ffi.dart';

import '../persistence/drawing_meta.dart';
import '../persistence/drawing_store.dart';
import '../widgets/painters.dart';

/// The reusable body of the local drawing library ("My Drawings"): a grid of every saved drawing
/// (thumbnail + title + last-edited) with in-place Rename / Delete, an empty-state, and an "Open"
/// badge on the currently-open drawing. Thumbnails are rendered from each `.mkpx` via a short-lived
/// temp engine, so this widget never touches the editor's live engine.
///
/// It owns no navigation: [onOpen] and [onNew] are supplied by the host — the editor's [GalleryPage]
/// pops a `GalleryResult`, while the profile's Private tab hands off to the editor pillar via the
/// local-library bridge. Rename/Delete are handled internally (self-refreshing) against [store].
class DrawingLibraryGrid extends StatefulWidget {
  final DrawingStore store;

  /// The currently-open drawing, if any: it gets an "Open" badge and its Delete is suppressed
  /// (autosave would recreate it). Null when no drawing is "live" (e.g. the profile's Private tab,
  /// where the editor is unmounted).
  final String? currentId;

  /// Open a drawing by id (host decides what "open" means).
  final void Function(String id) onOpen;

  /// Start a new drawing (host decides).
  final VoidCallback onNew;

  /// "Animate this" — hand the drawing to the Animator pillar (a menu item appears when set).
  final void Function(String id)? onAnimate;

  const DrawingLibraryGrid({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onNew,
    this.currentId,
    this.onAnimate,
  });

  @override
  State<DrawingLibraryGrid> createState() => _DrawingLibraryGridState();
}

class _DrawingLibraryGridState extends State<DrawingLibraryGrid> {
  List<DrawingMeta>? _items;
  // Decoded thumbnails, keyed by drawing id — decoded lazily per visible tile (not all upfront),
  // bounded FIFO so a large library can't retain O(drawings) ui.Images. [audit #14 gallery]
  final Map<String, ui.Image> _thumbs = {};
  final Set<String> _inFlight = {}; // ids whose thumbnail decode is in progress (de-dup guard)
  bool _loading = true;
  static const int _thumbCap = 60; // comfortably exceeds any simultaneously-visible tile count

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

  // Page open is now metadata-only (store.list reads per-drawing meta.json, never the full .mkpx),
  // so it's instant; thumbnails stream in lazily per visible tile via [_ensureThumb]. Also re-run
  // after Rename/Delete to refresh the list (cached thumbs persist; a deleted one is dropped there).
  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await widget.store.list();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  // Decode one drawing's thumbnail on demand. The engine is a **per-decode local** created, used,
  // and disposed **before** the decode await — so no full document is ever retained while the
  // gallery sits idle, and there's no shared-engine dispose-during-decode race. `frameThumb`
  // returns an independent copy (not the #5 reused buffer), so it survives the engine's disposal
  // and the await. [review A/B/C/D]
  Future<void> _ensureThumb(DrawingMeta m) async {
    if (_thumbs.containsKey(m.id) || _inFlight.contains(m.id)) return;
    _inFlight.add(m.id);
    ui.Image? img;
    try {
      final bytes = await widget.store.readDoc(m.id);
      if (!mounted || bytes == null) return;
      // Whole engine lifecycle is synchronous (no await inside) and disposed in the finally, so at
      // most one document is materialized at any instant even under concurrent decodes.
      final rendered = () {
        final eng = Engine(8, 8);
        try {
          if (!eng.load(bytes)) return null;
          final w = eng.width, h = eng.height;
          const maxDim = 220;
          final scale = w >= h ? maxDim / w : maxDim / h;
          final tw = (w * scale).round().clamp(1, maxDim);
          final th = (h * scale).round().clamp(1, maxDim);
          final rgba = eng.frameThumb(0, tw, th);
          return rgba.isEmpty ? null : (rgba: rgba, tw: tw, th: th);
        } finally {
          eng.dispose();
        }
      }();
      if (rendered == null) return;
      img = await _decodeRgba(rendered.rgba, rendered.tw, rendered.th);
      if (!mounted) return; // finally disposes `img`
      _thumbs[m.id] = img;
      img = null; // handed to the cache — don't dispose it below
      // FIFO cap: evict + dispose the oldest entry other than the one just added.
      if (_thumbs.length > _thumbCap) {
        final victim = _thumbs.keys.firstWhere((k) => k != m.id, orElse: () => '');
        if (victim.isNotEmpty) _thumbs.remove(victim)?.dispose();
      }
      setState(() {});
    } catch (_) {
      // unreadable/corrupt drawing → leave the placeholder icon
    } finally {
      _inFlight.remove(m.id);
      img?.dispose(); // decoded but not cached (unmounted / late exception) — never leak it
    }
  }

  Future<ui.Image> _decodeRgba(Uint8List bytes, int w, int h) {
    final c = Completer<ui.Image>();
    // The engine emits straight alpha; the raw decode expects premultiplied (see engine_ffi).
    premultiplyRgbaInPlace(bytes);
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (items == null || items.isEmpty) return _empty();
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
              onPressed: widget.onNew,
            ),
          ],
        ),
      );

  Widget _tile(DrawingMeta m) {
    final isCurrent = m.id == widget.currentId;
    final img = _thumbs[m.id];
    // Lazily decode this drawing's thumbnail the first time its (visible) tile builds; the guard in
    // _ensureThumb makes repeat calls cheap no-ops. Fire-and-forget: it setStates when ready.
    if (img == null) unawaited(_ensureThumb(m));
    return InkWell(
      onTap: () => widget.onOpen(m.id),
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
                        if (v == 'animate') widget.onAnimate?.call(m.id);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'rename', child: Text('Rename')),
                        if (widget.onAnimate != null)
                          const PopupMenuItem(value: 'animate', child: Text('Animate this')),
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
