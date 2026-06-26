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
  ToolDef('MoveLayer', Icons.control_camera, 'Move Lyr'),
  ToolDef('SelectRect', Icons.highlight_alt, 'Sel Rect'),
  ToolDef('SelectEllipse', Icons.lens_blur, 'Sel Oval'),
  ToolDef('SelectFree', Icons.gesture, 'Lasso'),
  ToolDef('SelectByColor', Icons.colorize_outlined, 'Sel Color'),
  ToolDef('HsvShift', Icons.palette, 'HSV'),
  // Transform actions: UI-only groups (no engine draw tool). Selecting one reveals its
  // action button(s) in row-1; the canvas is inert while one is selected.
  ToolDef('Flip', Icons.flip, 'Flip'),
  ToolDef('Rotate', Icons.rotate_90_degrees_cw, 'Rotate'),
  ToolDef('Invert', Icons.invert_colors, 'Invert'),
  ToolDef('Resize', Icons.aspect_ratio, 'Resize'),
];

// Succinct, teach-as-you-go help shown in the gesture-safe band at the bottom.
const toolTips = <String, String>{
  'Pencil': 'Drag to draw hard pixels in the primary colour.',
  'PrecisionPencil':
      'Drag to move the ✛ reticle off your finger; arrows nudge 1px. Tap DRAW for a dot, or turn PEN on and drag to draw a line.',
  'Brush': 'Drag to paint, blending onto existing pixels.',
  'Airbrush': 'Drag to aim the ◎ reticle off your finger; tap SPRAY for one burst. Set size & intensity.',
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
  'MoveLayer': 'Drag the canvas to move the active layer (or the move-group); arrows nudge 1px. Group layers via a layer\'s long-press menu.',
  'SelectRect': 'Drag to select a rectangle. Use Add/Subtract/Intersect modes.',
  'SelectEllipse': 'Drag to select an ellipse. Combine with Add/Subtract modes.',
  'SelectCircle': 'Drag from centre outward to select a circle.',
  'SelectPoly': 'Trace an outline; it closes into a selection on release.',
  'SelectFree': 'Lasso: trace around pixels to select them.',
  'SelectByColor': 'Tap to select similar-colour pixels. Threshold = tolerance.',
  'HsvShift': 'Shift Hue/Sat/Value of the selection. Set H/S/V, then Apply.',
  'Flip': 'Mirror the image — tap Flip H or Flip V.',
  'Rotate': 'Rotate the canvas 90° CW, 90° CCW, or 180°.',
  'Invert': 'Invert the colours of the image (or selection).',
  'Resize': 'Change the canvas dimensions.',
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
  final Set<int> _selLayers = {}; // layers grouped to move together with the Move-Layer tool
  String _clubUrl = 'http://localhost:8080';
  String _clubToken = '';
  // precision pencil / airbrush off-finger cursor
  bool _penDown = false;
  Offset? _lastTouch;
  double _accX = 0, _accY = 0;
  int _cursorX = 0, _cursorY = 0; // reticle position (canvas px), mirrored from the engine
  int? _eraserX, _eraserY; // eraser footprint centre (canvas px) during an active erase drag
  // multi-touch handling on the canvas: only the first finger drives a tool. Extra fingers are
  // ignored once the primary is actively drawing; a still 2/3-finger tap is an undo/redo gesture.
  final Set<int> _touches = {}; // pointer ids currently on the canvas
  int? _drawPointer; // the pointer that owns the in-progress draw (null = none/suspended)
  bool _gestureMode = false; // this touch session became a multi-finger gesture (drawing suspended)
  int _maxTouches = 0; // peak simultaneous fingers this session
  Duration? _sessionStart; // when the first finger landed (monotonic), for tap-duration timing
  double _primaryMoved = 0; // screen-px the primary finger has travelled (tap vs. draw)
  double _gestureMoved = 0; // screen-px moved during gesture mode (disqualifies a sloppy tap)
  final Stopwatch _touchClock = Stopwatch()..start();
  static const double _kDrawSlop = 10; // primary travel before a stroke counts as "real drawing"
  static const double _kGestureSlop = 18; // max finger travel still counted as a tap
  static const int _kTapMaxMs = 400; // max duration of a multi-finger tap
  // configurable bottom toolbar
  List<String> _toolOrder = tools.map((t) => t.dsl).toList();
  bool _reorderMode = false;
  static const _prefsKey = 'tool_order_v1';
  // film-roll frame thumbnails (cached, invalidated by per-frame content hash)
  final Map<int, _Thumb> _frameThumbs = {};
  final Set<int> _thumbInFlight = {};
  // layers film-strip thumbnails, keyed by (frame,layer) and invalidated by per-layer content hash
  final Map<int, _Thumb> _layerThumbs = {};
  final Set<int> _layerThumbInFlight = {};
  int _layerKey(int frame, int layer) => frame * 100000 + layer;

  bool get _isPrecision => _tool == 'PrecisionPencil';

  // UI-only action groups: selecting one reveals its row-1 buttons but does not change the
  // engine's draw tool, and the canvas is inert while one is active.
  static const _transformTools = {'Flip', 'Rotate', 'Invert', 'Resize'};
  bool get _isTransformTool => _transformTools.contains(_tool);

  // Off-finger "reticle" tools: dragging moves a cursor (drawn as a screen-space marching-ants
  // overlay) rather than the finger, and an action button effects one operation at a time.
  static const _cursorTools = {'PrecisionPencil', 'Airbrush'};
  bool get _isCursorTool => _cursorTools.contains(_tool);

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
    for (final t in _layerThumbs.values) {
      t.img.dispose();
    }
    _layerThumbs.clear();
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
    // While erasing, outline the eraser footprint at its current position so the user sees
    // exactly which pixels are being erased.
    if (_eraserX != null && _eraserY != null) {
      _appendBrushFootprint(edges, _eraserX!, _eraserY!);
    }
    _outlineEdges = edges;
  }

  // Append boundary segments outlining the configured brush footprint (size + Round/Square)
  // centred at (ex,ey), clipped to the canvas — mirrors the engine's stamp footprint so the
  // marching ants match exactly what a stamp at this position would cover.
  void _appendBrushFootprint(List<List<int>> edges, int ex, int ey) {
    final w = engine.width, h = engine.height;
    final size = _brushSize < 1 ? 1 : _brushSize;
    final radius = (size - 1) ~/ 2;
    final covered = <int>{};
    void add(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      covered.add(y * w + x);
    }
    if (_round) {
      if (size <= 1) {
        add(ex, ey);
      } else {
        final r = radius < 1 ? 1 : radius;
        for (var dy = -r; dy <= r; dy++) {
          for (var dx = -r; dx <= r; dx++) {
            if (dx * dx + dy * dy <= r * r) add(ex + dx, ey + dy);
          }
        }
      }
    } else {
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          add(ex + dx, ey + dy);
        }
      }
    }
    bool cov(int x, int y) => covered.contains(y * w + x) && x >= 0 && y >= 0 && x < w && y < h;
    for (final key in covered) {
      final x = key % w, y = key ~/ w;
      final t = x + y;
      if (!cov(x - 1, y)) edges.add([x, y, x, y + 1, t]);
      if (!cov(x + 1, y)) edges.add([x + 1, y, x + 1, y + 1, t]);
      if (!cov(x, y - 1)) edges.add([x, y, x + 1, y, t]);
      if (!cov(x, y + 1)) edges.add([x, y + 1, x + 1, y + 1, t]);
    }
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
    if (_transformTools.contains(t)) return; // UI-only action group: no engine tool change
    _send('SelectTool($t)');
    if (_cursorTools.contains(t)) {
      _setCursor(engine.width ~/ 2, engine.height ~/ 2);
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

  // Place the reticle at an absolute canvas pixel, mirroring the engine's clamping.
  void _setCursor(int x, int y) {
    _cursorX = x.clamp(0, engine.width - 1);
    _cursorY = y.clamp(0, engine.height - 1);
    _send('SetCursor($_cursorX,$_cursorY)');
  }

  // Move the reticle by a pixel delta. Uses MoveCursor so the engine still paints the precision
  // pen line while the pen is down; the local mirror clamps identically to stay in sync.
  void _moveCursor(int dx, int dy) {
    _cursorX = (_cursorX + dx).clamp(0, engine.width - 1);
    _cursorY = (_cursorY + dy).clamp(0, engine.height - 1);
    _send('MoveCursor($dx,$dy)');
  }

  void _nudgeCursor(int dx, int dy) {
    _moveCursor(dx, dy);
    _redraw();
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
      body: Column(
        children: [
          _buildFilmRoll(), // film-roll of frame previews at the top of the canvas area
          Expanded(child: _buildCanvas()),
          const Divider(height: 1),
          _buildLayers(layers), // layers film-strip, directly above the tool options
          _buildToolOptions(), // row-1
          _buildPalette(), // row-2
          _buildToolBar(), // row-3
          _buildTooltipBand(context),
        ],
      ),
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
            if (_isTransformTool) return; // transform action groups don't draw on the canvas
            final wasEmpty = _touches.isEmpty;
            _touches.add(e.pointer);
            if (wasEmpty) {
              // first finger: start a draw session
              _drawPointer = e.pointer;
              _gestureMode = false;
              _maxTouches = 1;
              _sessionStart = _touchClock.elapsed;
              _primaryMoved = 0;
              _gestureMoved = 0;
              _beginDraw(e.localPosition, box);
            } else {
              if (_touches.length > _maxTouches) _maxTouches = _touches.length;
              // A second/third finger landed. If the primary finger has barely moved it's a
              // multi-finger tap gesture: abort the nascent stroke and suspend drawing. Otherwise
              // the primary is actively drawing, so ignore the extra finger.
              if (!_gestureMode && _primaryMoved <= _kDrawSlop) {
                _gestureMode = true;
                _drawPointer = null;
                _cancelDraw();
              }
            }
          },
          onPointerMove: (e) {
            if (_isTransformTool) return;
            if (_gestureMode) {
              _gestureMoved += e.delta.distance;
              return;
            }
            if (e.pointer != _drawPointer) return; // ignore extra fingers while drawing
            _primaryMoved += e.delta.distance;
            _continueDraw(e.localPosition, box);
          },
          onPointerUp: (e) {
            if (_isTransformTool) return;
            _touches.remove(e.pointer);
            if (_gestureMode) {
              if (_touches.isEmpty) {
                _fireTapGesture();
                _resetTouchSession();
              }
              return;
            }
            if (e.pointer == _drawPointer) {
              _endDraw();
              _drawPointer = null;
            }
            if (_touches.isEmpty) _resetTouchSession();
          },
          onPointerCancel: (e) {
            if (_isTransformTool) return;
            _touches.remove(e.pointer);
            if (!_gestureMode && e.pointer == _drawPointer) {
              _cancelDraw(); // interrupted draw → roll back, leaving no stray mark
              _drawPointer = null;
            }
            if (_touches.isEmpty) _resetTouchSession();
          },
          child: Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: _CanvasPainter(_image), size: Size.infinite),
            CustomPaint(painter: _OutlinePainter(_outlineEdges, engine.width, engine.height, _antCtrl), size: Size.infinite),
            if (_isCursorTool)
              CustomPaint(
                painter: _ReticlePainter(_cursorX, _cursorY, engine.width, engine.height, _antCtrl),
                size: Size.infinite,
              ),
          ]),
        ),
      );
    });
  }

  // ---- single-pointer draw helpers (driven by the multi-touch state machine above) ----

  void _beginDraw(Offset pos, Size box) {
    if (_isCursorTool) {
      _lastTouch = pos;
      _accX = 0;
      _accY = 0;
      return; // off-finger: drag moves the reticle, acting is via buttons
    }
    final p = _toCanvas(pos, box, engine.width, engine.height);
    if (_tool == 'Eraser') {
      _eraserX = p.dx.toInt();
      _eraserY = p.dy.toInt();
    }
    _send('PointerDown(${p.dx.toInt()},${p.dy.toInt()})');
    _redraw();
  }

  void _continueDraw(Offset pos, Size box) {
    if (_isCursorTool) {
      final last = _lastTouch ?? pos;
      final r = _fittedRect(box, engine.width, engine.height);
      final scale = r.width / engine.width;
      _accX += (pos.dx - last.dx) / scale;
      _accY += (pos.dy - last.dy) / scale;
      _lastTouch = pos;
      final mx = _accX.truncate();
      final my = _accY.truncate();
      if (mx != 0 || my != 0) {
        _accX -= mx;
        _accY -= my;
        _moveCursor(mx, my);
        _redraw();
      }
      return;
    }
    final p = _toCanvas(pos, box, engine.width, engine.height);
    if (_tool == 'Eraser') {
      _eraserX = p.dx.toInt();
      _eraserY = p.dy.toInt();
    }
    _send('PointerMove(${p.dx.toInt()},${p.dy.toInt()})');
    _redraw();
  }

  void _endDraw() {
    if (_isCursorTool) {
      _lastTouch = null;
      if (_penDown) _refreshState();
      return;
    }
    if (_eraserX != null) {
      _eraserX = null;
      _eraserY = null;
    }
    _send('PointerUp()');
    _refreshState();
    _redraw();
    setState(() {});
  }

  // Abort an in-progress draw, discarding its marks without an undo step (used when a gesture
  // interrupts a nascent stroke).
  void _cancelDraw() {
    if (_isCursorTool) {
      _lastTouch = null;
      if (_penDown) _send('CancelStroke()'); // abort a precision pen line in progress
    } else {
      _eraserX = null;
      _eraserY = null;
      _send('CancelStroke()');
    }
    _refreshState();
    _redraw();
    setState(() {});
  }

  void _resetTouchSession() {
    _touches.clear();
    _drawPointer = null;
    _gestureMode = false;
    _maxTouches = 0;
    _sessionStart = null;
    _primaryMoved = 0;
    _gestureMoved = 0;
  }

  // A still 2/3-finger tap maps to undo/redo. Fired when the last finger of a gesture session lifts.
  void _fireTapGesture() {
    final dur = _sessionStart == null ? Duration.zero : (_touchClock.elapsed - _sessionStart!);
    final quick = dur.inMilliseconds <= _kTapMaxMs;
    final still = _gestureMoved <= _kGestureSlop;
    if (!quick || !still) return;
    if (_maxTouches >= 3) {
      if (_state['can_redo'] == true) _act('Redo()');
    } else if (_maxTouches == 2) {
      if (_state['can_undo'] == true) _act('Undo()');
    }
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
        Container(width: 1, color: Colors.black26),
        IconButton(iconSize: 20, tooltip: 'Add frame', onPressed: () => _act('AddFrame()'), icon: const Icon(Icons.add_box)),
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

  int _activeLayerIndex() {
    final frames = (_state['frame_detail'] as List?);
    if (frames != null && engine.activeFrame < frames.length) {
      return frames[engine.activeFrame]['active_layer'] ?? 0;
    }
    return 0;
  }

  // Push the current move-group to the engine's layer selection so both the Move-Layer drag and
  // the nudge buttons act on the whole group (or just the active layer when none is grouped).
  void _syncLayerSel() {
    if (_selLayers.length > 1) {
      // SetMoveGroup sets the move-group without changing the active layer (it stays put).
      final list = (_selLayers.toList()..sort()).join(',');
      _send('SetMoveGroup($list)');
    } else {
      _send('SetActiveLayer(${_activeLayerIndex()})');
    }
  }

  void _nudgeLayer(int dx, int dy) {
    _syncLayerSel();
    _act('NudgeLayers($dx,$dy)');
  }

  Future<void> _genLayerThumb(int frame, int layer, int hash) async {
    final key = _layerKey(frame, layer);
    if (_layerThumbInFlight.contains(key)) return;
    _layerThumbInFlight.add(key);
    final (tw, th) = _thumbSize();
    final bytes = engine.layerThumb(frame, layer, tw, th);
    if (bytes.length < tw * th * 4) {
      _layerThumbInFlight.remove(key);
      return;
    }
    final img = await _decode(bytes, tw, th);
    _layerThumbInFlight.remove(key);
    if (!mounted) {
      img.dispose();
      return;
    }
    _layerThumbs[key]?.img.dispose();
    _layerThumbs[key] = _Thumb(hash, img);
    if (_layerThumbs.length > 60) {
      final victim = _layerThumbs.keys.firstWhere((k) => k != key, orElse: () => -1);
      if (victim >= 0) _layerThumbs.remove(victim)?.img.dispose();
    }
    setState(() {});
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
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('In move group'),
                subtitle: const Text('Move together with the Move-Layer tool', style: TextStyle(fontSize: 11)),
                value: inGroup,
                onChanged: (v) {
                  setS(() => inGroup = v);
                  setState(() {
                    if (v) {
                      _selLayers.add(i);
                    } else {
                      _selLayers.remove(i);
                    }
                  });
                  _syncLayerSel();
                },
              ),
              Wrap(spacing: 8, children: [
                ActionChip(avatar: const Icon(Icons.control_point_duplicate, size: 16), label: const Text('Duplicate'), onPressed: () { Navigator.pop(ctx); _act('DuplicateLayer($i)'); }),
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

  // Layers as a horizontal film-strip (mirrors the frame film-roll): each tile shows just that
  // layer on a checkerboard (transparent) background. "Add layer" sits to the left; duplicate and
  // the other per-layer actions live in the long-press menu.
  Widget _buildLayers(List<dynamic> layers) {
    final frames = (_state['frame_detail'] as List?);
    int activeLayer = 0;
    if (frames != null && engine.activeFrame < frames.length) {
      activeLayer = frames[engine.activeFrame]['active_layer'] ?? 0;
    }
    final frame = engine.activeFrame;
    final (tw, th) = _thumbSize();
    final tileW = (40.0 * tw / th).clamp(26.0, 72.0);
    return Container(
      height: 56,
      color: const Color(0xFF1A1C1F),
      child: Row(children: [
        IconButton(iconSize: 20, tooltip: 'Add layer', onPressed: () => _act('AddLayer()'), icon: const Icon(Icons.add_box)),
        Container(width: 1, color: Colors.black26),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: layers.length,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemBuilder: (_, i) {
              final l = layers[i] as Map<String, dynamic>;
              final sel = i == activeLayer;
              final inGroup = _selLayers.contains(i);
              final visible = l['visible'] == true;
              final hash = engine.layerHash(frame, i);
              final key = _layerKey(frame, i);
              final cached = _layerThumbs[key];
              if (cached == null || cached.hash != hash) _genLayerThumb(frame, i, hash);
              return GestureDetector(
                onTap: () { setState(() => _selLayers.clear()); _act('SetActiveLayer($i)'); },
                onLongPress: () => _layerOptions(i, l, layers.length),
                child: Container(
                  width: tileW + 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101214),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      // active layer always shows blue (it stays put while grouped); other
                      // grouped layers show amber.
                      color: sel ? const Color(0xFF4080C0) : (inGroup ? Colors.amber : Colors.black26),
                      width: (sel || inGroup) ? 2 : 1,
                    ),
                  ),
                  child: Stack(fit: StackFit.expand, children: [
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: Opacity(
                        opacity: visible ? 1 : 0.35,
                        child: CustomPaint(
                          painter: const _CheckerPainter(),
                          child: cached != null
                              ? RawImage(image: cached.img, fit: BoxFit.contain, filterQuality: FilterQuality.none)
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    // quick visibility toggle (top-left)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => _act('SetLayerVisible($i, ${!visible})'),
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          color: const Color(0xCC000000),
                          child: Icon(visible ? Icons.visibility : Icons.visibility_off, size: 13, color: Colors.white70),
                        ),
                      ),
                    ),
                    if (l['locked'] == true)
                      const Positioned(right: 1, top: 1, child: Icon(Icons.lock, size: 12, color: Colors.white54)),
                  ]),
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

    if (_isCursorTool) {
      // off-finger reticle nudge pad (1px steps), shared by precision pencil + airbrush
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge left', onPressed: () => _nudgeCursor(-1, 0), icon: const Icon(Icons.chevron_left)));
      children.add(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        InkWell(onTap: () => _nudgeCursor(0, -1), child: const Icon(Icons.keyboard_arrow_up, size: 18)),
        InkWell(onTap: () => _nudgeCursor(0, 1), child: const Icon(Icons.keyboard_arrow_down, size: 18)),
      ]));
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge right', onPressed: () => _nudgeCursor(1, 0), icon: const Icon(Icons.chevron_right)));
      children.add(const SizedBox(width: 4));
    }
    if (_isPrecision) {
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
    if (_tool == 'MoveLayer') {
      // nudge the active layer 1px; dragging on the canvas also moves it (live)
      label('Move layer');
      children.add(IconButton(iconSize: 20, tooltip: 'Move layer left', onPressed: () => _nudgeLayer(-1, 0), icon: const Icon(Icons.chevron_left)));
      children.add(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        InkWell(onTap: () => _nudgeLayer(0, -1), child: const Icon(Icons.keyboard_arrow_up, size: 18)),
        InkWell(onTap: () => _nudgeLayer(0, 1), child: const Icon(Icons.keyboard_arrow_down, size: 18)),
      ]));
      children.add(IconButton(iconSize: 20, tooltip: 'Move layer right', onPressed: () => _nudgeLayer(1, 0), icon: const Icon(Icons.chevron_right)));
    }
    if (_tool == 'Airbrush') {
      // SPRAY (one airbrush dab at the reticle, off-finger)
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 34), backgroundColor: const Color(0xFF4080C0)),
          onPressed: () { _send('AirbrushCursor()'); _refreshState(); _redraw(); setState(() {}); },
          icon: const Icon(Icons.blur_on, size: 16),
          label: const Text('Spray'),
        ),
      ));
    }

    final sizeTools = {'Pencil', 'PrecisionPencil', 'Brush', 'Airbrush', 'Eraser', 'Dodge', 'Burn', 'Line', 'Rectangle', 'Ellipse'};
    if (sizeTools.contains(_tool)) {
      _labeledSlider(children, 'Size', _brushSize.toDouble(), 1, 32, (v) {
        setState(() => _brushSize = v.round());
        _send('SetBrushSize($_brushSize)');
      });
      label('Shape');
      children.add(_toggle(['Round', 'Square'], _round ? 0 : 1, (i) {
        setState(() => _round = i == 0);
        _send('SetBrushShape(${_round ? 'Round' : 'Square'})');
      }));
    }
    if (_tool == 'Airbrush' || _tool == 'Dodge' || _tool == 'Burn') {
      _labeledSlider(children, 'Intensity', _intensity.toDouble(), 1, 255, (v) {
        setState(() => _intensity = v.round());
        _send('SetIntensity($_intensity)');
      });
    }
    if (_tool == 'Bucket' || _tool == 'SelectByColor') {
      _labeledSlider(children, 'Threshold', _threshold.toDouble(), 0, 255, (v) {
        setState(() => _threshold = v.round());
        _send('SetThreshold($_threshold)');
      });
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
      children.add(_miniBtn('Crop→Sel', () => _act('CropToSelection()')));
    }
    if (_tool == 'HsvShift') {
      _labeledSlider(children, 'H', _hsvH, -180, 180, (v) => setState(() => _hsvH = v));
      _labeledSlider(children, 'S', _hsvS, -1, 1, (v) => setState(() => _hsvS = v), integer: false);
      _labeledSlider(children, 'V', _hsvV, -1, 1, (v) => setState(() => _hsvV = v), integer: false);
      children.add(_miniBtn('Apply', () {
        _send('SetHsvShift($_hsvH, $_hsvS, $_hsvV)');
        _act('ApplyHsvShift()');
      }));
    }
    if (_tool == 'Flip') {
      children.add(_miniBtn('Flip H', () => _act('FlipH()')));
      children.add(_miniBtn('Flip V', () => _act('FlipV()')));
    }
    if (_tool == 'Rotate') {
      children.add(IconButton(iconSize: 18, tooltip: 'Rotate 90° CW', onPressed: () => _act('Rotate(1)'), icon: const Icon(Icons.rotate_right)));
      children.add(IconButton(iconSize: 18, tooltip: 'Rotate 90° CCW', onPressed: () => _act('Rotate(3)'), icon: const Icon(Icons.rotate_left)));
      children.add(_miniBtn('Rotate 180', () => _act('Rotate(2)')));
    }
    if (_tool == 'Invert') {
      children.add(_miniBtn('Invert colours', () => _act('Invert()')));
    }
    if (_tool == 'Resize') {
      children.add(_miniBtn('Resize…', _resizeCanvasDialog));
    }

    return Container(
      height: 48,
      width: double.infinity, // span full width so narrow content doesn't expose the black background on each side
      color: const Color(0xFF202327),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [const SizedBox(width: 4), ...children, const SizedBox(width: 8)]),
      ),
    );
  }

  Widget _buildPalette() {
    return Container(
      color: const Color(0xFF1C1F22),
      child: SizedBox(
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
          // palette controls: tucked into a button after the last swatch
          IconButton(iconSize: 18, tooltip: 'Palette controls', onPressed: _paletteControlsMenu, icon: const Icon(Icons.palette, color: Colors.white70)),
        ]),
      ),
    );
  }

  void _paletteControlsMenu() {
    final names = (_state['palette_names'] as List?)?.cast<String>() ?? ['Default'];
    final active = (_state['active_palette'] as int?) ?? 0;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < names.length; i++)
            ListTile(
              leading: Icon(i == active ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
              title: Text(names[i]),
              onTap: () { Navigator.pop(ctx); _act('SetActivePalette($i)'); },
            ),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.add_box_outlined), title: const Text('New palette'), onTap: () { Navigator.pop(ctx); _newPalette(); }),
          ListTile(leading: const Icon(Icons.save_alt), title: const Text('Save palette'), onTap: () { Navigator.pop(ctx); _savePalette(); }),
          ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('Load palette (.json/.gpl)'), onTap: () { Navigator.pop(ctx); _loadPalette(); }),
        ]),
      ),
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

  // A row-1 slider with a tappable label: tapping the "Name value" label opens a numeric
  // text-entry dialog so the exact value can be typed instead of dragged. The text path and
  // the drag path share the same [onChanged], keeping behaviour identical.
  void _labeledSlider(List<Widget> children, String name, double value, double min, double max,
      ValueChanged<double> onChanged, {bool integer = true}) {
    final shown = integer ? value.round().toString() : value.toStringAsFixed(1);
    children.add(InkWell(
      onTap: () => _editSliderValue(name, value, min, max, onChanged, integer: integer),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Text('$name $shown',
            style: const TextStyle(
                fontSize: 11,
                color: Colors.white60,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white24)),
      ),
    ));
    children.add(_slider(value, min, max, onChanged));
  }

  Future<void> _editSliderValue(String name, double value, double min, double max,
      ValueChanged<double> onChanged, {required bool integer}) async {
    String fmt(double d) => integer ? d.round().toString() : d.toStringAsFixed(1);
    final ctrl = TextEditingController(text: integer ? value.round().toString() : value.toStringAsFixed(2));
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    final entered = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: !integer, signed: min < 0),
          decoration: InputDecoration(labelText: 'Value (${fmt(min)} – ${fmt(max)})'),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())), child: const Text('OK')),
        ],
      ),
    );
    if (entered != null && entered.isFinite) {
      onChanged(entered.clamp(min, max).toDouble());
    }
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

