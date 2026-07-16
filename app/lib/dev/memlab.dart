// Memory stress lab (tools/memlab): an escalation ladder of adversarial (full-noise) documents
// run against the real engine inside the real app process, so Android's LMK verdict applies to
// the whole binary — engine + Dart heap + textures — not just the engine.
//
// There is deliberately NO UI entry point. The lab is reachable only through a launch-intent
// extra (see MainActivity.kt):
//
//   adb shell am start -n club.makapix.app/.MainActivity -e memlab auto
//   adb shell am start -n club.makapix.app/.MainActivity -e memlab "edit:256:4+clear+thumbs,edit:512:1"
//
// Rung grammar:  edit:FRAMES:LAYERS[:CANVAS][+clear][+thumbs][+save]   |   churn:N
//   +clear   ClearHistory() after every frame — isolates document growth from undo retention
//   +thumbs  build + hold a per-frame timeline thumbnail (ui.Image), like an open editor
//   +save    serialize to .mkpx bytes at the end of the rung (the big transient)
//
// Each rung runs in a fresh engine session. Progress is checkpointed to the app's external files
// dir (adb-pullable: /sdcard/Android/data/club.makapix.app/files/memlab.json) BEFORE each rung and
// every 64 frames, so an LMK kill is itself the datapoint: the file names the rung that died.
// Every measurement is also logged to logcat as a single "MEMLAB {json}" line.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../engine_ffi.dart';

const _channel = MethodChannel('club.makapix.app/memlab');

/// The launch-intent plan, or null when the app was started normally (every platform other than
/// Android, and every Android launch without the extra).
Future<String?> memLabPlan() async {
  if (kIsWeb || !Platform.isAndroid) return null;
  try {
    return await _channel.invokeMethod<String>('plan');
  } catch (_) {
    return null; // no host handler (tests, older embedding) — never block normal startup
  }
}

/// Mounts [child] normally; replaces the whole app with the lab when a plan extra is present.
class MemLabGate extends StatefulWidget {
  const MemLabGate({super.key, required this.child});
  final Widget child;
  @override
  State<MemLabGate> createState() => _MemLabGateState();
}

class _MemLabGateState extends State<MemLabGate> {
  late final Future<String?> _plan = memLabPlan();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _plan,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final plan = snap.data;
        if (plan == null || plan.isEmpty) return widget.child;
        return MemLabPage(plan: plan);
      },
    );
  }
}

/// The default ladder, ordered by increasing lethality. Document bytes at 256×256 are
/// frames×layers/4 MiB; +save peaks at ~6× that (measured on Windows); rungs without +clear
/// additionally retain O(frames²×layers) undo tile-tables.
const _autoLadder = 'edit:64:4+clear+thumbs,'
    'edit:256:1,'
    'edit:256:4+clear+thumbs,'
    'edit:512:1,'
    'edit:1024:1+clear+thumbs,'
    'edit:256:4+clear+save,'
    'edit:1024:4+clear+thumbs,'
    'edit:1024:4+clear+save,'
    'edit:1024:8+clear,'
    'edit:1024:16+clear,'
    'edit:1024:32+clear';

class MemLabPage extends StatefulWidget {
  const MemLabPage({super.key, required this.plan});
  final String plan;
  @override
  State<MemLabPage> createState() => _MemLabPageState();
}

class _MemLabPageState extends State<MemLabPage> {
  final List<Map<String, dynamic>> _results = [];
  String _status = 'starting';
  File? _checkpoint;

  @override
  void initState() {
    super.initState();
    _run();
  }

  List<String> get _rungs =>
      (widget.plan.trim() == 'auto' ? _autoLadder : widget.plan)
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

  Future<void> _run() async {
    final dir = await getExternalStorageDirectory();
    if (dir != null) _checkpoint = File('${dir.path}/memlab.json');
    for (final spec in _rungs) {
      await _writeCheckpoint(attempting: spec);
      _say('attempting $spec');
      final row = await _runRung(spec);
      _results.add(row);
      debugPrint('MEMLAB ${jsonEncode(row)}');
      await _writeCheckpoint();
      if (mounted) setState(() {});
    }
    _say('ladder complete — all rungs survived');
    await _writeCheckpoint(done: true);
  }

  void _say(String s) {
    debugPrint('MEMLAB $s');
    if (mounted) setState(() => _status = s);
  }

