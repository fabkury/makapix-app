// Dart FFI bindings to the Makapix engine C ABI (makapix_ffi.dll). See crates/ffi.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// Premultiply straight-RGBA bytes in place, for handing to `ui.decodeImageFromPixels`.
///
/// The engine's FFI buffers are STRAIGHT alpha (`RgbaBuffer::to_rgba_bytes`), but Flutter's
/// `PixelFormat.rgba8888` raw decode treats the data as PREMULTIPLIED — feeding it straight
/// bytes renders translucent pixels too bright (pinned by canvas_checker_test.dart). Call this
/// on any engine pixel buffer before decoding it. Safe on the getters here: they all return
/// fresh copies.
void premultiplyRgbaInPlace(Uint8List bytes) {
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final a = bytes[i + 3];
    if (a == 255) continue;
    if (a == 0) {
      bytes[i] = 0;
      bytes[i + 1] = 0;
      bytes[i + 2] = 0;
    } else {
      bytes[i] = (bytes[i] * a) ~/ 255;
      bytes[i + 1] = (bytes[i + 1] * a) ~/ 255;
      bytes[i + 2] = (bytes[i + 2] * a) ~/ 255;
    }
  }
}

// ---- native signatures ----
typedef _NewC = Pointer<Void> Function(Uint16, Uint16);
typedef _NewD = Pointer<Void> Function(int, int);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);
typedef _RunC = Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _RunD = Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _U32C = Uint32 Function(Pointer<Void>);
typedef _U32D = int Function(Pointer<Void>);
typedef _DisplayC = Int32 Function(Pointer<Void>, Int32, Int32, Int32, Pointer<Uint8>, IntPtr);
typedef _DisplayD = int Function(Pointer<Void>, int, int, int, Pointer<Uint8>, int);
typedef _CompositeC = Int32 Function(Pointer<Void>, Uint32, Pointer<Uint8>, IntPtr);
typedef _CompositeD = int Function(Pointer<Void>, int, Pointer<Uint8>, int);
typedef _StateC = Pointer<Utf8> Function(Pointer<Void>);
typedef _StateD = Pointer<Utf8> Function(Pointer<Void>);
typedef _OutlineC = Int32 Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _OutlineD = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _FrameHashC = Uint64 Function(Pointer<Void>, Uint32);
typedef _FrameHashD = int Function(Pointer<Void>, int);
typedef _FrameThumbC = Int32 Function(Pointer<Void>, Uint32, Uint32, Uint32, Pointer<Uint8>, IntPtr);
typedef _FrameThumbD = int Function(Pointer<Void>, int, int, int, Pointer<Uint8>, int);
typedef _LayerThumbC = Int32 Function(Pointer<Void>, Uint32, Uint32, Uint32, Uint32, Pointer<Uint8>, IntPtr);
typedef _LayerThumbD = int Function(Pointer<Void>, int, int, int, int, Pointer<Uint8>, int);
typedef _LayerHashC = Uint64 Function(Pointer<Void>, Uint32, Uint32);
typedef _LayerHashD = int Function(Pointer<Void>, int, int);
typedef _SaveC = Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint64>);
typedef _SaveD = Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint64>);
typedef _LoadC = Int32 Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _LoadD = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _FreeStringC = Void Function(Pointer<Utf8>);
typedef _FreeStringD = void Function(Pointer<Utf8>);
typedef _FreeBytesC = Void Function(Pointer<Uint8>, Uint64);
typedef _FreeBytesD = void Function(Pointer<Uint8>, int);
typedef _ImportC = Int32 Function(Pointer<Void>, Pointer<Uint8>, IntPtr, Int32, Int32, Uint32, Int32, Int32, Int32, Int32);
typedef _ImportD = int Function(Pointer<Void>, Pointer<Uint8>, int, int, int, int, int, int, int, int);
typedef _ExportPngC = Pointer<Uint8> Function(Pointer<Void>, Uint32, Uint32, Pointer<Uint64>);
typedef _ExportPngD = Pointer<Uint8> Function(Pointer<Void>, int, int, Pointer<Uint64>);
typedef _ExportLayerPngC = Pointer<Uint8> Function(Pointer<Void>, Uint32, Uint32, Uint32, Pointer<Uint64>);
typedef _ExportLayerPngD = Pointer<Uint8> Function(Pointer<Void>, int, int, int, Pointer<Uint64>);
typedef _ExportGifC = Pointer<Uint8> Function(Pointer<Void>, Uint32, Pointer<Uint64>);
typedef _ExportGifD = Pointer<Uint8> Function(Pointer<Void>, int, Pointer<Uint64>);
typedef _ExportProgressC = Uint64 Function();
typedef _ExportProgressD = int Function();
typedef _ExportVoidC = Void Function();
typedef _ExportVoidD = void Function();

