// Makapix Editor — Flutter shell (SPEC §20). Smartphone-first three-row UI over the
// deterministic Rust engine. The engine owns the document; this shell captures input and
// presents composited buffers.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MakapixApp());
}

class MakapixApp extends StatelessWidget {
  const MakapixApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Makapix Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4080C0),
          brightness: Brightness.dark,
        ),
        sliderTheme: const SliderThemeData(trackHeight: 2),
      ),
      home: const EditorPage(),
    );
  }
}

class ToolDef {
  final String dsl;
  final IconData icon;
  final String label;
  const ToolDef(this.dsl, this.icon, this.label);
}

const tools = <ToolDef>[
  ToolDef('Pencil', Icons.edit, 'Pencil'),
  ToolDef('PrecisionPencil', Icons.gps_fixed, 'Precision'),
  ToolDef('Brush', Icons.brush, 'Brush'),
  ToolDef('Airbrush', Icons.blur_on, 'Airbrush'),
  ToolDef('Eraser', Icons.auto_fix_normal, 'Eraser'),
  ToolDef('Bucket', Icons.format_color_fill, 'Fill'),
  ToolDef('Gradient', Icons.gradient, 'Gradient'),
  ToolDef('Line', Icons.show_chart, 'Line'),
  ToolDef('Rectangle', Icons.crop_square, 'Rect'),
  ToolDef('Ellipse', Icons.circle_outlined, 'Ellipse'),
  ToolDef('Dodge', Icons.light_mode, 'Dodge'),
  ToolDef('Burn', Icons.dark_mode, 'Burn'),
  ToolDef('Eyedropper', Icons.colorize, 'Pick'),
  ToolDef('Move', Icons.open_with, 'Move'),
  ToolDef('SelectRect', Icons.highlight_alt, 'Sel Rect'),
  ToolDef('SelectEllipse', Icons.lens_blur, 'Sel Oval'),
  ToolDef('SelectFree', Icons.gesture, 'Lasso'),
  ToolDef('SelectByColor', Icons.colorize_outlined, 'Sel Color'),
  ToolDef('HsvShift', Icons.palette, 'HSV'),
];