  Future<void> _writeCheckpoint({String? attempting, bool done = false, int? progress}) async {
    final f = _checkpoint;
    if (f == null) return;
    await f.writeAsString(jsonEncode({
      'plan': widget.plan,
      'results': _results,
      'attempting': ?attempting,
      'progress_frames': ?progress,
      'done': done,
    }));
  }

  /// (VmRSS, VmHWM) in bytes from /proc/self/status.
  (int, int) _osMem() {
    try {
      final s = File('/proc/self/status').readAsStringSync();
      int grab(String key) {
        final m = RegExp('$key:\\s+(\\d+) kB').firstMatch(s);
        return m == null ? 0 : int.parse(m.group(1)!) * 1024;
      }

      return (grab('VmRSS'), grab('VmHWM'));
    } catch (_) {
      return (0, 0);
    }
  }

  Future<Map<String, dynamic>> _runRung(String spec) async {
    final sw = Stopwatch()..start();
    final row = <String, dynamic>{'rung': spec};
    Engine? engine;
    final thumbs = <ui.Image>[];
    try {
      if (spec.startsWith('churn:')) {
        final n = int.parse(spec.substring(6));
        engine = Engine(256, 256);
        for (var i = 0; i < n; i++) {
          final err = engine.run('FillNoise(${i + 1})');
          if (err != null) throw StateError(err);
          if (i % 16 == 15) await Future<void>.delayed(Duration.zero);
        }
      } else {
        final opts = spec.split('+');
        final dims = opts.first.split(':'); // edit:F:L[:W]
        final frames = int.parse(dims[1]);
        final layers = int.parse(dims[2]);
        final canvas = dims.length > 3 ? int.parse(dims[3]) : 256;
        final clear = opts.contains('clear');
        engine = Engine(canvas, canvas);
        var seed = 1;
        for (var f = 0; f < frames; f++) {
          final b = StringBuffer();
          if (f > 0) b.writeln('AddFrame()');
          for (var l = 0; l < layers; l++) {
            if (l > 0) b.writeln('AddLayer()');
            b.writeln('FillNoise(${seed++})');
          }
          if (clear) b.writeln('ClearHistory()');
          final err = engine.run(b.toString());
          if (err != null) throw StateError(err);
          if (f % 16 == 15) await Future<void>.delayed(Duration.zero);
          if (f % 64 == 63) await _writeCheckpoint(attempting: spec, progress: f + 1);
        }
        if (opts.contains('thumbs')) {
          for (var f = 0; f < frames; f++) {
            thumbs.add(await _decode(engine.frameThumb(f, 48, 48), 48, 48));
            if (f % 64 == 63) await Future<void>.delayed(Duration.zero);
          }
          row['thumbs'] = thumbs.length;
        }
        if (opts.contains('save')) {
          final t = Stopwatch()..start();
          final bytes = engine.save();
          row['save_bytes'] = bytes.length;
          row['save_ms'] = t.elapsedMilliseconds;
        }
      }
      row['engine'] = jsonDecode(engine.memJson());
      final (rss, hwm) = _osMem();
      row['vmrss'] = rss;
      row['vmhwm'] = hwm;
      row['ok'] = true;
    } catch (e) {
      row['ok'] = false;
      row['error'] = '$e';
    } finally {
      for (final t in thumbs) {
        t.dispose();
      }
      engine?.dispose();
    }
    row['ms'] = sw.elapsedMilliseconds;
    return row;
  }

  Future<ui.Image> _decode(Uint8List rgba, int w, int h) async {
    final buf = await ui.ImmutableBuffer.fromUint8List(rgba);
    final desc = ui.ImageDescriptor.raw(buf,
        width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    desc.dispose();
    buf.dispose();
    return frame.image;
  }

  String _mib(num? b) => b == null ? '-' : (b / 1048576).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory stress lab')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_status, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final r in _results)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      r['ok'] == true ? Icons.check_circle : Icons.error,
                      color: r['ok'] == true ? Colors.green : Colors.red,
                    ),
                    title: Text('${r['rung']}'),
                    subtitle: Text(
                      'doc ${_mib(r['engine']?['doc_bytes'])} MiB · '
                      'total ${_mib(r['engine']?['total_bytes'])} MiB · '
                      'rss ${_mib(r['vmrss'])} MiB · peak ${_mib(r['vmhwm'])} MiB · '
                      '${r['ms']} ms${r['error'] != null ? ' · ${r['error']}' : ''}',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