DynamicLibrary _open() {
  // Android: the engine ships as libmakapix_ffi.so bundled in the APK (jniLibs).
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libmakapix_ffi.so');
  }
  // iOS (future): statically linked into the app process.
  if (Platform.isIOS) {
    return DynamicLibrary.process();
  }
  // Windows / desktop: makapix_ffi.dll next to the exe, or the dev target dirs.
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = <String>[
    'makapix_ffi.dll',
    '$exeDir\\makapix_ffi.dll',
    '$exeDir\\..\\..\\..\\..\\..\\target\\release\\makapix_ffi.dll',
    '${Directory.current.path}\\..\\target\\release\\makapix_ffi.dll',
    '${Directory.current.path}\\..\\target\\debug\\makapix_ffi.dll',
  ];
  for (final c in candidates) {
    try {
      return DynamicLibrary.open(c);
    } catch (_) {}
  }
  throw Exception('Could not locate makapix_ffi.dll. Build it with: cargo build -p makapix-ffi --release');
}

class Engine {
  final DynamicLibrary _lib;
  late final Pointer<Void> _s;

  late final _NewD _new = _lib.lookupFunction<_NewC, _NewD>('mkpx_new');
  late final _FreeD _freeS = _lib.lookupFunction<_FreeC, _FreeD>('mkpx_free');
  late final _RunD _run = _lib.lookupFunction<_RunC, _RunD>('mkpx_run');
  late final _U32D _width = _lib.lookupFunction<_U32C, _U32D>('mkpx_width');
  late final _U32D _height = _lib.lookupFunction<_U32C, _U32D>('mkpx_height');
  late final _U32D _displayWidth = _lib.lookupFunction<_U32C, _U32D>('mkpx_display_width');
  late final _U32D _displayHeight = _lib.lookupFunction<_U32C, _U32D>('mkpx_display_height');
  late final _U32D _frameCount = _lib.lookupFunction<_U32C, _U32D>('mkpx_frame_count');
  late final _U32D _activeFrame = _lib.lookupFunction<_U32C, _U32D>('mkpx_active_frame');
  late final _U32D _playFrame = _lib.lookupFunction<_U32C, _U32D>('mkpx_play_frame');
  late final _U32D _primary = _lib.lookupFunction<_U32C, _U32D>('mkpx_primary_color');
  late final _DisplayD _display = _lib.lookupFunction<_DisplayC, _DisplayD>('mkpx_display');
  late final _CompositeD _composite = _lib.lookupFunction<_CompositeC, _CompositeD>('mkpx_composite_frame');
  late final _StateD _state = _lib.lookupFunction<_StateC, _StateD>('mkpx_state_json');
  late final _OutlineD _outline = _lib.lookupFunction<_OutlineC, _OutlineD>('mkpx_outline_mask');
  late final _FrameHashD _frameHash = _lib.lookupFunction<_FrameHashC, _FrameHashD>('mkpx_frame_hash');
  late final _FrameThumbD _frameThumb = _lib.lookupFunction<_FrameThumbC, _FrameThumbD>('mkpx_frame_thumb');
  late final _LayerThumbD _layerThumb = _lib.lookupFunction<_LayerThumbC, _LayerThumbD>('mkpx_layer_thumb');
  late final _LayerHashD _layerHash = _lib.lookupFunction<_LayerHashC, _LayerHashD>('mkpx_layer_hash');
  late final _SaveD _save = _lib.lookupFunction<_SaveC, _SaveD>('mkpx_save');
  // Same C signature as mkpx_save (Session*, out_len) → bytes; wraps the plain bytes in DEFLATE.
  late final _SaveD _saveCompact = _lib.lookupFunction<_SaveC, _SaveD>('mkpx_save_compact');
  late final _LoadD _load = _lib.lookupFunction<_LoadC, _LoadD>('mkpx_load');
  late final _FreeStringD _freeStr = _lib.lookupFunction<_FreeStringC, _FreeStringD>('mkpx_free_string');
  late final _FreeBytesD _freeBytes = _lib.lookupFunction<_FreeBytesC, _FreeBytesD>('mkpx_free_bytes');
  late final _ImportD _import = _lib.lookupFunction<_ImportC, _ImportD>('mkpx_import');
  late final _ExportPngD _exportPng = _lib.lookupFunction<_ExportPngC, _ExportPngD>('mkpx_export_png');
  late final _ExportLayerPngD _exportLayerPng = _lib.lookupFunction<_ExportLayerPngC, _ExportLayerPngD>('mkpx_export_layer_png');
  // The still-WebP twins share the PNG exports' C signatures.
  late final _ExportPngD _exportFrameWebp = _lib.lookupFunction<_ExportPngC, _ExportPngD>('mkpx_export_frame_webp');
  late final _ExportLayerPngD _exportLayerWebp = _lib.lookupFunction<_ExportLayerPngC, _ExportLayerPngD>('mkpx_export_layer_webp');
  late final _ExportGifD _exportGif = _lib.lookupFunction<_ExportGifC, _ExportGifD>('mkpx_export_gif');
  // Same C signature as export_gif (Session*, out_len) → bytes.
  late final _ExportGifD _exportWebp = _lib.lookupFunction<_ExportGifC, _ExportGifD>('mkpx_export_webp');
  // Export progress/cancel are PROCESS-WIDE in the engine library (no session argument): the
  // encode isolate writes them, the UI isolate polls them.
  late final _ExportProgressD _exportProgress = _lib.lookupFunction<_ExportProgressC, _ExportProgressD>('mkpx_export_progress');
  late final _ExportVoidD _exportProgressReset = _lib.lookupFunction<_ExportVoidC, _ExportVoidD>('mkpx_export_progress_reset');
  late final _ExportVoidD _exportCancel = _lib.lookupFunction<_ExportVoidC, _ExportVoidD>('mkpx_export_cancel');

