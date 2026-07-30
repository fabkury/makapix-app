// SceneEngine — the Animator's dart:ffi binding over the `mkps_*` C ABI (engine_ffi.dart's
// sibling). Opens the SAME cdylib via [openMakapixLibrary] (one library, one allocator;
// export progress rides the shared process-wide `mkpx_export_*` atomics, so the editor's
// [Engine.exportProgressStatic]/[Engine.cancelExportStatic] drive Scene exports too). All
// conventions mirrored from Engine: reused native scratch buffer with the
// consume-synchronously contract, straight-alpha output that Dart premultiplies, calloc/
// finally hardening on save, and the rebuild-from-bytes isolate model for background encodes
// (an opaque session pointer never crosses isolates).
import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:makapix_club/engine_ffi.dart' show openMakapixLibrary, utf8Encode;

typedef _NewC = Pointer<Void> Function(Uint16, Uint16, Uint32);
typedef _NewD = Pointer<Void> Function(int, int, int);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);
typedef _RunC = Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, UintPtr);
typedef _RunD = Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _StrC = Pointer<Utf8> Function(Pointer<Void>);
typedef _StrD = Pointer<Utf8> Function(Pointer<Void>);
typedef _U32C = Uint32 Function(Pointer<Void>);
typedef _U32D = int Function(Pointer<Void>);
typedef _U64C = Uint64 Function(Pointer<Void>);
typedef _U64D = int Function(Pointer<Void>);
typedef _CompositeC = Int32 Function(Pointer<Void>, Uint32, Pointer<Uint8>, UintPtr);
typedef _CompositeD = int Function(Pointer<Void>, int, Pointer<Uint8>, int);
typedef _FrameHashC = Uint64 Function(Pointer<Void>, Uint32);
typedef _FrameHashD = int Function(Pointer<Void>, int);
typedef _ThumbC = Int32 Function(Pointer<Void>, Uint32, Uint32, Uint32, Pointer<Uint8>, UintPtr);
typedef _ThumbD = int Function(Pointer<Void>, int, int, int, Pointer<Uint8>, int);
typedef _HitC = Int32 Function(Pointer<Void>, Uint32, Int32, Int32);
typedef _HitD = int Function(Pointer<Void>, int, int, int);
typedef _SaveC = Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint64>);
typedef _SaveD = Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint64>);
typedef _LoadC = Int32 Function(Pointer<Void>, Pointer<Uint8>, UintPtr);
typedef _LoadD = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _ProbeC = Pointer<Utf8> Function(Pointer<Uint8>, UintPtr);
typedef _ProbeD = Pointer<Utf8> Function(Pointer<Uint8>, int);
typedef _ImportC = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Uint8>, UintPtr, Int32, Int32, Pointer<Utf8>);
typedef _ImportD = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Uint8>, int, int, int, Pointer<Utf8>);
typedef _ExportC = Pointer<Uint8> Function(Pointer<Void>, Uint32, Pointer<Uint64>);
typedef _ExportD = Pointer<Uint8> Function(Pointer<Void>, int, Pointer<Uint64>);
typedef _AlphaLossyC = Uint32 Function();
typedef _AlphaLossyD = int Function();
typedef _FreeStringC = Void Function(Pointer<Utf8>);
typedef _FreeStringD = void Function(Pointer<Utf8>);
typedef _FreeBytesC = Void Function(Pointer<Uint8>, Uint64);
typedef _FreeBytesD = void Function(Pointer<Uint8>, int);

class SceneEngine {
  final DynamicLibrary _lib;
  late final Pointer<Void> _s;

  // Reused native scratch buffer for per-scrub composite reads (Engine's exact pattern):
  // grown on demand, freed in [dispose], never shrunk.
  Pointer<Uint8> _scratch = nullptr;
  int _scratchCap = 0;

  Pointer<Uint8> _ensureScratch(int cap) {
    if (cap > _scratchCap) {
      if (_scratch != nullptr) malloc.free(_scratch);
      _scratch = malloc<Uint8>(cap);
      _scratchCap = cap;
    }
    return _scratch;
  }

