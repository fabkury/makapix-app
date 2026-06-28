import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'drawing_meta.dart';

/// On-disk library of drawings. All file I/O for autosave/recovery lives here; it owns no engine,
/// UI or network state. The base directory is **injected** (the editor passes `path_provider`'s
/// app-support dir; tests pass a temp dir), so this class is fully unit-testable.
///
/// Layout: `<base>/drawings/<id>/{doc.mkpx, doc.mkpx.bak, doc.mkpx.tmp, meta.json, thumb.png}`.
class DrawingStore {
  final Directory root; // <base>/drawings

  DrawingStore(Directory base) : root = Directory(p.join(base.path, 'drawings'));

  static const _doc = 'doc.mkpx';
  static const _bak = 'doc.mkpx.bak';
  static const _tmp = 'doc.mkpx.tmp';
  static const _meta = 'meta.json';
  static const _thumb = 'thumb.png';

  Directory dirFor(String id) => Directory(p.join(root.path, id));
  File _file(String id, String name) => File(p.join(root.path, id, name));
  File docFile(String id) => _file(id, _doc);
  File thumbFile(String id) => _file(id, _thumb);

  /// A fresh, filesystem-safe drawing id: a base36 microsecond timestamp prefix with a random tail
  /// to avoid collisions within the same microsecond. No uuid dependency. (The gallery orders by
  /// `meta.updatedAt`, not by id, so id ordering is not relied upon.)
  static String newId([int? seedMicros, int? seedRand]) {
    final micros = seedMicros ?? DateTime.now().microsecondsSinceEpoch;
    final rand = seedRand ?? DateTime.now().microsecond ^ (micros & 0xFFFF);
    return 'dwg_${micros.toRadixString(36)}_${(rand & 0xFFFF).toRadixString(36)}';
  }

  // ---- writes ----------------------------------------------------------------

  /// Atomically replace the drawing's `doc.mkpx` with [bytes], keeping the prior copy as
  /// `doc.mkpx.bak`. Crash-safe: at any interruption point a complete `doc.mkpx` (old or new) or
  /// `doc.mkpx.bak` (old) exists. No-op on empty bytes (never clobbers a good file with nothing).
  Future<void> writeDoc(String id, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    final dir = dirFor(id);
    if (!await dir.exists()) await dir.create(recursive: true);
    final doc = docFile(id);
    final tmp = _file(id, _tmp);
    final bak = _file(id, _bak);

    await tmp.writeAsBytes(bytes, flush: true); // 1. stage the new bytes
    if (await bak.exists()) await bak.delete(); // 2. clear the old backup
    if (await doc.exists()) await doc.rename(bak.path); // 3. demote current → backup
    await tmp.rename(doc.path); // 4. promote staged → current (target is now absent: works on Windows too)
  }

  /// Write `meta.json` (tmp→rename so a torn write can't corrupt it). Best-effort; metadata is
  /// non-authoritative.
  Future<void> writeMeta(DrawingMeta meta) async {
    final dir = dirFor(meta.id);
    if (!await dir.exists()) await dir.create(recursive: true);
    final tmp = _file(meta.id, '$_meta.tmp');
    final dst = _file(meta.id, _meta);
    await tmp.writeAsString(meta.encode(), flush: true);
    if (await dst.exists()) await dst.delete();
    await tmp.rename(dst.path);
  }

  /// Write the gallery thumbnail (already-encoded PNG bytes). Best-effort.
  Future<void> writeThumb(String id, Uint8List png) async {
    if (png.isEmpty) return;
    final dir = dirFor(id);
    if (!await dir.exists()) await dir.create(recursive: true);
    final tmp = _file(id, '$_thumb.tmp');
    final dst = thumbFile(id);
    await tmp.writeAsBytes(png, flush: true);
    if (await dst.exists()) await dst.delete();
    await tmp.rename(dst.path);
  }

  // ---- reads -----------------------------------------------------------------

  /// Load a drawing's `.mkpx` bytes, falling back to `doc.mkpx.bak` if the primary is missing.
  /// [validate] (default the engine loader) decides whether the primary is intact; on a corrupt
  /// primary the backup is returned. Returns null if neither yields usable bytes.
  Future<Uint8List?> readDoc(String id, {bool Function(Uint8List)? validate}) async {
    Future<Uint8List?> tryFile(File f) async {
      if (!await f.exists()) return null;
      try {
        final b = await f.readAsBytes();
        if (b.isEmpty) return null;
        if (validate != null && !validate(b)) return null;
        return b;
      } catch (_) {
        return null;
      }
    }

    return await tryFile(docFile(id)) ?? await tryFile(_file(id, _bak));
  }

  Future<DrawingMeta?> readMeta(String id) async {
    final f = _file(id, _meta);
    if (!await f.exists()) return null;
    try {
      return DrawingMeta.tryParse(await f.readAsString(),
          fallbackId: id, fallbackTime: (await f.stat()).modified.toUtc());
    } catch (_) {
      return null;
    }
  }

  /// List every drawing (by scanning `meta.json` per folder), newest-updated first. Folders without
  /// a usable doc or meta are skipped (e.g. a half-created or partially-deleted entry).
  Future<List<DrawingMeta>> list() async {
    if (!await root.exists()) return [];
    final out = <DrawingMeta>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final id = p.basename(entry.path);
      if (!await docFile(id).exists()) continue; // no artwork → not a real drawing
      final meta = await readMeta(id);
      if (meta != null) out.add(meta);
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<bool> exists(String id) => docFile(id).exists();

  Future<void> delete(String id) async {
    final dir = dirFor(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