  Engine(int w, int h) : _lib = _open() {
    _s = _new(w, h);
    if (_s == nullptr) throw Exception('mkpx_new failed');
  }

  int get width => _width(_s);
  int get height => _height(_s);

  /// Size of the buffer [display] returns and [outlineMask] fills: the whole storage area
  /// (canvas + off-canvas gutter) when the overscan view is on, else the canvas.
  int get displayWidth => _displayWidth(_s);
  int get displayHeight => _displayHeight(_s);
  int get frameCount => _frameCount(_s);
  int get activeFrame => _activeFrame(_s);
  int get playFrame => _playFrame(_s);
  int get primaryColor => _primary(_s); // 0xRRGGBBAA

  /// Run a DSL script; returns null on success or an error message.
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

  /// Active-frame display RGBA bytes (with overlays).
  Uint8List display({bool onion = false, bool grid = false, bool checker = true}) {
    final cap = displayWidth * displayHeight * 4; // storage-sized under the overscan view
    final out = malloc<Uint8>(cap);
    final n = _display(_s, onion ? 1 : 0, grid ? 1 : 0, checker ? 1 : 0, out, cap);
    final bytes = Uint8List.fromList(out.asTypedList(n < 0 ? 0 : n));
    malloc.free(out);
    return bytes;
  }

  Uint8List compositeFrame(int frame) {
    final cap = width * height * 4;
    final out = malloc<Uint8>(cap);
    final n = _composite(_s, frame, out, cap);
    final bytes = Uint8List.fromList(out.asTypedList(n < 0 ? 0 : n));
    malloc.free(out);
    return bytes;
  }

