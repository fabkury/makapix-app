// The full-screen palette page (replaces the old row-2 palette-controls bottom sheet):
// previews every document palette as swatch cards, loads one on tap, and manages them —
// rename / duplicate / export / clear / delete, drag-to-reorder, import, "from artwork
// colours", and a read-only Presets section bundled as assets.
//
// The page talks to the engine only through [PaletteHost], so widget tests can drive it with
// a fake and never need the native binary. Destructive operations (delete, clear) always
// reconfirm: palette edits live OUTSIDE the engine's undo history and cannot be undone.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../engine_ffi.dart';
import 'palette_io.dart';

/// Palettes per document — mirrors the engine's MAX_PALETTES (the .mkpx loader bound). The
/// engine silently no-ops past it, so every add path pre-checks to avoid a NewPalette no-op
/// letting the follow-up AddPaletteColor batch pollute the active palette.
const int kMaxPalettes = 256;

/// Colours per palette — the engine's used-colours scan aborts past this many uniques.
const int kMaxPaletteColors = 256;

/// The bundled preset palettes (GIMP/Lospec .gpl), shown read-only below the document's own.
const List<String> kPresetPaletteAssets = [
  'assets/palettes/pico-8.gpl',
  'assets/palettes/endesga-32.gpl',
  'assets/palettes/resurrect-64.gpl',
  'assets/palettes/nintendo-entertainment-system.gpl',
  'assets/palettes/comfort44s.gpl',
];

Future<List<PaletteInfo>> loadPresetPalettes({AssetBundle? bundle}) async {
  final b = bundle ?? rootBundle;
  final out = <PaletteInfo>[];
  for (final path in kPresetPaletteAssets) {
    try {
      final stem = path.split('/').last.split('.').first;
      final p = parsePaletteFile(await b.loadString(path), fallbackName: stem);
      if (p.colors.isNotEmpty) out.add(p);
    } catch (_) {} // a missing/corrupt asset must not take down the page
  }
  return out;
}

/// What the page needs from the engine — kept minimal so tests can fake it.
abstract class PaletteHost {
  ({List<PaletteInfo> palettes, int active}) readPalettes();

  /// Runs a DSL script; null on success, else the engine's error string.
  String? run(String dsl);

  /// `{"colors":["#RRGGBBAA",...]}` or `{"over_limit":true}` (engine aborts past 256 uniques).
  String usedColorsJson();
}

class EnginePaletteHost implements PaletteHost {
  EnginePaletteHost(this.engine, {this.onMutated});
  final Engine engine;

  /// Fired after every mutation so the editor's autosave sees the activity (what `_send` does).
  final VoidCallback? onMutated;

  @override
  ({List<PaletteInfo> palettes, int active}) readPalettes() {
    try {
      final state = json.decode(engine.stateJson()) as Map<String, dynamic>;
      return (palettes: palettesFromState(state), active: (state['active_palette'] as int?) ?? 0);
    } catch (_) {
      return (palettes: const <PaletteInfo>[], active: 0);
    }
  }

  @override
  String? run(String dsl) {
    final err = engine.run(dsl);
    onMutated?.call();
    return err;
  }

  @override
  String usedColorsJson() => engine.usedColorsJson();
}

class PalettePage extends StatefulWidget {
  const PalettePage({super.key, required this.host, this.presetLoader});
  final PaletteHost host;

  /// Overridable so tests can inject presets without asset bundles.
  final Future<List<PaletteInfo>> Function()? presetLoader;

  @override
  State<PalettePage> createState() => _PalettePageState();
}

class _PalettePageState extends State<PalettePage> {
  static const _green = Color(0xFF30A050); // the editor's active-highlight accent
  static const _cardBg = Color(0xFF23272B);

  List<PaletteInfo> _palettes = [];
  int _active = 0;
  late final Future<List<PaletteInfo>> _presets;

  @override
  void initState() {
    super.initState();
    _reload();
    _presets = (widget.presetLoader ?? loadPresetPalettes)();
  }

  void _reload() {
    final r = widget.host.readPalettes();
    _palettes = r.palettes;
    _active = r.active;
  }

