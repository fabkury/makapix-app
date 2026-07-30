// On-disk library of Animator Scenes — DrawingStore's twin over `.mkps` files, with the same
// injected base directory, crash-safe 4-step write dance, `.bak` fallback, and newest-first
// listing. Owns no engine, UI, or network state; fully unit-testable.
//
// Layout: `<base>/scenes/<id>/{doc.mkps, doc.mkps.bak, doc.mkps.tmp, meta.json}`.
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'scene_meta.dart';

class SceneStore {
  final Directory root; // <base>/scenes

  SceneStore(Directory base) : root = Directory(p.join(base.path, 'scenes'));

  static const _doc = 'doc.mkps';
  static const _bak = 'doc.mkps.bak';
  static const _tmp = 'doc.mkps.tmp';
  static const _meta = 'meta.json';

  Directory dirFor(String id) => Directory(p.join(root.path, id));
  File _file(String id, String name) => File(p.join(root.path, id, name));
  File docFile(String id) => _file(id, _doc);

  /// A fresh, filesystem-safe scene id (`scn_` + base36 micros + random tail — the
  /// DrawingStore recipe; ordering rides `meta.updatedAt`, never the id).
  static String newId([int? seedMicros, int? seedRand]) {
    final micros = seedMicros ?? DateTime.now().microsecondsSinceEpoch;
    final rand = seedRand ?? DateTime.now().microsecond ^ (micros & 0xFFFF);
    return 'scn_${micros.toRadixString(36)}_${(rand & 0xFFFF).toRadixString(36)}';
  }

  // ---- writes ----------------------------------------------------------------

  /// Atomically replace `doc.mkps`, keeping the prior copy as `.bak`. Crash-safe: at any
  /// interruption point a complete current or backup exists. No-op on empty bytes.
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
    await tmp.rename(doc.path); // 4. promote staged → current (absent target: Windows-safe)
  }

  /// Write `meta.json` (tmp→rename). Best-effort; metadata is non-authoritative.
  Future<void> writeMeta(SceneMeta meta) async {
    final dir = dirFor(meta.id);
    if (!await dir.exists()) await dir.create(recursive: true);
    final tmp = _file(meta.id, '$_meta.tmp');
    final dst = _file(meta.id, _meta);
    await tmp.writeAsString(meta.encode(), flush: true);
    if (await dst.exists()) await dst.delete();
    await tmp.rename(dst.path);
  }

  // ---- reads -----------------------------------------------------------------

  /// Load a scene's `.mkps` bytes, falling back to `.bak`; [validate] (typically the engine
  /// loader) decides whether the primary is intact. Null if neither yields usable bytes.
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

  Future<SceneMeta?> readMeta(String id) async {
    final f = _file(id, _meta);
    if (!await f.exists()) return null;
    try {
      return SceneMeta.tryParse(await f.readAsString(),
          fallbackId: id, fallbackTime: (await f.stat()).modified.toUtc());
    } catch (_) {
      return null;
    }
  }

  /// Every scene (scanning `meta.json` per folder), newest-updated first; folders without a
  /// usable doc or meta are skipped.
  Future<List<SceneMeta>> list() async {
    if (!await root.exists()) return [];
    final out = <SceneMeta>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final id = p.basename(entry.path);
      if (!await docFile(id).exists()) continue;
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