  String stateJson() {
    final p = _state(_s);
    final s = p.toDartString();
    _freeStr(p);
    return s;
  }

  /// Low-64-bit content hash of a frame (for thumbnail cache invalidation).
  int frameHash(int frame) => _frameHash(_s, frame);

  /// A `tw`×`th` nearest-downscaled composite of `frame` (straight RGBA bytes).
  Uint8List frameThumb(int frame, int tw, int th) {
    final cap = tw * th * 4;
    final out = malloc<Uint8>(cap);
    final n = _frameThumb(_s, frame, tw, th, out, cap);
    final bytes = n > 0 ? Uint8List.fromList(out.asTypedList(n)) : Uint8List(0);
    malloc.free(out);
    return bytes;
  }

  /// Low-64-bit content hash of one layer (within `frame`) — for layer thumbnail cache invalidation.
  int layerHash(int frame, int layer) => _layerHash(_s, frame, layer);

  /// A `tw`×`th` nearest-downscaled thumbnail of a single layer's raw pixels (straight RGBA,
  /// transparent where empty).
  Uint8List layerThumb(int frame, int layer, int tw, int th) {
    final cap = tw * th * 4;
    final out = malloc<Uint8>(cap);
    final n = _layerThumb(_s, frame, layer, tw, th, out, cap);
    final bytes = n > 0 ? Uint8List.fromList(out.asTypedList(n)) : Uint8List(0);
    malloc.free(out);
    return bytes;
  }

  /// 1-byte-per-pixel selection coverage (1=selected) for drawing the outline; empty if none.
  Uint8List outlineMask() {
    final cap = displayWidth * displayHeight; // storage-sized under the overscan view
    if (cap <= 0) return Uint8List(0);
    final out = malloc<Uint8>(cap);
    final n = _outline(_s, out, cap);
    final bytes = n > 0 ? Uint8List.fromList(out.asTypedList(n)) : Uint8List(0);
    malloc.free(out);
    return bytes;
  }

  Uint8List save() {
    final lenPtr = malloc<Uint64>();
    final p = _save(_s, lenPtr);
    final len = lenPtr.value;
    final bytes = Uint8List.fromList(p.asTypedList(len));
    _freeBytes(p, len);
    malloc.free(lenPtr);
    return bytes;
  }

  /// Serialize to a **compact** (DEFLATE-wrapped) `.mkpx` — for the explicit "Save" / portable export
  /// only. Autosave and library persistence use [save] (plain, cheap); both forms load back via
  /// [load], which auto-detects the envelope.
  Uint8List saveCompact() {
    final lenPtr = malloc<Uint64>();
    final p = _saveCompact(_s, lenPtr);
    final len = lenPtr.value;
    final bytes = Uint8List.fromList(p.asTypedList(len));
    _freeBytes(p, len);
    malloc.free(lenPtr);
    return bytes;
  }

  bool load(Uint8List data) {
    final p = malloc<Uint8>(data.length);
    p.asTypedList(data.length).setAll(0, data);
    final ok = _load(_s, p, data.length) == 0;
    malloc.free(p);
    return ok;
  }

  /// Import an image; mode 0=Fit,1=Stretch,2=Crop. Pass a crop rect (source pixels) to use an
  /// explicit interactive crop region, placed 1:1 centered on the canvas (downscaled to fit only
  /// when larger than the canvas, never upscaled).
  bool importImage(Uint8List data,
      {int mode = 0, bool asLayer = true, int startFrame = 0, int cropX = 0, int cropY = 0, int cropW = 0, int cropH = 0}) {
    final p = malloc<Uint8>(data.length);
    p.asTypedList(data.length).setAll(0, data);
    final ok = _import(_s, p, data.length, mode, asLayer ? 1 : 0, startFrame, cropX, cropY, cropW, cropH) == 0;
    malloc.free(p);
    return ok;
  }