  void _mutate(String dsl) {
    final err = widget.host.run(dsl);
    if (err != null) debugPrint('palette DSL error: $err  <- $dsl');
    setState(_reload);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  bool _belowCap() {
    if (_palettes.length < kMaxPalettes) return true;
    _toast('Palette limit reached ($kMaxPalettes)');
    return false;
  }

  // ---- dialogs ----

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<String?> _nameDialog(String title, String initial, String action) async {
    final ctrl = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(action)),
        ],
      ),
    );
    return (name == null || name.trim().isEmpty) ? null : name;
  }

  // ---- per-palette actions ----

  void _paletteActions(int i) {
    final p = _palettes[i];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${p.colors.length} colours'),
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(ctx);
              _renamePalette(i);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Duplicate'),
            onTap: () {
              Navigator.pop(ctx);
              _duplicatePalette(i);
            },
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Export .gpl'),
            onTap: () {
              Navigator.pop(ctx);
              _exportPalette(i);
            },
          ),
          ListTile(
            leading: const Icon(Icons.format_color_reset),
            title: const Text('Clear'),
            enabled: p.colors.isNotEmpty,
            onTap: () {
              Navigator.pop(ctx);
              _clearPalette(i);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete'),
            enabled: _palettes.length > 1,
            onTap: () {
              Navigator.pop(ctx);
              _deletePalette(i);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _renamePalette(int i) async {
    final name = await _nameDialog('Rename palette', _palettes[i].name, 'Rename');
    if (name == null || !mounted) return;
    _mutate('RenamePaletteAt($i, ${sanitizePaletteName(name)})');
  }

  void _duplicatePalette(int i) {
    if (i >= _palettes.length || !_belowCap()) return;
    _mutate('DuplicatePalette($i)');
  }

  Future<void> _exportPalette(int i) async {
    final p = _palettes[i];
    final safe = p.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final path =
        await FilePicker.saveFile(fileName: '$safe.gpl', type: FileType.custom, allowedExtensions: ['gpl']);
    if (path == null || !mounted) return;
    await File(path).writeAsString(encodeGpl(p.name, p.colors));
    if (!mounted) return;
    _toast('Saved palette (${p.colors.length} colours)');
  }

  Future<void> _clearPalette(int i) async {
    final p = _palettes[i];
    if (p.colors.isEmpty) return;
    final ok = await _confirm('Clear "${p.name}"?',
        'Removes all ${p.colors.length} colours from this palette. This cannot be undone.', 'Clear');
    if (!ok) return;
    _mutate('ClearPaletteAt($i)');
  }

  Future<void> _deletePalette(int i) async {
    if (_palettes.length <= 1) return;
    final p = _palettes[i];
    final ok = await _confirm('Delete "${p.name}"?',
        'Deletes this palette and its ${p.colors.length} colours. This cannot be undone.', 'Delete');
    if (!ok) return;
    _mutate('DeletePalette($i)');
  }

  // ---- add flow ----

  void _addMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.add_box_outlined),
            title: const Text('New palette'),
            onTap: () {
              Navigator.pop(ctx);
              _newPalette();
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Duplicate current'),
            onTap: () {
              Navigator.pop(ctx);
              _duplicatePalette(_active);
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import palette (.gpl/.json)'),
            onTap: () {
              Navigator.pop(ctx);
              _importFile();
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('From artwork colours'),
            onTap: () {
              Navigator.pop(ctx);
              _fromArtwork();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _newPalette() async {
    if (!_belowCap()) return;
    final name = await _nameDialog('New palette', 'Palette', 'Create');
    if (name == null || !mounted) return;
    _mutate('NewPalette(${sanitizePaletteName(name)})');
  }

  Future<void> _importFile() async {
    if (!_belowCap()) return;
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['gpl', 'json', 'txt']);
    if (res == null || res.files.single.path == null || !mounted) return;
    final text = await File(res.files.single.path!).readAsString();
    if (!mounted) return;
    final p = parsePaletteFile(text, fallbackName: res.files.single.name.split('.').first);
    if (p.colors.isEmpty) {
      _toast('No colours found');
      return;
    }
    _mutate(buildImportScript(p.name, p.colors));
    _toast('Imported "${p.name}" (${p.colors.length} colours)');
  }

  Future<void> _fromArtwork() async {
    if (!_belowCap()) return;
    Map<String, dynamic> r;
    try {
      r = json.decode(widget.host.usedColorsJson()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (r['over_limit'] == true) {
      _toast('The artwork uses more than $kMaxPaletteColors colours.');
      return;
    }
    final colors = [for (final h in (r['colors'] as List? ?? const [])) parseHexColor(h.toString())];
    if (colors.isEmpty) {
      _toast('The artwork has no colours yet');
      return;
    }
    _mutate(buildImportScript('Artwork colours', colors));
    _toast('Created "Artwork colours" (${colors.length} colours)');
  }

  void _importPreset(PaletteInfo p) {
    if (!_belowCap()) return;
    _mutate(buildImportScript(p.name, p.colors)); // NewPalette activates the import
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ---- widgets ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Palettes'),
        actions: [IconButton(tooltip: 'Add palette', icon: const Icon(Icons.add), onPressed: _addMenu)],
      ),
      body: ReorderableListView(
        padding: const EdgeInsets.all(8),
        buildDefaultDragHandles: false, // long-press opens the actions sheet; drag via the handle
        header: const Padding(
          padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Text('Tap a palette to load it. Drag the handle to reorder.',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ),
        footer: _presetsFooter(),
        // onReorderItem already delivers the post-removal target index — MovePalette semantics.
        onReorderItem: (o, n) {
          if (n != o) _mutate('MovePalette($o, $n)');
        },
        children: [for (var i = 0; i < _palettes.length; i++) _paletteCard(i, _palettes[i])],
      ),
    );
  }

  Widget _paletteCard(int i, PaletteInfo p) {
    final active = i == _active;
    return Card(
      key: ValueKey('pal-$i'),
      color: _cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: active ? const BorderSide(color: _green, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _mutate('SetActivePalette($i)');
          Navigator.of(context).pop(); // load-and-return
        },
        onLongPress: () => _paletteActions(i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (active) const Icon(Icons.check_circle, size: 18, color: _green),
              if (active) const SizedBox(width: 6),
              Expanded(
                child: Text(
                  p.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, color: active ? _green : null),
                ),
              ),
              Text('${p.colors.length} colours',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Icon(Icons.drag_handle, size: 20, color: Colors.white38),
                ),
              ),
              IconButton(
                tooltip: 'Palette actions',
                icon: const Icon(Icons.more_vert, size: 20, color: Colors.white70),
                onPressed: () => _paletteActions(i),
              ),
            ]),
            _swatchGrid(p),
          ]),
        ),
      ),
    );
  }

  Widget _presetCard(PaletteInfo p) {
    return Card(
      color: const Color(0xFF1E2226),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _importPreset(p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(p.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Text('${p.colors.length} colours',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            _swatchGrid(p),
          ]),
        ),
      ),
    );
  }

  Widget _swatchGrid(PaletteInfo p) {
    if (p.colors.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('empty', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.white38)),
      );
    }
    return LayoutBuilder(builder: (ctx, cons) {
      final cols = swatchColumns(cons.maxWidth);
      final lay = swatchLayout(p.colors.length, cols);
      return Wrap(spacing: 4, runSpacing: 4, children: [
        for (var k = 0; k < lay.shown; k++)
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: p.colors[k],
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        if (lay.trimmed)
          const SizedBox(
            width: 24,
            height: 24,
            child: Center(child: Text('…', style: TextStyle(color: Colors.white70))),
          ),
      ]);
    });
  }

  Widget _presetsFooter() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(8, 20, 8, 4),
        child: Text('Presets', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
      ),
      FutureBuilder<List<PaletteInfo>>(
        future: _presets,
        builder: (ctx, snap) {
          final ps = snap.data ?? const <PaletteInfo>[];
          if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 48);
          if (ps.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(8),
              child: Text('No presets bundled', style: TextStyle(color: Colors.white38)),
            );
          }
          return Column(children: [for (final p in ps) _presetCard(p)]);
        },
      ),
      const SizedBox(height: 24),
    ]);
  }
}