  late final _NewD _new = _lib.lookupFunction<_NewC, _NewD>('mkps_new');
  late final _FreeD _freeS = _lib.lookupFunction<_FreeC, _FreeD>('mkps_free');
  late final _RunD _run = _lib.lookupFunction<_RunC, _RunD>('mkps_run');
  late final _StrD _state = _lib.lookupFunction<_StrC, _StrD>('mkps_state_json');
  late final _StrD _memJson = _lib.lookupFunction<_StrC, _StrD>('mkps_mem_json');
  late final _U32D _width = _lib.lookupFunction<_U32C, _U32D>('mkps_width');
  late final _U32D _height = _lib.lookupFunction<_U32C, _U32D>('mkps_height');
  late final _U32D _frameCount = _lib.lookupFunction<_U32C, _U32D>('mkps_frame_count');
  late final _U32D _playhead = _lib.lookupFunction<_U32C, _U32D>('mkps_playhead');
  late final _U32D _playFrame = _lib.lookupFunction<_U32C, _U32D>('mkps_play_frame');
  late final _U64D _cacheEpoch = _lib.lookupFunction<_U64C, _U64D>('mkps_cache_epoch');
  late final _CompositeD _composite = _lib.lookupFunction<_CompositeC, _CompositeD>('mkps_composite');
  late final _FrameHashD _frameHash = _lib.lookupFunction<_FrameHashC, _FrameHashD>('mkps_frame_hash');
  late final _ThumbD _propThumb = _lib.lookupFunction<_ThumbC, _ThumbD>('mkps_prop_thumb');
  late final _ThumbD _actorThumb = _lib.lookupFunction<_ThumbC, _ThumbD>('mkps_actor_thumb');
  late final _HitD _hitTest = _lib.lookupFunction<_HitC, _HitD>('mkps_hit_test');
  late final _SaveD _save = _lib.lookupFunction<_SaveC, _SaveD>('mkps_save');
  late final _SaveD _saveCompact = _lib.lookupFunction<_SaveC, _SaveD>('mkps_save_compact');
  late final _LoadD _load = _lib.lookupFunction<_LoadC, _LoadD>('mkps_load');
  late final _ImportD _importProp = _lib.lookupFunction<_ImportC, _ImportD>('mkps_import_prop');
  late final _ExportD _exportGif = _lib.lookupFunction<_ExportC, _ExportD>('mkps_export_gif');
  late final _ExportD _exportWebp = _lib.lookupFunction<_ExportC, _ExportD>('mkps_export_webp');
  late final _FreeStringD _freeStr =
      _lib.lookupFunction<_FreeStringC, _FreeStringD>('mkpx_free_string');
  late final _FreeBytesD _freeBytes =
      _lib.lookupFunction<_FreeBytesC, _FreeBytesD>('mkpx_free_bytes');

  /// New session at `w`×`h` and `millifps` (one of the curated list; throws otherwise).
  SceneEngine(int w, int h, {required int millifps}) : _lib = openMakapixLibrary() {
    _s = _new(w, h, millifps);
    if (_s == nullptr) throw Exception('mkps_new failed');
  }

  /// A throwaway session for [load]-then-use flows (thumbnails, background encodes).
  SceneEngine.forLoad() : this(8, 8, millifps: 12500);

  int get width => _width(_s);
  int get height => _height(_s);
  int get frameCount => _frameCount(_s);
  int get playhead => _playhead(_s);
  int get playFrame => _playFrame(_s);
  int get cacheEpoch => _cacheEpoch(_s);

  /// Run a DSL script; null on success, else the engine's error message.
  String? run(String script) {
    final units = utf8Encode(script);
    final p = malloc<Uint8>(units.length);
    p.asTypedList(units.length).setAll(0, units);
    final err = _run(_s, p, units.length);
    malloc.free(p);
    if (err == nullptr) return null;
    final msg = err.toDartString();
    _freeStr(err);
    return msg;
  }