  // `scale` on every export is an integer nearest-neighbour upscale (1..=32, clamped engine-side).
  Uint8List exportPng(int frame, {int scale = 1}) {
    final lenPtr = malloc<Uint64>();
    final p = _exportPng(_s, frame, scale, lenPtr);
    final out = p == nullptr ? Uint8List(0) : Uint8List.fromList(p.asTypedList(lenPtr.value));
    if (p != nullptr) _freeBytes(p, lenPtr.value);
    malloc.free(lenPtr);
    return out;
  }

  /// One layer of one frame as a PNG — the layer's own pixels (straight alpha), not the composite.
  Uint8List exportLayerPng(int frame, int layer, {int scale = 1}) {
    final lenPtr = malloc<Uint64>();
    final p = _exportLayerPng(_s, frame, layer, scale, lenPtr);
    final out = p == nullptr ? Uint8List(0) : Uint8List.fromList(p.asTypedList(lenPtr.value));
    if (p != nullptr) _freeBytes(p, lenPtr.value);
    malloc.free(lenPtr);
    return out;
  }

  /// One frame as a LOSSLESS static WebP — the still twin of [exportPng] (distinct from
  /// [exportWebp], which exports the whole animation).
  Uint8List exportFrameWebp(int frame, {int scale = 1}) {
    final lenPtr = malloc<Uint64>();
    final p = _exportFrameWebp(_s, frame, scale, lenPtr);
    final out = p == nullptr ? Uint8List(0) : Uint8List.fromList(p.asTypedList(lenPtr.value));
    if (p != nullptr) _freeBytes(p, lenPtr.value);
    malloc.free(lenPtr);
    return out;
  }

  /// One layer of one frame as a LOSSLESS static WebP — the still twin of [exportLayerPng].
  Uint8List exportLayerWebp(int frame, int layer, {int scale = 1}) {
    final lenPtr = malloc<Uint64>();
    final p = _exportLayerWebp(_s, frame, layer, scale, lenPtr);
    final out = p == nullptr ? Uint8List(0) : Uint8List.fromList(p.asTypedList(lenPtr.value));
    if (p != nullptr) _freeBytes(p, lenPtr.value);
    malloc.free(lenPtr);
    return out;
  }

  Uint8List exportGif({int scale = 1}) {
    final lenPtr = malloc<Uint64>();
    final p = _exportGif(_s, scale, lenPtr);
    final out = p == nullptr ? Uint8List(0) : Uint8List.fromList(p.asTypedList(lenPtr.value));
    if (p != nullptr) _freeBytes(p, lenPtr.value);
    malloc.free(lenPtr);
    return out;
  }

  /// Lossless WebP (static for one frame, animated WebP for many) — the recommended Club format.
  Uint8List exportWebp({int scale = 1}) {
    final lenPtr = malloc<Uint64>();
    final p = _exportWebp(_s, scale, lenPtr);
    final out = p == nullptr ? Uint8List(0) : Uint8List.fromList(p.asTypedList(lenPtr.value));
    if (p != nullptr) _freeBytes(p, lenPtr.value);
    malloc.free(lenPtr);
    return out;
  }

  /// Progress of the multi-frame export in flight (GIF/WebP), as (done, total) steps — one step
  /// per frame composited plus one per frame encoded, so total = 2 × frames. (0, 0) when no
  /// export has started (or after [resetExportProgress]). The counters live process-wide in the
  /// engine library, so the UI isolate can poll an export running on the encode isolate.
  (int, int) get exportProgress {
    final v = _exportProgress();
    return (v & 0xFFFFFFFF, v >>> 32);
  }

  /// Clear the progress pair before spawning an export, so the dialog never briefly shows the
  /// previous export's finished bar while the new isolate is still starting up.
  void resetExportProgress() => _exportProgressReset();

  /// Ask the export in flight to stop at its next frame boundary; its result comes back empty.
  void cancelExport() => _exportCancel();

  void dispose() => _freeS(_s);