// Succinct, teach-as-you-go help shown in the gesture-safe band at the bottom.
const toolTips = <String, String>{
  'Pencil': 'Drag to draw hard pixels in the primary colour.',
  'PrecisionPencil':
      'Drag to move the ✛ reticle off your finger; arrows nudge 1px. Tap DRAW for a dot, or turn PEN on and drag to draw a line.',
  'Brush': 'Drag to paint, blending onto existing pixels.',
  'Airbrush': 'Drag/hold to spray — density builds up. Set size & intensity.',
  'Eraser': 'Drag to erase pixels to transparent.',
  'Bucket': 'Tap an area to flood-fill. Threshold = colour tolerance.',
  'Gradient': 'Drag start→end to fill a gradient. Pick 2–3 colours, Linear/Radial.',
  'Line': 'Drag from one point to another to draw a straight line.',
  'Rectangle': 'Drag corner-to-corner. Toggle Fill / Outline.',
  'Ellipse': 'Drag to bound an ellipse. Toggle Fill / Outline.',
  'Dodge': 'Drag over pixels to lighten them. Set intensity.',
  'Burn': 'Drag over pixels to darken them. Set intensity.',
  'Eyedropper': 'Tap a pixel to pick its colour as primary.',
  'Move': 'Select first, then drag the selected pixels to move them.',
  'SelectRect': 'Drag to select a rectangle. Use Add/Subtract/Intersect modes.',
  'SelectEllipse': 'Drag to select an ellipse. Combine with Add/Subtract modes.',
  'SelectCircle': 'Drag from centre outward to select a circle.',
  'SelectPoly': 'Trace an outline; it closes into a selection on release.',
  'SelectFree': 'Lasso: trace around pixels to select them.',
  'SelectByColor': 'Tap to select similar-colour pixels. Threshold = tolerance.',
  'HsvShift': 'Shift Hue/Sat/Value of the selection. Set H/S/V, then Apply.',
};

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with SingleTickerProviderStateMixin {
  late Engine engine;
  ui.Image? _image;
  late AnimationController _antCtrl; // marching-ants animation phase
  List<List<int>> _outlineEdges = const []; // each: [x1,y1,x2,y2,t] in canvas-corner coords
  String _tool = 'Pencil';
  Color _primary = const Color(0xFF000000);
  List<Color> _palette = [];
  int _brushSize = 1;
  bool _round = true;
  int _threshold = 16;
  bool _contiguous = true;
  bool _shapeFill = true;
  bool _radial = false;
  int _intensity = 128;
  String _selMode = 'Replace';
  Color _gradA = const Color(0xFF102040);
  Color _gradB = const Color(0xFFFFFFFF);
  double _hsvH = 60, _hsvS = 0, _hsvV = 0;
  bool _onion = false;
  bool _grid = false;
  bool _playing = false;
  Timer? _playTimer;
  Map<String, dynamic> _state = {};
  String? _error;
  final Set<int> _selLayers = {}; // multi-selected layers for group move
  String _clubUrl = 'http://localhost:8080';
  String _clubToken = '';
  // precision pencil
  bool _penDown = false;
  Offset? _lastTouch;
  double _accX = 0, _accY = 0;
  // configurable bottom toolbar
  List<String> _toolOrder = tools.map((t) => t.dsl).toList();
  bool _reorderMode = false;
  static const _prefsKey = 'tool_order_v1';
  // film-roll frame thumbnails (cached, invalidated by per-frame content hash)
  final Map<int, _Thumb> _frameThumbs = {};
  final Set<int> _thumbInFlight = {};

  bool get _isPrecision => _tool == 'PrecisionPencil';

  bool get _engineReady => _error == null;

  @override
  void initState() {
    super.initState();
    _antCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat();
    _loadToolOrder();
    try {
      engine = Engine(64, 64);
      _send('SelectTool(Pencil)');
      _refreshState();
      _redraw();
    } catch (e) {
      _error = '$e';
    }
  }

  ToolDef _toolDef(String dsl) => tools.firstWhere((t) => t.dsl == dsl, orElse: () => tools.first);

  Future<void> _loadToolOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefsKey);
      final all = tools.map((t) => t.dsl).toList();
      if (saved != null) {
        // keep saved order, drop unknown tools, append any new tools at the end
        final reconciled = <String>[for (final d in saved) if (all.contains(d)) d];
        for (final d in all) {
          if (!reconciled.contains(d)) reconciled.add(d);
        }
        if (mounted) setState(() => _toolOrder = reconciled);
      }
    } catch (_) {/* prefs unavailable → keep default order */}
  }

  Future<void> _persistOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _toolOrder);
    } catch (_) {}
  }

  /// Reorder a tool from `from` to target slot `to` (drag-and-drop semantics).
  void _reorderTool(int from, int to) {
    if (from < 0 || from >= _toolOrder.length) return;
    setState(() {
      final item = _toolOrder.removeAt(from);
      if (to > from) to -= 1;
      _toolOrder.insert(to.clamp(0, _toolOrder.length), item);
    });
    _persistOrder();
  }

  /// Swap a tool with its neighbour (move left/right exactly one slot).
  void _moveTool(int i, int delta) {
    final j = i + delta;
    if (i < 0 || j < 0 || i >= _toolOrder.length || j >= _toolOrder.length) return;
    setState(() {
      final t = _toolOrder[i];
      _toolOrder[i] = _toolOrder[j];
      _toolOrder[j] = t;
    });
    _persistOrder();
  }

  Future<void> _resetToolOrder() async {
    setState(() => _toolOrder = tools.map((t) => t.dsl).toList());
    _persistOrder();
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _antCtrl.dispose();
    for (final t in _frameThumbs.values) {
      t.img.dispose();
    }
    _frameThumbs.clear();
    if (_engineReady) engine.dispose();
    super.dispose();
  }

  // Pull the selection (or live drag-preview) mask and turn it into thin boundary segments
  // for the screen-space marching-ants overlay.
  void _updateOutline() {
    if (!_engineReady) return;
    final w = engine.width, h = engine.height;
    final mask = engine.outlineMask();
    final edges = <List<int>>[];
    if (mask.isNotEmpty && mask.length >= w * h) {
      bool sel(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] != 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (mask[y * w + x] == 0) continue;
          final t = x + y;
          if (!sel(x - 1, y)) edges.add([x, y, x, y + 1, t]);
          if (!sel(x + 1, y)) edges.add([x + 1, y, x + 1, y + 1, t]);
          if (!sel(x, y - 1)) edges.add([x, y, x + 1, y, t]);
          if (!sel(x, y + 1)) edges.add([x, y + 1, x + 1, y + 1, t]);
        }
      }
    }
    _outlineEdges = edges;
  }

  String _hex(Color c) =>
      '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}${c.alpha.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  Color _parseHex(String h) {
    h = h.replaceAll('#', '');
    if (h.length == 6) h = '${h}FF';
    final v = int.parse(h, radix: 16);
    return Color.fromARGB(v & 0xFF, (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF);
  }

  void _send(String dsl) {
    if (!_engineReady) return;
    final err = engine.run(dsl);
    if (err != null) debugPrint('DSL error: $err  <- $dsl');
  }

  Future<void> _redraw() async {
    if (!_engineReady) return;
    _updateOutline();
    final w = engine.width, h = engine.height;
    final frame = _playing ? engine.playFrame : engine.activeFrame;
    final bytes = _playing
        ? engine.compositeFrame(frame)
        : engine.display(onion: _onion, grid: _grid, checker: true);
    final img = await _decode(bytes, w, h);
    if (mounted) setState(() => _image = img);
  }

  void _refreshState() {
    if (!_engineReady) return;
    try {
      _state = json.decode(engine.stateJson()) as Map<String, dynamic>;
      final pal = (_state['palette'] as List?)?.cast<String>() ?? [];
      _palette = pal.map(_parseHex).toList();
      final pc = engine.primaryColor;
      _primary = Color.fromARGB(pc & 0xFF, (pc >> 24) & 0xFF, (pc >> 16) & 0xFF, (pc >> 8) & 0xFF);
    } catch (_) {}
  }

  Future<ui.Image> _decode(Uint8List bytes, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  Future<ui.Image> _decodeBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _act(String dsl) {
    _send(dsl);
    _refreshState();
    _redraw();
    setState(() {});
  }

  void _selectTool(String t) {
    if (_penDown) {
      _send('CursorPenUp()');
      _penDown = false;
    }
    setState(() => _tool = t);
    _send('SelectTool($t)');
    if (t == 'PrecisionPencil') {
      _send('SetCursor(${engine.width ~/ 2},${engine.height ~/ 2})');
      _redraw();
    }
    _send('SetBrushSize($_brushSize); SetBrushShape(${_round ? 'Round' : 'Square'})');
    _send('SetThreshold($_threshold); SetContiguous($_contiguous)');
    _send('SetIntensity($_intensity); SetShapeFill($_shapeFill)');
    _send('SetSelectionMode($_selMode)');
    if (t == 'Gradient') {
      _send('SetGradientType(${_radial ? 'Radial' : 'Linear'})');
      _send('SetGradientStops([${_hex(_gradA)}@0, ${_hex(_gradB)}@1])');
    }
  }

  void _setPrimary(Color c) {
    setState(() => _primary = c);
    _send('SetPrimaryColor(${_hex(c)})');
  }

  Rect _fittedRect(Size box, int w, int h) {
    final s1 = box.width / w;
    final s2 = box.height / h;
    final s = s1 < s2 ? s1 : s2;
    final dw = w * s, dh = h * s;
    return Rect.fromLTWH((box.width - dw) / 2, (box.height - dh) / 2, dw, dh);
  }

  Offset _toCanvas(Offset local, Size box, int w, int h) {
    final r = _fittedRect(box, w, h);
    final px = ((local.dx - r.left) / r.width * w).floorToDouble();
    final py = ((local.dy - r.top) / r.height * h).floorToDouble();
    return Offset(px, py);
  }

  void _play() {
    if (engine.frameCount <= 1) return;
    setState(() => _playing = true);
    _send('Play()');
    _playTimer?.cancel();
    _playTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _send('AdvanceClock(33)');
      _redraw();
    });
  }

  void _pause() {
    _playTimer?.cancel();
    setState(() => _playing = false);
    _send('Pause()');
    _redraw();
  }

  Future<void> _save() async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save .mkpx',
      fileName: 'untitled.mkpx',
      type: FileType.custom,
      allowedExtensions: ['mkpx'],
    );
    if (path == null) return;
    final bytes = engine.save();
    await File(path).writeAsBytes(bytes);
    _toast('Saved ${bytes.length ~/ 1024} KiB → ${path.split(RegExp(r"[\\/]")).last}');
  }

  Future<void> _open() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['mkpx']);
    if (res == null || res.files.single.path == null) return;
    final bytes = await File(res.files.single.path!).readAsBytes();
    if (engine.load(bytes)) {
      _refreshState();
      _redraw();
      _toast('Opened ${res.files.single.name}');
    } else {
      _toast('Failed to load (corrupt or wrong version)');
    }
    setState(() {});
  }

  Future<void> _importImage() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'gif', 'jpg', 'jpeg', 'bmp', 'webp', 'apng'],
    );
    if (res == null || res.files.single.path == null) return;
    final bytes = await File(res.files.single.path!).readAsBytes();

    final srcImg = await _decodeBytes(bytes);
    int mode = 0; // Fit
    bool asLayer = true;
    Rect? cropRect; // in source pixels
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Import ${res.files.single.name} (${srcImg.width}×${srcImg.height})'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Scaling', style: TextStyle(fontSize: 12, color: Colors.white60)),
            const SizedBox(height: 4),
            ToggleButtons(
              isSelected: [mode == 0, mode == 1, mode == 2],
              onPressed: (i) => setS(() { mode = i; if (i != 2) cropRect = null; }),
              children: const [Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Fit')), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Stretch')), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Crop'))],
            ),
            if (mode == 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.crop, size: 16),
                  label: Text(cropRect == null ? 'Select crop area…' : 'Crop: ${cropRect!.width.toInt()}×${cropRect!.height.toInt()}'),
                  onPressed: () async {
                    final r = await showDialog<Rect>(context: context, builder: (_) => CropDialog(image: srcImg));
                    if (r != null) setS(() => cropRect = r);
                  },
                ),
              ),
            const SizedBox(height: 12),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Add as new layer in existing frames'),
              subtitle: const Text('(off = import as new frames)', style: TextStyle(fontSize: 11)),
              value: asLayer,
              onChanged: (v) => setS(() => asLayer = v),
            ),
            Text('Start at frame ${engine.activeFrame + 1}', style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final done = engine.importImage(bytes,
        mode: mode,
        asLayer: asLayer,
        startFrame: engine.activeFrame,
        cropX: cropRect?.left.toInt() ?? 0,
        cropY: cropRect?.top.toInt() ?? 0,
        cropW: cropRect?.width.toInt() ?? 0,
        cropH: cropRect?.height.toInt() ?? 0);
    if (done) {
      _refreshState();
      _redraw();
      _toast('Imported ${res.files.single.name} (${engine.frameCount} frames)');
    } else {
      _toast('Import failed (unsupported or too large)');
    }
    setState(() {});
  }

  Future<void> _uploadToClub() async {
    String title = 'Untitled';
    String tags = '';
    String visibility = 'public';
    String format = 'mkpx';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Upload to Makapix Club'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(decoration: const InputDecoration(labelText: 'Title'), controller: TextEditingController(text: title), onChanged: (v) => title = v),
              TextField(decoration: const InputDecoration(labelText: 'Tags (comma-separated)'), onChanged: (v) => tags = v),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Artifact: '),
                DropdownButton<String>(
                  value: format,
                  items: const [DropdownMenuItem(value: 'mkpx', child: Text('.mkpx')), DropdownMenuItem(value: 'gif', child: Text('GIF')), DropdownMenuItem(value: 'png', child: Text('PNG'))],
                  onChanged: (v) => setS(() => format = v!),
                ),
                const Spacer(),
                DropdownButton<String>(
                  value: visibility,
                  items: const [DropdownMenuItem(value: 'public', child: Text('Public')), DropdownMenuItem(value: 'unlisted', child: Text('Unlisted')), DropdownMenuItem(value: 'private', child: Text('Private'))],
                  onChanged: (v) => setS(() => visibility = v!),
                ),
              ]),
              const Divider(),
              TextField(decoration: const InputDecoration(labelText: 'Server base URL'), controller: TextEditingController(text: _clubUrl), onChanged: (v) => _clubUrl = v),
              TextField(decoration: const InputDecoration(labelText: 'Bearer token'), obscureText: true, onChanged: (v) => _clubToken = v),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upload')),
          ],
        ),
      ),
    );
    if (go != true) return;

    final Uint8List data;
    final String filename;
    switch (format) {
      case 'gif':
        data = engine.exportGif();
        filename = 'art.gif';
        break;
      case 'png':
        data = engine.exportPng(engine.activeFrame);
        filename = 'art.png';
        break;
      default:
        data = engine.save();
        filename = 'art.mkpx';
    }
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$_clubUrl/api/v1/artifacts'));
      if (_clubToken.isNotEmpty) req.headers['Authorization'] = 'Bearer $_clubToken';
      req.fields['metadata'] = '{"title":"$title","tags":[${tags.split(',').where((t) => t.trim().isNotEmpty).map((t) => '"${t.trim()}"').join(',')}],"visibility":"$visibility"}';
      req.files.add(http.MultipartFile.fromBytes('file', data, filename: filename));
      final resp = await req.send().timeout(const Duration(seconds: 15));
      final body = await resp.stream.bytesToString();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _toast('Uploaded to Club (${data.length ~/ 1024} KiB): $body');
      } else {
        _toast('Club upload failed (${resp.statusCode})');
      }
    } catch (e) {
      _toast('Upload error: $e');
    }
  }

  Future<void> _exportPng() async {
    final path = await FilePicker.saveFile(fileName: 'frame_${engine.activeFrame + 1}.png', type: FileType.custom, allowedExtensions: ['png']);
    if (path == null) return;
    final bytes = engine.exportPng(engine.activeFrame);
    if (bytes.isEmpty) {
      _toast('Export failed');
      return;
    }
    await File(path).writeAsBytes(bytes);
    _toast('Exported PNG (${bytes.length ~/ 1024} KiB)');
  }

  Future<void> _exportGif() async {
    final path = await FilePicker.saveFile(fileName: 'animation.gif', type: FileType.custom, allowedExtensions: ['gif']);
    if (path == null) return;
    final bytes = engine.exportGif();
    if (bytes.isEmpty) {
      _toast('Export failed');
      return;
    }
    await File(path).writeAsBytes(bytes);
    _toast('Exported GIF (${engine.frameCount} frames, ${bytes.length ~/ 1024} KiB)');
  }

  Future<void> _resizeCanvasDialog() async {
    double w = engine.width.toDouble();
    double h = engine.height.toDouble();
    bool center = true;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Resize canvas'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [const SizedBox(width: 20, child: Text('W')), Expanded(child: Slider(value: w.clamp(8, 256), min: 8, max: 256, divisions: 248, label: '${w.toInt()}', onChanged: (v) => setS(() => w = v))), SizedBox(width: 36, child: Text('${w.toInt()}'))]),
            Row(children: [const SizedBox(width: 20, child: Text('H')), Expanded(child: Slider(value: h.clamp(8, 256), min: 8, max: 256, divisions: 248, label: '${h.toInt()}', onChanged: (v) => setS(() => h = v))), SizedBox(width: 36, child: Text('${h.toInt()}'))]),
            SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Anchor center'), subtitle: const Text('(off = top-left)', style: TextStyle(fontSize: 11)), value: center, onChanged: (v) => setS(() => center = v)),
            Wrap(spacing: 6, children: [for (final p in [16, 32, 48, 64, 128, 256]) ActionChip(label: Text('$p²'), onPressed: () => setS(() { w = p.toDouble(); h = p.toDouble(); }))]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () { _act('ResizeCanvas(${w.toInt()}, ${h.toInt()}, $center)'); Navigator.pop(ctx); }, child: const Text('Resize')),
          ],
        ),
      ),
    );
  }

  Future<void> _editDuration() async {
    final frames = (_state['frame_detail'] as List?);
    int curUs = 100000;
    if (frames != null && engine.activeFrame < frames.length) {
      curUs = frames[engine.activeFrame]['duration_us'] ?? 100000;
    }
    double ms = curUs / 1000.0;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Frame ${engine.activeFrame + 1} duration'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${ms.toStringAsFixed(1)} ms  (${(1000 / ms).toStringAsFixed(1)} fps)'),
            Slider(value: ms.clamp(16.6, 1000), min: 16.6, max: 1000, onChanged: (v) => setS(() => ms = v)),
            Wrap(spacing: 6, children: [
              for (final f in [60, 30, 24, 12, 8])
                ActionChip(label: Text('${f}fps'), onPressed: () => setS(() => ms = 1000 / f)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
                onPressed: () {
                  _act('SetFrameDuration(${engine.activeFrame}, ${ms.toStringAsFixed(2)})');
                  Navigator.pop(ctx);
                },
                child: const Text('This frame')),
            FilledButton(
                onPressed: () {
                  _act('SetAllDurations(${ms.toStringAsFixed(2)})');
                  Navigator.pop(ctx);
                },
                child: const Text('All frames')),
          ],
        ),
      ),
    );
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
  }

  Future<void> _pickColor({required Color initial, required ValueChanged<Color> onPick}) async {
    final c = await showDialog<Color>(context: context, builder: (_) => ColorPickerDialog(initial: initial));
    if (c != null) onPick(c);
  }

  @override
  Widget build(BuildContext context) {
    if (!_engineReady) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
                'Engine load failed:\n$_error\n\nBuild the DLL with:\n  cargo build -p makapix-ffi --release',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final layers = _layerList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(children: [
          const Text('Makapix', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Text('${engine.width}×${engine.height}', style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ]),
        actions: [
          IconButton(tooltip: 'New', onPressed: _newDialog, icon: const Icon(Icons.insert_drive_file_outlined)),
          IconButton(tooltip: 'Open', onPressed: _open, icon: const Icon(Icons.folder_open)),
          IconButton(tooltip: 'Save', onPressed: _save, icon: const Icon(Icons.save)),
          PopupMenuButton<String>(
            tooltip: 'Import / Export',
            icon: const Icon(Icons.import_export),
            onSelected: (v) {
              if (v == 'import') _importImage();
              if (v == 'png') _exportPng();
              if (v == 'gif') _exportGif();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Import image…')),
              PopupMenuItem(value: 'png', child: Text('Export frame as PNG…')),
              PopupMenuItem(value: 'gif', child: Text('Export animation as GIF…')),
            ],
          ),
          IconButton(tooltip: 'Upload to Makapix Club', onPressed: _uploadToClub, icon: const Icon(Icons.cloud_upload_outlined)),
          const SizedBox(width: 8),
          IconButton(
              tooltip: 'Undo',
              onPressed: (_state['can_undo'] == true) ? () => _act('Undo()') : null,
              icon: const Icon(Icons.undo)),
          IconButton(
              tooltip: 'Redo',
              onPressed: (_state['can_redo'] == true) ? () => _act('Redo()') : null,
              icon: const Icon(Icons.redo)),
          const SizedBox(width: 8),
          IconButton(
              tooltip: _playing ? 'Pause' : 'Play',
              onPressed: _playing ? _pause : _play,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow)),
          IconButton(
              tooltip: 'Onion skin',
              onPressed: () {
                setState(() => _onion = !_onion);
                _redraw();
              },
              icon: Icon(Icons.layers, color: _onion ? Colors.amber : null)),
          IconButton(
              tooltip: 'Grid',
              onPressed: () {
                setState(() => _grid = !_grid);
                _redraw();
              },
              icon: Icon(Icons.grid_on, color: _grid ? Colors.amber : null)),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 1000; // tablet / desktop → side panel
        Widget panelLabel(String s) => Container(
              width: double.infinity,
              color: const Color(0xFF141619),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(s, style: const TextStyle(fontSize: 10, color: Colors.white38)),
            );
        final belowFilmRoll = wide
            ? Row(children: [
                Expanded(child: _buildCanvas()),
                Container(width: 1, color: Colors.black26),
                SizedBox(
                  width: 300,
                  child: Column(children: [
                    panelLabel('LAYERS'),
                    _buildLayers(layers),
                    const Expanded(child: ColoredBox(color: Color(0xFF1A1C1F))),
                  ]),
                ),
              ])
            : Column(children: [
                Expanded(child: _buildCanvas()),
                _buildLayers(layers),
              ]);
        return Column(
          children: [
            _buildFilmRoll(), // film-roll of frame previews at the top of the canvas area
            Expanded(child: belowFilmRoll),
            const Divider(height: 1),
            _buildToolOptions(),
            _buildPalette(),
            _buildToolBar(),
            _buildTooltipBand(context),
          ],
        );
      }),
    );
  }

  // Non-interactive help band at the very bottom. It moves the tool buttons up and out of
  // Android's bottom swipe-to-switch-app gesture zone, and teaches the current tool.
  Widget _buildTooltipBand(BuildContext context) {
    // Reserve the system gesture inset (min 16) as empty space below the text so the
    // Android swipe-up-to-switch-app gesture isn't blocked by tool buttons.
    final inset = MediaQuery.of(context).viewPadding.bottom;
    final gesturePad = inset < 16 ? 16.0 : inset;
    final tip = toolTips[_tool] ?? '';
    final icon = tools.firstWhere((t) => t.dsl == _tool, orElse: () => tools.first).icon;
    // FIXED height = exactly two text lines + top padding + the reserved gesture pad, so the
    // band never changes height (no reflow of the rest of the screen).
    const lineH = 13.75; // 11px * 1.25
    final bandHeight = 6 + lineH * 2 + 6 + gesturePad;
    return Container(
      width: double.infinity,
      height: bandHeight,
      color: const Color(0xFF0E1012),
      padding: EdgeInsets.fromLTRB(12, 6, 12, gesturePad),
      alignment: Alignment.topLeft,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: const Color(0xFF6DAA2C)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            tip,
            style: const TextStyle(fontSize: 11, color: Colors.white60, height: 1.25),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(builder: (context, c) {
      final box = Size(c.maxWidth, c.maxHeight);
      return Container(
        color: const Color(0xFF222428),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (_isPrecision) {
              _lastTouch = e.localPosition;
              _accX = 0;
              _accY = 0;
              return; // precision: drag moves the reticle, drawing is via buttons
            }
            final p = _toCanvas(e.localPosition, box, engine.width, engine.height);
            _send('PointerDown(${p.dx.toInt()},${p.dy.toInt()})');
            _redraw();
          },
          onPointerMove: (e) {
            if (_isPrecision) {
              final last = _lastTouch ?? e.localPosition;
              final r = _fittedRect(box, engine.width, engine.height);
              final scale = r.width / engine.width;
              _accX += (e.localPosition.dx - last.dx) / scale;
              _accY += (e.localPosition.dy - last.dy) / scale;
              _lastTouch = e.localPosition;
              final mx = _accX.truncate();
              final my = _accY.truncate();
              if (mx != 0 || my != 0) {
                _accX -= mx;
                _accY -= my;
                _send('MoveCursor($mx,$my)');
                _redraw();
              }
              return;
            }
            final p = _toCanvas(e.localPosition, box, engine.width, engine.height);
            _send('PointerMove(${p.dx.toInt()},${p.dy.toInt()})');
            _redraw();
          },
          onPointerUp: (e) {
            if (_isPrecision) {
              _lastTouch = null;
              if (_penDown) _refreshState();
              return;
            }
            _send('PointerUp()');
            _refreshState();
            _redraw();
            setState(() {});
          },
          child: Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: _CanvasPainter(_image), size: Size.infinite),
            CustomPaint(painter: _OutlinePainter(_outlineEdges, engine.width, engine.height, _antCtrl), size: Size.infinite),
          ]),
        ),
      );
    });
  }

  (int, int) _thumbSize() {
    final w = engine.width, h = engine.height;
    const maxSide = 64;
    if (w >= h) {
      final t = (maxSide * h / w).round().clamp(1, maxSide).toInt();
      return (maxSide, t);
    }
    final t = (maxSide * w / h).round().clamp(1, maxSide).toInt();
    return (t, maxSide);
  }

  Future<void> _genFrameThumb(int i, int hash) async {
    if (_thumbInFlight.contains(i)) return;
    _thumbInFlight.add(i);
    final (tw, th) = _thumbSize();
    final bytes = engine.frameThumb(i, tw, th);
    if (bytes.length < tw * th * 4) {
      _thumbInFlight.remove(i);
      return;
    }
    final img = await _decode(bytes, tw, th);
    _thumbInFlight.remove(i);
    if (!mounted) {
      img.dispose();
      return;
    }
    _frameThumbs[i]?.img.dispose();
    _frameThumbs[i] = _Thumb(hash, img);
    if (_frameThumbs.length > 80) {
      final victim = _frameThumbs.keys.firstWhere((k) => k != engine.activeFrame, orElse: () => -1);
      if (victim >= 0) _frameThumbs.remove(victim)?.img.dispose();
    }
    setState(() {});
  }

  // Horizontal "film roll" of frame thumbnails at the top of the canvas area.
  Widget _buildFilmRoll() {
    final count = engine.frameCount;
    final active = engine.activeFrame;
    final (tw, th) = _thumbSize();
    final tileW = (46.0 * tw / th).clamp(28.0, 84.0);
    return Container(
      height: 70,
      color: const Color(0xFF15171A),
      child: Row(children: [
        IconButton(iconSize: 20, tooltip: 'Add frame', onPressed: () => _act('AddFrame()'), icon: const Icon(Icons.add_box)),
        Container(width: 1, color: Colors.black26),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemBuilder: (_, i) {
              final hash = engine.frameHash(i);
              final cached = _frameThumbs[i];
              if (cached == null || cached.hash != hash) _genFrameThumb(i, hash);
              final sel = i == active;
              return GestureDetector(
                onTap: () => _act('SetActiveFrame($i)'),
                onLongPress: () => _frameMenu(i),
                child: Container(
                  width: tileW + 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101214),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: sel ? const Color(0xFF4080C0) : Colors.black26, width: sel ? 2 : 1),
                  ),
                  child: Column(children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.all(2),
                        color: const Color(0xFF3A3D42),
                        alignment: Alignment.center,
                        child: cached != null
                            ? RawImage(image: cached.img, fit: BoxFit.contain, filterQuality: FilterQuality.none)
                            : const SizedBox.shrink(),
                      ),
                    ),
                    Text('${i + 1}', style: TextStyle(fontSize: 9, color: sel ? Colors.white : Colors.white54)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  void _frameMenu(int i) {
    final count = engine.frameCount;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(dense: true, title: Text('Frame ${i + 1} of $count', style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(leading: const Icon(Icons.copy), title: const Text('Duplicate'), onTap: () { Navigator.pop(ctx); _act('DuplicateFrame($i)'); }),
          ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Duration…'), onTap: () { Navigator.pop(ctx); _act('SetActiveFrame($i)'); _editDuration(); }),
          ListTile(leading: const Icon(Icons.chevron_left), title: const Text('Move left'), enabled: i > 0, onTap: () { Navigator.pop(ctx); _act('ReorderFrame($i, ${i - 1})'); }),
          ListTile(leading: const Icon(Icons.chevron_right), title: const Text('Move right'), enabled: i + 1 < count, onTap: () { Navigator.pop(ctx); _act('ReorderFrame($i, ${i + 1})'); }),
          ListTile(leading: const Icon(Icons.delete, color: Colors.redAccent), title: const Text('Delete'), enabled: count > 1, onTap: () { Navigator.pop(ctx); _act('RemoveFrame($i)'); }),
        ]),
      ),
    );
  }

  List<dynamic> _layerList() {
    final frames = (_state['frame_detail'] as List?) ?? [];
    final active = engine.activeFrame;
    if (active < frames.length) {
      return (frames[active]['layers'] as List?) ?? [];
    }
    return [];
  }

  void _nudgeGroup(int dx, int dy) {
    if (_selLayers.length > 1) {
      _send('SetActiveLayers(${_selLayers.join(",")})');
    }
    _act('NudgeLayers($dx,$dy)');
  }

  void _layerOptions(int i, Map<String, dynamic> l, int count) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        int opacity = l['opacity'] ?? 255;
        bool locked = l['locked'] ?? false;
        bool inGroup = _selLayers.contains(i);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${l['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                const Text('Opacity'),
                Expanded(child: Slider(value: opacity.toDouble(), max: 255, onChanged: (v) { setS(() => opacity = v.round()); _send('SetLayerOpacity($i, $opacity)'); _redraw(); })),
                Text('$opacity'),
              ]),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Locked'), value: locked, onChanged: (v) { setS(() => locked = v); _act('SetLayerLocked($i, $v)'); }),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('In move group'), value: inGroup, onChanged: (v) { setS(() { if (v) { _selLayers.add(i); } else { _selLayers.remove(i); } }); setState(() {}); }),
              Wrap(spacing: 8, children: [
                ActionChip(avatar: const Icon(Icons.arrow_upward, size: 16), label: const Text('Up'), onPressed: i + 1 < count ? () { Navigator.pop(ctx); _act('ReorderLayer($i, ${i + 1})'); } : null),
                ActionChip(avatar: const Icon(Icons.arrow_downward, size: 16), label: const Text('Down'), onPressed: i > 0 ? () { Navigator.pop(ctx); _act('ReorderLayer($i, ${i - 1})'); } : null),
                ActionChip(avatar: const Icon(Icons.dynamic_feed, size: 16), label: const Text('Copy to all frames'), onPressed: () {
                  Navigator.pop(ctx);
                  final all = List.generate(engine.frameCount, (k) => k).where((k) => k != engine.activeFrame).join(',');
                  if (all.isNotEmpty) _act('SetActiveLayer($i); DuplicateLayerToFrames($all)');
                }),
                ActionChip(avatar: const Icon(Icons.delete, size: 16), label: const Text('Delete'), onPressed: count > 1 ? () { Navigator.pop(ctx); _act('RemoveLayer($i)'); } : null),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  Widget _buildLayers(List<dynamic> layers) {
    final frames = (_state['frame_detail'] as List?);
    int activeLayer = 0;
    if (frames != null && engine.activeFrame < frames.length) {
      activeLayer = frames[engine.activeFrame]['active_layer'] ?? 0;
    }
    return Container(
      height: 46,
      color: const Color(0xFF1A1C1F),
      child: Row(children: [
        IconButton(iconSize: 18, tooltip: 'Add layer', onPressed: () => _act('AddLayer()'), icon: const Icon(Icons.add)),
        IconButton(iconSize: 18, tooltip: 'Duplicate layer', onPressed: () => _act('DuplicateLayer($activeLayer)'), icon: const Icon(Icons.control_point_duplicate)),
        // nudge pad (moves active layer, or the move-group if >1 selected)
        IconButton(iconSize: 16, tooltip: 'Nudge left', onPressed: () => _nudgeGroup(-1, 0), icon: const Icon(Icons.chevron_left)),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          InkWell(onTap: () => _nudgeGroup(0, -1), child: const Icon(Icons.keyboard_arrow_up, size: 16)),
          InkWell(onTap: () => _nudgeGroup(0, 1), child: const Icon(Icons.keyboard_arrow_down, size: 16)),
        ]),
        IconButton(iconSize: 16, tooltip: 'Nudge right', onPressed: () => _nudgeGroup(1, 0), icon: const Icon(Icons.chevron_right)),
        const SizedBox(width: 2),
        Expanded(
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            itemCount: layers.length,
            onReorder: (oldI, newI) {
              if (newI > oldI) newI -= 1;
              _act('ReorderLayer($oldI, $newI)');
            },
            itemBuilder: (_, i) {
              final l = layers[i] as Map<String, dynamic>;
              final sel = i == activeLayer;
              final inGroup = _selLayers.contains(i);
              return ReorderableDelayedDragStartListener(
                key: ValueKey('layer_$i'),
                index: i,
                child: GestureDetector(
                  onTap: () { setState(() => _selLayers.clear()); _act('SetActiveLayer($i)'); },
                  onLongPress: () => _layerOptions(i, l, layers.length),
                  child: Container(
                    width: 96,
                    margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF34506A) : const Color(0xFF2A2D31),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: inGroup ? Colors.amber : (sel ? const Color(0xFF4080C0) : Colors.transparent)),
                    ),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => _act('SetLayerVisible($i, ${!(l['visible'] as bool)})'),
                        child: Icon(l['visible'] == true ? Icons.visibility : Icons.visibility_off, size: 15),
                      ),
                      if (l['locked'] == true) const Padding(padding: EdgeInsets.only(left: 2), child: Icon(Icons.lock, size: 12, color: Colors.white38)),
                      const SizedBox(width: 4),
                      Expanded(child: Text('${l['name']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildToolOptions() {
    final children = <Widget>[];
    void label(String s) => children.add(Padding(
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Text(s, style: const TextStyle(fontSize: 11, color: Colors.white60))));

    if (_isPrecision) {
      // reticle nudge pad
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge left', onPressed: () { _send('MoveCursor(-1,0)'); _redraw(); }, icon: const Icon(Icons.chevron_left)));
      children.add(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        InkWell(onTap: () { _send('MoveCursor(0,-1)'); _redraw(); }, child: const Icon(Icons.keyboard_arrow_up, size: 18)),
        InkWell(onTap: () { _send('MoveCursor(0,1)'); _redraw(); }, child: const Icon(Icons.keyboard_arrow_down, size: 18)),
      ]));
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge right', onPressed: () { _send('MoveCursor(1,0)'); _redraw(); }, icon: const Icon(Icons.chevron_right)));
      children.add(const SizedBox(width: 4));
      // DRAW (single dot)
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 34), backgroundColor: const Color(0xFF4080C0)),
          onPressed: () { _send('PlotCursor()'); _refreshState(); _redraw(); setState(() {}); },
          icon: const Icon(Icons.brush, size: 16),
          label: const Text('Draw'),
        ),
      ));
      // PEN toggle (continuous line while dragging the reticle)
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _penDown,
          label: Text(_penDown ? 'Pen ✔' : 'Pen'),
          selectedColor: const Color(0xFF30A050),
          onSelected: (v) {
            setState(() => _penDown = v);
            _send(v ? 'CursorPenDown()' : 'CursorPenUp()');
            _refreshState();
            _redraw();
          },
        ),
      ));
    }

    final sizeTools = {'Pencil', 'PrecisionPencil', 'Brush', 'Airbrush', 'Eraser', 'Dodge', 'Burn', 'Line', 'Rectangle', 'Ellipse'};
    if (sizeTools.contains(_tool)) {
      label('Size $_brushSize');
      children.add(_slider(_brushSize.toDouble(), 1, 32, (v) {
        setState(() => _brushSize = v.round());
        _send('SetBrushSize($_brushSize)');
      }));
      label('Shape');
      children.add(_toggle(['Round', 'Square'], _round ? 0 : 1, (i) {
        setState(() => _round = i == 0);
        _send('SetBrushShape(${_round ? 'Round' : 'Square'})');
      }));
    }
    if (_tool == 'Airbrush' || _tool == 'Dodge' || _tool == 'Burn') {
      label('Intensity $_intensity');
      children.add(_slider(_intensity.toDouble(), 1, 255, (v) {
        setState(() => _intensity = v.round());
        _send('SetIntensity($_intensity)');
      }));
    }
    if (_tool == 'Bucket' || _tool == 'SelectByColor') {
      label('Threshold $_threshold');
      children.add(_slider(_threshold.toDouble(), 0, 255, (v) {
        setState(() => _threshold = v.round());
        _send('SetThreshold($_threshold)');
      }));
      children.add(_toggle(['Contiguous', 'Global'], _contiguous ? 0 : 1, (i) {
        setState(() => _contiguous = i == 0);
        _send('SetContiguous($_contiguous)');
      }));
    }
    if (_tool == 'Rectangle' || _tool == 'Ellipse') {
      children.add(_toggle(['Fill', 'Outline'], _shapeFill ? 0 : 1, (i) {
        setState(() => _shapeFill = i == 0);
        _send('SetShapeFill($_shapeFill)');
      }));
    }
    if (_tool == 'Gradient') {
      children.add(_toggle(['Linear', 'Radial'], _radial ? 1 : 0, (i) {
        setState(() => _radial = i == 1);
        _send('SetGradientType(${_radial ? 'Radial' : 'Linear'})');
      }));
      children.add(_swatchButton(_gradA, () => _pickColor(initial: _gradA, onPick: (c) {
            setState(() => _gradA = c);
            _send('SetGradientStops([${_hex(_gradA)}@0, ${_hex(_gradB)}@1])');
          })));
      children.add(_swatchButton(_gradB, () => _pickColor(initial: _gradB, onPick: (c) {
            setState(() => _gradB = c);
            _send('SetGradientStops([${_hex(_gradA)}@0, ${_hex(_gradB)}@1])');
          })));
    }
    if (_tool.startsWith('Select')) {
      children.add(_toggle(['Replace', 'Add', 'Subtract', 'Intersect'],
          ['Replace', 'Add', 'Subtract', 'Intersect'].indexOf(_selMode), (i) {
        setState(() => _selMode = ['Replace', 'Add', 'Subtract', 'Intersect'][i]);
        _send('SetSelectionMode($_selMode)');
      }));
      children.add(_miniBtn('All', () => _act('SelectAll()')));
      children.add(_miniBtn('None', () => _act('SelectNone()')));
      children.add(_miniBtn('Invert', () => _act('InvertSelection()')));
      children.add(_miniBtn('Fill', () => _act('FillSelection()')));
      children.add(_miniBtn('Clear', () => _act('ClearSelection()')));
      children.add(_miniBtn('Copy', () => _act('Copy()')));
      children.add(_miniBtn('Cut', () => _act('Cut()')));
      children.add(_miniBtn('Paste', () => _act('Paste()')));
    }
    if (_tool == 'HsvShift') {
      label('H ${_hsvH.toInt()}');
      children.add(_slider(_hsvH, -180, 180, (v) => setState(() => _hsvH = v)));
      label('S ${_hsvS.toStringAsFixed(1)}');
      children.add(_slider(_hsvS, -1, 1, (v) => setState(() => _hsvS = v)));
      label('V ${_hsvV.toStringAsFixed(1)}');
      children.add(_slider(_hsvV, -1, 1, (v) => setState(() => _hsvV = v)));
      children.add(_miniBtn('Apply', () {
        _send('SetHsvShift($_hsvH, $_hsvS, $_hsvV)');
        _act('ApplyHsvShift()');
      }));
    }
    children.add(_miniBtn('Flip H', () => _act('FlipH()')));
    children.add(_miniBtn('Flip V', () => _act('FlipV()')));
    children.add(_miniBtn('Invert', () => _act('Invert()')));
    children.add(const SizedBox(width: 6));
    children.add(IconButton(iconSize: 18, tooltip: 'Rotate 90° CW', onPressed: () => _act('Rotate(1)'), icon: const Icon(Icons.rotate_right)));
    children.add(IconButton(iconSize: 18, tooltip: 'Rotate 90° CCW', onPressed: () => _act('Rotate(3)'), icon: const Icon(Icons.rotate_left)));
    children.add(_miniBtn('Rotate 180', () => _act('Rotate(2)')));
    children.add(_miniBtn('Crop→Sel', () => _act('CropToSelection()')));
    children.add(_miniBtn('Resize…', _resizeCanvasDialog));

    return Container(
      height: 48,
      color: const Color(0xFF202327),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [const SizedBox(width: 4), ...children, const SizedBox(width: 8)]),
      ),
    );
  }

  Widget _buildPalette() {
    final names = (_state['palette_names'] as List?)?.cast<String>() ?? ['Default'];
    final active = (_state['active_palette'] as int?) ?? 0;
    return Container(
      color: const Color(0xFF1C1F22),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // header: palette selector + manage
        SizedBox(
          height: 30,
          child: Row(children: [
            const SizedBox(width: 6),
            const Icon(Icons.palette, size: 15, color: Colors.white54),
            const SizedBox(width: 4),
            DropdownButton<int>(
              value: active < names.length ? active : 0,
              isDense: true,
              underline: const SizedBox(),
              style: const TextStyle(fontSize: 12, color: Colors.white),
              dropdownColor: const Color(0xFF26292E),
              items: [for (var i = 0; i < names.length; i++) DropdownMenuItem(value: i, child: Text(names[i]))],
              onChanged: (v) => _act('SetActivePalette($v)'),
            ),
            IconButton(iconSize: 16, tooltip: 'New palette', onPressed: _newPalette, icon: const Icon(Icons.add_box_outlined)),
            IconButton(iconSize: 16, tooltip: 'Save palette', onPressed: _savePalette, icon: const Icon(Icons.save_alt)),
            IconButton(iconSize: 16, tooltip: 'Load palette (.json/.gpl)', onPressed: _loadPalette, icon: const Icon(Icons.file_download_outlined)),
          ]),
        ),
        // swatches
        SizedBox(
          height: 42,
          child: Row(children: [
            GestureDetector(
              onTap: () => _pickColor(initial: _primary, onPick: _setPrimary),
              child: Container(
                width: 32, height: 32, margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white70, width: 2)),
                child: const Icon(Icons.edit, size: 13, color: Colors.white70),
              ),
            ),
            IconButton(iconSize: 18, tooltip: 'Add current color', onPressed: () => _act('AddPaletteColor(${_hex(_primary)})'), icon: const Icon(Icons.add_circle_outline)),
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _palette.length,
                itemBuilder: (_, i) {
                  final c = _palette[i];
                  return GestureDetector(
                    onTap: () => _setPrimary(c),
                    onLongPress: () => _paletteSwatchMenu(i, c),
                    child: Container(
                      width: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.black26)),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  void _paletteSwatchMenu(int i, Color c) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit), title: const Text('Edit color'), onTap: () {
            Navigator.pop(ctx);
            _pickColor(initial: c, onPick: (nc) => _act('EditPaletteColor($i, ${_hex(nc)})'));
          }),
          ListTile(leading: const Icon(Icons.copy), title: const Text('Duplicate'), onTap: () { Navigator.pop(ctx); _act('DuplicatePaletteColor($i)'); }),
          ListTile(leading: const Icon(Icons.delete), title: const Text('Remove'), onTap: () { Navigator.pop(ctx); _act('RemovePaletteColor($i)'); }),
        ]),
      ),
    );
  }

  Future<void> _newPalette() async {
    final ctrl = TextEditingController(text: 'Palette');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New palette'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) _act('NewPalette(${name.trim()})');
  }

  Future<void> _savePalette() async {
    final path = await FilePicker.saveFile(fileName: 'palette.gpl', type: FileType.custom, allowedExtensions: ['gpl', 'json']);
    if (path == null) return;
    final names = (_state['palette_names'] as List?)?.cast<String>() ?? ['Palette'];
    final active = (_state['active_palette'] as int?) ?? 0;
    final pname = active < names.length ? names[active] : 'Palette';
    final sb = StringBuffer('GIMP Palette\nName: $pname\nColumns: 0\n#\n');
    for (final c in _palette) {
      sb.writeln('${c.red}\t${c.green}\t${c.blue}\t${_hex(c)}');
    }
    await File(path).writeAsString(sb.toString());
    _toast('Saved palette (${_palette.length} colors)');
  }

  Future<void> _loadPalette() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['gpl', 'json', 'txt']);
    if (res == null || res.files.single.path == null) return;
    final text = await File(res.files.single.path!).readAsString();
    final colors = _parsePalette(text);
    if (colors.isEmpty) {
      _toast('No colors found');
      return;
    }
    _send('NewPalette(${res.files.single.name.split('.').first})');
    for (final c in colors) {
      _send('AddPaletteColor(${_hex(c)})');
    }
    _refreshState();
    setState(() {});
    _toast('Loaded ${colors.length} colors');
  }

  List<Color> _parsePalette(String text) {
    final out = <Color>[];
    // try JSON array of hex strings
    final t = text.trim();
    if (t.startsWith('[')) {
      try {
        for (final h in (json.decode(t) as List)) {
          out.add(_parseHex(h.toString()));
        }
        return out;
      } catch (_) {}
    }
    // GIMP .gpl: lines of "R G B  name"
    for (final line in text.split('\n')) {
      final l = line.trim();
      if (l.isEmpty || l.startsWith('#') || l.startsWith('GIMP') || l.startsWith('Name:') || l.startsWith('Columns:')) continue;
      final parts = l.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final r = int.tryParse(parts[0]), g = int.tryParse(parts[1]), b = int.tryParse(parts[2]);
        if (r != null && g != null && b != null) out.add(Color.fromARGB(255, r, g, b));
      }
    }
    return out;
  }

  // The static visual of a tool tile (icon + label, highlighted when selected/hovered).
  Widget _tileVisual(ToolDef t, {required bool selected, bool hover = false}) {
    return Container(
      width: 54,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF4080C0) : const Color(0xFF26292E),
        borderRadius: BorderRadius.circular(6),
        border: hover ? Border.all(color: Colors.amber, width: 2) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(t.icon, size: 18, color: selected ? Colors.white : Colors.white70),
          const SizedBox(height: 1),
          Text(t.label, style: const TextStyle(fontSize: 8.5), maxLines: 1, overflow: TextOverflow.clip),
        ],
      ),
    );
  }

  Widget _toolTile(int index) {
    final dsl = _toolOrder[index];
    final t = _toolDef(dsl);
    final selected = dsl == _tool;
    if (!_reorderMode) {
      return GestureDetector(onTap: () => _selectTool(dsl), child: _tileVisual(t, selected: selected));
    }
    // reorder mode: draggable + drop target, with ◀ ▶ one-slot buttons overlaid
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => _reorderTool(d.data, index),
      builder: (ctx, cand, rej) {
        return LongPressDraggable<int>(
          data: index,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(color: Colors.transparent, child: _tileVisual(t, selected: true)),
          childWhenDragging: Opacity(opacity: 0.3, child: _tileVisual(t, selected: selected)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _tileVisual(t, selected: selected, hover: cand.isNotEmpty),
              Positioned(
                left: 0,
                top: 0,
                child: InkWell(
                  onTap: () => _moveTool(index, -1),
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: const BoxDecoration(color: Color(0xCC000000), shape: BoxShape.circle),
                    child: const Icon(Icons.chevron_left, size: 15, color: Colors.amber),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: InkWell(
                  onTap: () => _moveTool(index, 1),
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: const BoxDecoration(color: Color(0xCC000000), shape: BoxShape.circle),
                    child: const Icon(Icons.chevron_right, size: 15, color: Colors.amber),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolBar() {
    final n = _toolOrder.length;
    final cols = (n + 1) ~/ 2; // top row holds the first half (row-major)
    final top = [for (var i = 0; i < cols; i++) _toolTile(i)];
    final bottom = [for (var i = cols; i < n; i++) _toolTile(i)];
    return Container(
      height: 100,
      color: const Color(0xFF15171A),
      child: Row(children: [
        // fixed leading control: toggle reorder mode (+ reset while reordering)
        SizedBox(
          width: 40,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              iconSize: 22,
              padding: EdgeInsets.zero,
              tooltip: _reorderMode ? 'Done' : 'Rearrange tools',
              onPressed: () => setState(() => _reorderMode = !_reorderMode),
              icon: Icon(_reorderMode ? Icons.check_circle : Icons.dashboard_customize,
                  color: _reorderMode ? const Color(0xFF30A050) : Colors.white70),
            ),
            if (_reorderMode)
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                tooltip: 'Reset to default order',
                onPressed: _resetToolOrder,
                icon: const Icon(Icons.restart_alt, color: Colors.white54),
              ),
          ]),
        ),
        Container(width: 1, color: Colors.black26),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: top),
              Row(children: bottom),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _slider(double v, double min, double max, ValueChanged<double> onChanged) {
    return SizedBox(
      width: 120,
      child: Slider(value: v.clamp(min, max), min: min, max: max, onChanged: onChanged),
    );
  }

  Widget _toggle(List<String> opts, int sel, ValueChanged<int> onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ToggleButtons(
        isSelected: List.generate(opts.length, (i) => i == sel),
        onPressed: onTap,
        constraints: const BoxConstraints(minHeight: 30, minWidth: 44),
        borderRadius: BorderRadius.circular(6),
        children: opts
            .map((o) => Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(o, style: const TextStyle(fontSize: 11))))
            .toList(),
      ),
    );
  }

  Widget _miniBtn(String s, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: const Color(0xFF2E3237),
        ),
        onPressed: onTap,
        child: Text(s, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _swatchButton(Color c, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white54))),
      ),
    );
  }

  Future<void> _newDialog() async {
    int w = 64, h = 64;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New document'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final preset in [16, 32, 48, 64, 128, 256])
            ListTile(
              dense: true,
              title: Text('$preset × $preset'),
              onTap: () {
                w = preset;
                h = preset;
                Navigator.pop(ctx, true);
              },
            ),
        ]),
      ),
    );
    if (ok == true) {
      _send('NewDocument($w,$h)');
      _send('SelectTool($_tool)');
      _refreshState();
      _redraw();
      setState(() {});
    }
  }
}