  String stateJson() {
    final p = _state(_s);
    final s = p.toDartString();
    _freeStr(p);
    return s;
  }

  String memJson() {
    final p = _memJson(_s);
    final s = p.toDartString();
    _freeStr(p);
    return s;
  }

  /// One scene frame's composited RGBA (canvas-sized, STRAIGHT alpha — premultiply before
  /// decode). Same reused-scratch-buffer contract as [Engine.display]: the returned list is a
  /// view valid only until the next [compositeFrame] call — consume synchronously, never
  /// store/await/ship to an isolate.
  Uint8List compositeFrame(int frame) {
    final cap = width * height * 4;
    final out = _ensureScratch(cap);
    final n = _composite(_s, frame, out, cap);
    return out.asTypedList(n < 0 ? 0 : n);
  }

  /// Low-64-bit content hash of a composited frame (cache validation).
  int frameHash(int frame) => _frameHash(_s, frame);

  /// A Prop's frame-0 thumbnail as exactly `tw`×`th` straight RGBA (art centered, transparent
  /// padding). Fresh copy (not the scratch buffer). Empty on unknown prop.
  Uint8List propThumb(int propId, int tw, int th) {
    final cap = tw * th * 4;
    final p = malloc<Uint8>(cap);
    try {
      final n = _propThumb(_s, propId, tw, th, p, cap);
      return n <= 0 ? Uint8List(0) : Uint8List.fromList(p.asTypedList(n));
    } finally {
      malloc.free(p);
    }
  }

  /// An Actor's resolved-source-frame thumbnail at the playhead. Fresh copy.
  Uint8List actorThumb(int actorId, int tw, int th) {
    final cap = tw * th * 4;
    final p = malloc<Uint8>(cap);
    try {
      final n = _actorThumb(_s, actorId, tw, th, p, cap);
      return n <= 0 ? Uint8List(0) : Uint8List.fromList(p.asTypedList(n));
    } finally {
      malloc.free(p);
    }
  }

  /// Topmost visible Actor whose opaque transformed pixel covers scene point (x, y), or null.
  int? hitTest(int frame, int x, int y) {
    final id = _hitTest(_s, frame, x, y);
    return id < 0 ? null : id;
  }

  /// Plain `.mkps` bytes (autosave uses plain; explicit Save/export uses [saveCompact] —
  /// the editor's convention). Hardened like [Engine.save]: calloc + try/finally.
  Uint8List save() {
    final lenPtr = calloc<Uint64>();
    try {
      final p = _save(_s, lenPtr);
      if (p == nullptr) return Uint8List(0);
      final len = lenPtr.value;
      try {
        return Uint8List.fromList(p.asTypedList(len));
      } finally {
        _freeBytes(p, len);
      }
    } finally {
      calloc.free(lenPtr);
    }
  }

  Uint8List saveCompact() {
    final lenPtr = calloc<Uint64>();
    try {
      final p = _saveCompact(_s, lenPtr);
      if (p == nullptr) return Uint8List(0);
      final len = lenPtr.value;
      try {
        return Uint8List.fromList(p.asTypedList(len));
      } finally {
        _freeBytes(p, len);
      }
    } finally {
      calloc.free(lenPtr);
    }
  }

  bool load(Uint8List data) {
    final p = malloc<Uint8>(data.length);
    p.asTypedList(data.length).setAll(0, data);
    final ok = _load(_s, p, data.length) == 0;
    malloc.free(p);
    return ok;
  }

  /// Import bytes as Prop(s); returns the engine's result JSON
  /// (`{"props":[...],"actors":[...]}` or `{"error":".."}`).
  String importProp(Uint8List data,
      {required bool splitLayers, bool placeActors = true, String name = ''}) {
    final p = malloc<Uint8>(data.length);
    p.asTypedList(data.length).setAll(0, data);
    final Pointer<Utf8> namePtr = name.isEmpty ? nullptr : name.toNativeUtf8();
    try {
      final r = _importProp(
          _s, p, data.length, splitLayers ? 1 : 0, placeActors ? 1 : 0, namePtr);
      final json = r.toDartString();
      _freeStr(r);
      return json;
    } finally {
      malloc.free(p);
      if (namePtr != nullptr) malloc.free(namePtr);
    }
  }