  // ---- process-wide export progress, readable without owning an Engine ----
  // The GIF/WebP export counters live in the DLL's process memory (not per-session), so the shared
  // share flow (lib/share) can drive its progress dialog without holding an Engine instance.
  static final DynamicLibrary _staticLib = _open();
  static final _ExportProgressD _sProgress =
      _staticLib.lookupFunction<_ExportProgressC, _ExportProgressD>('mkpx_export_progress');
  static final _ExportVoidD _sProgressReset =
      _staticLib.lookupFunction<_ExportVoidC, _ExportVoidD>('mkpx_export_progress_reset');
  static final _ExportVoidD _sCancel =
      _staticLib.lookupFunction<_ExportVoidC, _ExportVoidD>('mkpx_export_cancel');

  static (int, int) get exportProgressStatic {
    final v = _sProgress();
    return (v & 0xFFFFFFFF, v >>> 32);
  }

  static void resetExportProgressStatic() => _sProgressReset();
  static void cancelExportStatic() => _sCancel();

  /// Build a throwaway document from a decoded raster (`width`×`height`, any supported still or
  /// animation) and encode it to `format` ('gif' | 'webp' | 'png') at `scale`, **off the UI thread**.
  /// Used by the shared share flow to re-render a Club artwork's downloaded pixels to a shareable
  /// GIF / lossless WebP / PNG. Progress is reported via [exportProgressStatic]. Empty on failure.
  static Future<Uint8List> encodeRasterInBackground(Uint8List raster,
      {required int width, required int height, required String format, int scale = 1}) async {
    try {
      return await Isolate.run(() => _encodeRaster(raster, width, height, format, scale));
    } catch (_) {
      return _encodeRaster(raster, width, height, format, scale);
    }
  }

  static Uint8List _encodeRaster(Uint8List raster, int width, int height, String format, int scale) {
    final e = Engine(width, height);
    try {
      // Stretch the whole render onto a native-sized canvas (integer nearest → exact native pixels
      // when the render is a clean integer upscale), pulling in every animation frame.
      if (!e.importImage(raster, mode: 1, asLayer: false, startFrame: 0)) return Uint8List(0);
      switch (format) {
        case 'webp':
          return e.exportWebp(scale: scale);
        case 'gif':
          return e.exportGif(scale: scale);
        default:
          return e.exportPng(0, scale: scale); // static → PNG of the single frame
      }
    } finally {
      e.dispose();
    }
  }

  /// Encode `docBytes` (a `.mkpx` snapshot) to the given `format` ('webp' | 'gif' | 'png' |
  /// 'frame-webp' | 'layer-png' | 'layer-webp') **off the UI thread**: a background isolate builds its own engine from the
  /// snapshot and runs the (potentially slow, multi-frame) encode, so the editor stays responsive.
  /// Falls back to a synchronous encode if the isolate can't run. The opaque session pointer is
  /// never shared across isolates; each builds its own from the bytes. [audit F-12]
  static Future<Uint8List> encodeInBackground(Uint8List docBytes,
      {required String format, int frame = 0, int layer = 0, int scale = 1}) async {
    try {
      return await Isolate.run(() => _encodeFromBytes(docBytes, format: format, frame: frame, layer: layer, scale: scale));
    } catch (_) {
      return _encodeFromBytes(docBytes, format: format, frame: frame, layer: layer, scale: scale);
    }
  }

  static Uint8List _encodeFromBytes(Uint8List docBytes,
      {required String format, int frame = 0, int layer = 0, int scale = 1}) {
    final e = Engine(8, 8);
    try {
      if (!e.load(docBytes)) return Uint8List(0);
      switch (format) {
        case 'webp':
          return e.exportWebp(scale: scale);
        case 'gif':
          return e.exportGif(scale: scale);
        case 'frame-webp':
          return e.exportFrameWebp(frame, scale: scale);
        case 'layer-png':
          return e.exportLayerPng(frame, layer, scale: scale);
        case 'layer-webp':
          return e.exportLayerWebp(frame, layer, scale: scale);
        default:
          return e.exportPng(frame, scale: scale);
      }
    } finally {
      e.dispose();
    }
  }
}

List<int> utf8Encode(String s) => const Utf8Encoder().convert(s);