// A cached frame thumbnail tagged with the frame content hash it was generated from.
class _Thumb {
  final int hash;
  final ui.Image img;
  _Thumb(this.hash, this.img);
}

class _CanvasPainter extends CustomPainter {
  final ui.Image? image;
  _CanvasPainter(this.image);
  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;
    final iw = image!.width.toDouble(), ih = image!.height.toDouble();
    final scale = (size.width / iw) < (size.height / ih) ? (size.width / iw) : (size.height / ih);
    final dw = iw * scale, dh = ih * scale;
    final dst = Rect.fromLTWH((size.width - dw) / 2, (size.height - dh) / 2, dw, dh);
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    canvas.drawImageRect(image!, Rect.fromLTWH(0, 0, iw, ih), dst, paint);
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => old.image != image;
}

// Thin, animated marching-ants selection outline drawn in SCREEN space (so it stays a
// hairline regardless of how large the canvas pixels are scaled).
class _OutlinePainter extends CustomPainter {
  final List<List<int>> edges; // [x1,y1,x2,y2,t] in canvas-corner coords
  final int cw, ch;
  final Animation<double> anim;
  _OutlinePainter(this.edges, this.cw, this.ch, this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    if (edges.isEmpty || cw <= 0 || ch <= 0) return;
    final scale = (size.width / cw) < (size.height / ch) ? (size.width / cw) : (size.height / ch);
    final ox = (size.width - cw * scale) / 2;
    final oy = (size.height - ch * scale) / 2;
    final phase = (anim.value * 4).floor(); // 4-unit marching period
    final dark = <Offset>[];
    final light = <Offset>[];
    for (final e in edges) {
      final p1 = Offset(ox + e[0] * scale, oy + e[1] * scale);
      final p2 = Offset(ox + e[2] * scale, oy + e[3] * scale);
      if (((e[4] + phase) % 4) < 2) {
        dark..add(p1)..add(p2);
      } else {
        light..add(p1)..add(p2);
      }
    }
    final black = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.4
      ..isAntiAlias = false;
    final white = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4
      ..isAntiAlias = false;
    canvas.drawPoints(ui.PointMode.lines, dark, black);
    canvas.drawPoints(ui.PointMode.lines, light, white);
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => true; // driven by the animation
}

/// Interactive crop-rectangle picker over a source image. Returns the crop rect in
/// **source pixels** (SPEC §16.1).
class CropDialog extends StatefulWidget {
  final ui.Image image;
  const CropDialog({super.key, required this.image});
  @override
  State<CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<CropDialog> {
  late double scale;
  late double boxW, boxH;
  Offset? _start;
  Rect _disp = Rect.zero; // display-coordinate crop rect

  @override
  void initState() {
    super.initState();
    final w = widget.image.width.toDouble();
    final h = widget.image.height.toDouble();
    scale = (360 / w) < (360 / h) ? 360 / w : 360 / h;
    boxW = w * scale;
    boxH = h * scale;
    _disp = Rect.fromLTWH(0, 0, boxW, boxH); // default = whole image
  }

  Rect _toSource(Rect d) {
    final iw = widget.image.width.toDouble();
    final ih = widget.image.height.toDouble();
    return Rect.fromLTRB(
      (d.left / scale).clamp(0.0, iw),
      (d.top / scale).clamp(0.0, ih),
      (d.right / scale).clamp(0.0, iw),
      (d.bottom / scale).clamp(0.0, ih),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Drag to select crop area'),
      content: SizedBox(
        width: boxW,
        height: boxH,
        child: GestureDetector(
          onPanStart: (e) => setState(() => _start = e.localPosition),
          onPanUpdate: (e) {
            if (_start == null) return;
            final a = _start!;
            final b = e.localPosition;
            final left = (a.dx < b.dx ? a.dx : b.dx).clamp(0.0, boxW);
            final right = (a.dx < b.dx ? b.dx : a.dx).clamp(0.0, boxW);
            final top = (a.dy < b.dy ? a.dy : b.dy).clamp(0.0, boxH);
            final bottom = (a.dy < b.dy ? b.dy : a.dy).clamp(0.0, boxH);
            setState(() => _disp = Rect.fromLTRB(left, top, right, bottom));
          },
          child: CustomPaint(painter: _CropPainter(widget.image, _disp, boxW, boxH), size: Size(boxW, boxH)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: () {
              final s = _toSource(_disp);
              Navigator.pop(context, s.width < 1 || s.height < 1 ? null : s);
            },
            child: const Text('Use crop')),
      ],
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect crop;
  final double w, h;
  _CropPainter(this.image, this.crop, this.w, this.h);
  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(0, 0, w, h);
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.drawRect(dst, Paint()..color = const Color(0x99000000));
    if (crop.width > 0 && crop.height > 0) {
      final cs = Rect.fromLTRB(crop.left / w * image.width, crop.top / h * image.height, crop.right / w * image.width, crop.bottom / h * image.height);
      canvas.drawImageRect(image, cs, crop, Paint()..filterQuality = FilterQuality.medium);
      canvas.drawRect(crop, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.amber);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop;
}

class ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const ColorPickerDialog({super.key, required this.initial});
  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late double r, g, b, a;
  bool hsvMode = false;
  late double h, s, v;

  @override
  void initState() {
    super.initState();
    r = widget.initial.red.toDouble();
    g = widget.initial.green.toDouble();
    b = widget.initial.blue.toDouble();
    a = widget.initial.alpha.toDouble();
    final hsvC = HSVColor.fromColor(widget.initial);
    h = hsvC.hue;
    s = hsvC.saturation;
    v = hsvC.value;
  }

  Color get _color => hsvMode
      ? HSVColor.fromAHSV(a / 255, h, s, v).toColor()
      : Color.fromARGB(a.round(), r.round(), g.round(), b.round());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Text('Pick color'),
        const Spacer(),
        ToggleButtons(
          isSelected: [!hsvMode, hsvMode],
          onPressed: (i) => setState(() => hsvMode = i == 1),
          constraints: const BoxConstraints(minHeight: 28, minWidth: 44),
          children: const [Text('RGB'), Text('HSV')],
        ),
      ]),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: 40, decoration: BoxDecoration(color: _color, border: Border.all(color: Colors.white24))),
          const SizedBox(height: 10),
          if (!hsvMode) ...[
            _chan('R', r, 255, Colors.red, (x) => setState(() => r = x)),
            _chan('G', g, 255, Colors.green, (x) => setState(() => g = x)),
            _chan('B', b, 255, Colors.blue, (x) => setState(() => b = x)),
          ] else ...[
            _chan('H', h, 360, Colors.purple, (x) => setState(() => h = x)),
            _chan('S', s * 100, 100, Colors.teal, (x) => setState(() => s = x / 100)),
            _chan('V', v * 100, 100, Colors.amber, (x) => setState(() => v = x / 100)),
          ],
          _chan('A', a, 255, Colors.grey, (x) => setState(() => a = x)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('OK')),
      ],
    );
  }

  Widget _chan(String name, double val, double max, Color color, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 18, child: Text(name)),
      Expanded(child: Slider(value: val.clamp(0, max), max: max, activeColor: color, onChanged: onChanged)),
      SizedBox(width: 36, child: Text(val.round().toString(), textAlign: TextAlign.right)),
    ]);
  }
}