  /// Whole-scene animated GIF at an integer `scale`. Empty on failure/cancel. After a
  /// successful call, [SceneEngine.lastGifAlphaLossy] reports the threshold notice.
  Uint8List exportGif({int scale = 1}) {
    final lenPtr = malloc<Uint64>();
    final p = _exportGif(_s, scale, lenPtr);
    final out = p == nullptr ? Uint8List(0) : Uint8List.fromList(p.asTypedList(lenPtr.value));
    if (p != nullptr) _freeBytes(p, lenPtr.value);
    malloc.free(lenPtr);
    return out;
  }

  /// Whole-scene animated lossless WEBP (true alpha) at an integer `scale`.
  Uint8List exportWebp({int scale = 1}) {
    final lenPtr = malloc<Uint64>();
    final p = _exportWebp(_s, scale, lenPtr);
    final out = p == nullptr ? Uint8List(0) : Uint8List.fromList(p.asTypedList(lenPtr.value));
    if (p != nullptr) _freeBytes(p, lenPtr.value);
    malloc.free(lenPtr);
    return out;
  }

  void dispose() {
    if (_scratch != nullptr) {
      malloc.free(_scratch);
      _scratch = nullptr;
      _scratchCap = 0;
    }
    _freeS(_s);
  }

  // ---- statics (usable without a session; lazy so importing this file never loads the DLL) --

  static final DynamicLibrary _staticLib = openMakapixLibrary();
  static final _ProbeD _sProbe =
      _staticLib.lookupFunction<_ProbeC, _ProbeD>('mkps_probe_import');
  static final _FreeStringD _sFreeStr =
      _staticLib.lookupFunction<_FreeStringC, _FreeStringD>('mkpx_free_string');
  static final _AlphaLossyD _sAlphaLossy =
      _staticLib.lookupFunction<_AlphaLossyC, _AlphaLossyD>('mkps_export_alpha_lossy');

  /// SESSION-FREE probe of importable bytes for the Whole/Parts card:
  /// `{"kind":"mkpx","w":..,"h":..,"frames":..,"layers":[{"name":".."},..]}` /
  /// `{"kind":"raster",...}` / `{"error":"unsupported"|"too_large"}`.
  static String probeImport(Uint8List data) {
    final p = malloc<Uint8>(data.length);
    p.asTypedList(data.length).setAll(0, data);
    try {
      final r = _sProbe(p, data.length);
      final json = r.toDartString();
      _sFreeStr(r);
      return json;
    } finally {
      malloc.free(p);
    }
  }

  /// Whether the most recent GIF export thresholded semi-transparent pixels (process-wide,
  /// readable from the UI isolate after a background encode).
  static bool get lastGifAlphaLossy => _sAlphaLossy() != 0;

  /// Encode a `.mkps` snapshot to 'gif' | 'webp' **off the UI thread** — the
  /// [Engine.encodeInBackground] model exactly: the isolate rebuilds its own session from the
  /// bytes (opaque pointers never cross isolates); progress flows through the shared
  /// process-wide atomics ([Engine.exportProgressStatic]); sync fallback if the isolate
  /// can't run. Empty on failure/cancel.
  static Future<Uint8List> encodeSceneInBackground(Uint8List mkpsBytes,
      {required String format, int scale = 1}) async {
    try {
      return await Isolate.run(() => _encodeFromBytes(mkpsBytes, format, scale));
    } catch (_) {
      return _encodeFromBytes(mkpsBytes, format, scale);
    }
  }

  static Uint8List _encodeFromBytes(Uint8List bytes, String format, int scale) {
    final e = SceneEngine.forLoad();
    try {
      if (!e.load(bytes)) return Uint8List(0);
      return format == 'webp' ? e.exportWebp(scale: scale) : e.exportGif(scale: scale);
    } finally {
      e.dispose();
    }
  }
}