/// The off-finger cursor "bulls-eye": a thin, screen-space, marching-ants reticle around the
/// target pixel (cell outline + four crosshair arms). Drawn in screen pixels — never baked into
/// canvas pixels — so it stays crisp at any zoom, like the selection outline.
class _ReticlePainter extends CustomPainter {
  final int cx, cy, cw, ch; // reticle target pixel + canvas dims
  final Animation<double> anim;
  _ReticlePainter(this.cx, this.cy, this.cw, this.ch, this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    if (cw <= 0 || ch <= 0) return;
    final scale = (size.width / cw) < (size.height / ch) ? (size.width / cw) : (size.height / ch);
    final ox = (size.width - cw * scale) / 2;
    final oy = (size.height - ch * scale) / 2;
    final left = ox + cx * scale;
    final top = oy + cy * scale;
    final cell = Rect.fromLTWH(left, top, scale, scale);
    final center = cell.center;
    final gap = scale * 0.5 + 3; // keep the target pixel + its ring uncovered
    final arm = scale * 1.5 + 7;
    final segs = <List<Offset>>[
      // outline of the exact target pixel cell
      [cell.topLeft, cell.topRight],
      [cell.topRight, cell.bottomRight],
      [cell.bottomRight, cell.bottomLeft],
      [cell.bottomLeft, cell.topLeft],
      // four crosshair arms pointing inward from outside the gap
      [Offset(center.dx, top - gap - arm), Offset(center.dx, top - gap)],
      [Offset(center.dx, cell.bottom + gap), Offset(center.dx, cell.bottom + gap + arm)],
      [Offset(left - gap - arm, center.dy), Offset(left - gap, center.dy)],
      [Offset(cell.right + gap, center.dy), Offset(cell.right + gap + arm, center.dy)],
    ];
    final phase = anim.value; // 0..1, advances the ants along each segment
    for (final s in segs) {
      _march(canvas, s[0], s[1], phase);
    }
  }

  // Draw a marching-ants dashed segment: alternating black/white dashes sliding with [phase].
  void _march(Canvas canvas, Offset a, Offset b, double phase) {
    const dash = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    final black = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.4
      ..isAntiAlias = false;
    final white = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4
      ..isAntiAlias = false;
    var pos = -((phase * dash * 2) % (dash * 2)); // negative start so ants march toward +dir
    var idx = 0;
    while (pos < total) {
      final segStart = pos < 0 ? 0.0 : pos;
      final segEnd = (pos + dash) > total ? total : (pos + dash);
      if (segEnd > segStart) {
        canvas.drawLine(a + dir * segStart, a + dir * segEnd, idx.isEven ? black : white);
      }
      pos += dash;
      idx++;
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => true; // driven by the animation
}

/// A small two-tone checkerboard, used behind layer thumbnails so transparent areas read as
/// transparent (the layers film-strip shows each layer against a transparent background).
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();
  static const double cell = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFF3A3D42);
    final dark = Paint()..color = const Color(0xFF26282C);
    canvas.drawRect(Offset.zero & size, light);
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if ((r + c).isEven) continue;
        canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => false;
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
