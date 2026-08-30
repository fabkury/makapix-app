// Dart FFI bindings to the Makapix engine C ABI (makapix_ffi.dll). See crates/ffi.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'dev/battery_stats.dart';

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
typedef _U64C = Uint64 Function(Pointer<Void>);
typedef _U64D = int Function(Pointer<Void>);
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
typedef _ClipRgbaC = Int32 Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _ClipRgbaD = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _LayerThumbC = Int32 Function(Pointer<Void>, Uint32, Uint32, Uint32, Uint32, Pointer<Uint8>, IntPtr);
typedef _LayerThumbD = int Function(Pointer<Void>, int, int, int, int, Pointer<Uint8>, int);
typedef _LayerHashC = Uint64 Function(Pointer<Void>, Uint32, Uint32);
typedef _LayerHashD = int Function(Pointer<Void>, int, int);
typedef _SaveC = Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint64>);
typedef _SaveD = Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint64>);
typedef _SaveMetaC = Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint8>, IntPtr, Pointer<Uint64>);
typedef _SaveMetaD = Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>);
typedef _ReadMetaC = Pointer<Utf8> Function(Pointer<Uint8>, IntPtr);
typedef _ReadMetaD = Pointer<Utf8> Function(Pointer<Uint8>, int);
typedef _LoadC = Int32 Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _LoadD = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _FreeStringC = Void Function(Pointer<Utf8>);
typedef _FreeStringD = void Function(Pointer<Utf8>);
typedef _FreeBytesC = Void Function(Pointer<Uint8>, Uint64);
typedef _FreeBytesD = void Function(Pointer<Uint8>, int);
typedef _ImportC = Int32 Function(Pointer<Void>, Pointer<Uint8>, IntPtr, Int32, Int32, Uint32, Int32, Int32, Int32, Int32);
typedef _ImportD = int Function(Pointer<Void>, Pointer<Uint8>, int, int, int, int, int, int, int, int);
typedef _DecodeImageC = Pointer<Uint8> Function(Pointer<Uint8>, IntPtr, Pointer<Uint64>, Pointer<Int32>);
typedef _DecodeImageD = Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Uint64>, Pointer<Int32>);
typedef _ExportPngC = Pointer<Uint8> Function(Pointer<Void>, Uint32, Uint32, Pointer<Uint64>);
typedef _ExportPngD = Pointer<Uint8> Function(Pointer<Void>, int, int, Pointer<Uint64>);
typedef _ExportLayerPngC = Pointer<Uint8> Function(Pointer<Void>, Uint32, Uint32, Uint32, Pointer<Uint64>);
typedef _ExportLayerPngD = Pointer<Uint8> Function(Pointer<Void>, int, int, int, Pointer<Uint64>);
// GIF carries an extra out-flags pointer (bit 0 = semi-transparent pixels were flattened to
// GIF's 1-bit alpha) — the WebP export keeps the plain bytes+len shape.
typedef _ExportGifC = Pointer<Uint8> Function(Pointer<Void>, Uint32, Pointer<Uint64>, Pointer<Uint32>);
typedef _ExportGifD = Pointer<Uint8> Function(Pointer<Void>, int, Pointer<Uint64>, Pointer<Uint32>);
typedef _ExportWebpC = Pointer<Uint8> Function(Pointer<Void>, Uint32, Pointer<Uint64>);
typedef _ExportWebpD = Pointer<Uint8> Function(Pointer<Void>, int, Pointer<Uint64>);
typedef _ExportProgressC = Uint64 Function();
typedef _ExportProgressD = int Function();
typedef _ExportVoidC = Void Function();
typedef _ExportVoidD = void Function();
// Replay checkpoints (Journal scrubbing) — crates/ffi mkpx_checkpoint_*.
typedef _CkptTakeC = Int64 Function(Pointer<Void>);
typedef _CkptTakeD = int Function(Pointer<Void>);
typedef _CkptRestoreC = Int32 Function(Pointer<Void>, Uint32);
typedef _CkptRestoreD = int Function(Pointer<Void>, int);
typedef _CkptIdsC = Uint32 Function(Pointer<Void>, Pointer<Uint32>, Uint32);
typedef _CkptIdsD = int Function(Pointer<Void>, Pointer<Uint32>, int);
// Timelapse export — crates/ffi mkpx_timelapse_* / mkpx_tl_encode_*.
typedef _TlFrameC = Pointer<Uint8> Function(Pointer<Void>, Uint32, Uint32, Uint32, Uint32, Uint32, Int32, Int32, Pointer<Uint64>);
typedef _TlFrameD = Pointer<Uint8> Function(Pointer<Void>, int, int, int, int, int, int, int, Pointer<Uint64>);
typedef _TlOverlayC = Int32 Function(Pointer<Uint8>, Uint32, Uint32, Int32, Int32);
typedef _TlOverlayD = int Function(Pointer<Uint8>, int, int, int, int);
typedef _TlBeginC = Int32 Function(Int32, Uint32, Uint32);
typedef _TlBeginD = int Function(int, int, int);
typedef _TlPushC = Int32 Function(Pointer<Uint8>, Uint64, Uint32);
typedef _TlPushD = int Function(Pointer<Uint8>, int, int);
typedef _TlEndC = Pointer<Uint8> Function(Pointer<Uint64>);
typedef _TlEndD = Pointer<Uint8> Function(Pointer<Uint64>);

DynamicLibrary _open() {
  // Android: the engine ships as libmakapix_ffi.so bundled in the APK (jniLibs).
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libmakapix_ffi.so');
  }
  // iOS: the engine ships as a dynamic framework embedded in Runner.app/Frameworks
  // (built by build_ios.sh, vendored via app/ios/makapix_ffi.podspec). dlopen resolves
  // the relative path through @rpath (@executable_path/Frameworks). It was previously
  // statically linked + DynamicLibrary.process(), but Xcode 26's linker dead-strips the
  // symbols out of the main executable's export table (2026-07-09) — don't go back.
  if (Platform.isIOS) {
    return DynamicLibrary.open('MakapixFFI.framework/MakapixFFI');
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

/// Outcome of an image import (decode or apply). [failed] = undecodable or corrupt input;
/// [tooLarge] = valid input refused by the codec's decode size gates (4096×4096 per frame,
/// 1024 frames, 384 MiB decoded — crates/codec); [refused] = the engine's memory-budget gate
/// rolled the whole import back (the document is unchanged). All three are worth telling the
/// user apart.
enum ImportStatus { ok, failed, tooLarge, refused }

/// Outcome of loading a `.mkpx` into the engine — mirrors mkpx_load's return codes
/// (crates/ffi/src/lib.rs; keep the two in sync).
enum LoadStatus {
  ok,

  /// Loaded fully, but the file's stored content hash didn't match the rebuilt document.
  /// Diagnostic only (e.g. written by a newer build with a different hash rule) — treat as
  /// success; callers log it, never surface it.
  okWithWarnings,

  /// Neither the plain nor the compact `.mkpx` signature.
  notMkpx,

  /// Written by a newer (or unknown) version of the format.
  unsupportedVersion,

  corrupt,

  /// Refused by the engine's document memory budget — too big for this device.
  overBudget,

  failed;

  /// The document is in the engine and usable.
  bool get loaded => this == LoadStatus.ok || this == LoadStatus.okWithWarnings;
}

// META wire-format separators shared with crates/ffi (`parse_packed_meta`): US (0x1F) between
// key and value, RS (0x1E) between records — characters that cannot appear in the sqids, flags,
// and format names the shell stores.
const String _metaKV = '\u001F';
const String _metaRec = '\u001E';

/// Pack `.mkpx` META entries for the ABI crossing (both directions): UTF-8 records of
/// `key U+001F value` joined by U+001E. Entries containing a separator are dropped rather than
/// corrupting the stream. Top-level so pure-Dart tests cover the packing without the engine
/// binary.
String packMkpxMeta(Map<String, String> entries) => entries.entries
    .where((e) =>
        !e.key.contains(_metaKV) &&
        !e.key.contains(_metaRec) &&
        !e.value.contains(_metaKV) &&
        !e.value.contains(_metaRec))
    .map((e) => '${e.key}$_metaKV${e.value}')
    .join(_metaRec);

/// Inverse of [packMkpxMeta]; malformed records (no separator) are skipped.
Map<String, String> unpackMkpxMeta(String packed) {
  final out = <String, String>{};
  if (packed.isEmpty) return out;
  for (final rec in packed.split(_metaRec)) {
    final i = rec.indexOf(_metaKV);
    if (i < 0) continue;
    out[rec.substring(0, i)] = rec.substring(i + 1);
  }
  return out;
}

/// Top-level (not on [Engine]) so pure-Dart tests cover it without the engine binary.
/// Unknown codes map to [LoadStatus.failed], never to success.
LoadStatus loadStatusFromRc(int rc) => switch (rc) {
      0 => LoadStatus.ok,
      1 => LoadStatus.okWithWarnings,
      -2 => LoadStatus.notMkpx,
      -3 => LoadStatus.unsupportedVersion,
      -4 => LoadStatus.corrupt,
      -5 => LoadStatus.overBudget,
      _ => LoadStatus.failed,
    };

/// A decoded-frames blob produced by [Engine.decodeImageInBackground], living in the engine
/// library's native heap (NOT GC-tracked). Apply it with [Engine.importDecoded] and ALWAYS
/// [dispose] it in a `finally` — on every path, including when the import is never applied.
class DecodedImage {
  final int _addr;
  final int _len;
  bool _freed = false;
  DecodedImage._(this._addr, this._len);

  void dispose() {
    if (_freed) return;
    _freed = true;
    Engine._sFreeBytes(Pointer<Uint8>.fromAddress(_addr), _len);
  }
}

class Engine {
  final DynamicLibrary _lib;
  late final Pointer<Void> _s;

  // Reused native scratch buffer for the per-pointer-move display/composite reads (see [display]).
  // Grown on demand, freed in [dispose]; never shrunk.
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
  late final _StateD _memJson = _lib.lookupFunction<_StateC, _StateD>('mkpx_mem_json');
  late final _StateD _usedColors = _lib.lookupFunction<_StateC, _StateD>('mkpx_used_colors_json');
  late final _U64D _saveEstimate = _lib.lookupFunction<_U64C, _U64D>('mkpx_save_estimate');
  late final _OutlineD _outline = _lib.lookupFunction<_OutlineC, _OutlineD>('mkpx_outline_mask');
  late final _U32D _outlinePresent = _lib.lookupFunction<_U32C, _U32D>('mkpx_outline_present');
  late final _U64D _playStatusRaw = _lib.lookupFunction<_U64C, _U64D>('mkpx_play_status');
  late final _FrameHashD _frameHash = _lib.lookupFunction<_FrameHashC, _FrameHashD>('mkpx_frame_hash');
  late final _FrameThumbD _frameThumb = _lib.lookupFunction<_FrameThumbC, _FrameThumbD>('mkpx_frame_thumb');
  late final _ClipRgbaD _clipboardRgba = _lib.lookupFunction<_ClipRgbaC, _ClipRgbaD>('mkpx_clipboard_rgba');
  late final _LayerThumbD _layerThumb = _lib.lookupFunction<_LayerThumbC, _LayerThumbD>('mkpx_layer_thumb');
  late final _LayerHashD _layerHash = _lib.lookupFunction<_LayerHashC, _LayerHashD>('mkpx_layer_hash');
  late final _SaveD _save = _lib.lookupFunction<_SaveC, _SaveD>('mkpx_save');
  // Same C signature as mkpx_save (Session*, out_len) → bytes; wraps the plain bytes in DEFLATE.
  late final _SaveD _saveCompact = _lib.lookupFunction<_SaveC, _SaveD>('mkpx_save_compact');
  // The meta-carrying save twins: (Session*, packed_meta, meta_len, out_len) → bytes.
  late final _SaveMetaD _saveMeta = _lib.lookupFunction<_SaveMetaC, _SaveMetaD>('mkpx_save_meta');
  late final _SaveMetaD _saveCompactMeta = _lib.lookupFunction<_SaveMetaC, _SaveMetaD>('mkpx_save_compact_meta');
  late final _LoadD _load = _lib.lookupFunction<_LoadC, _LoadD>('mkpx_load');
  late final _FreeStringD _freeStr = _lib.lookupFunction<_FreeStringC, _FreeStringD>('mkpx_free_string');
  late final _FreeBytesD _freeBytes = _lib.lookupFunction<_FreeBytesC, _FreeBytesD>('mkpx_free_bytes');
  late final _ImportD _import = _lib.lookupFunction<_ImportC, _ImportD>('mkpx_import');
  // Same C signature as mkpx_import, but takes a mkpx_decode_image blob instead of file bytes.
  late final _ImportD _importDecoded = _lib.lookupFunction<_ImportC, _ImportD>('mkpx_import_decoded');
  late final _ExportPngD _exportPng = _lib.lookupFunction<_ExportPngC, _ExportPngD>('mkpx_export_png');
  late final _ExportLayerPngD _exportLayerPng = _lib.lookupFunction<_ExportLayerPngC, _ExportLayerPngD>('mkpx_export_layer_png');
  // The still-WebP twins share the PNG exports' C signatures.
  late final _ExportPngD _exportFrameWebp = _lib.lookupFunction<_ExportPngC, _ExportPngD>('mkpx_export_frame_webp');
  late final _ExportLayerPngD _exportLayerWebp = _lib.lookupFunction<_ExportLayerPngC, _ExportLayerPngD>('mkpx_export_layer_webp');
  late final _ExportGifD _exportGif = _lib.lookupFunction<_ExportGifC, _ExportGifD>('mkpx_export_gif');
  late final _ExportWebpD _exportWebp = _lib.lookupFunction<_ExportWebpC, _ExportWebpD>('mkpx_export_webp');
  // Export progress/cancel are PROCESS-WIDE in the engine library (no session argument): the
  // encode isolate writes them, the UI isolate polls them.
  late final _ExportProgressD _exportProgress = _lib.lookupFunction<_ExportProgressC, _ExportProgressD>('mkpx_export_progress');
  late final _ExportVoidD _exportProgressReset = _lib.lookupFunction<_ExportVoidC, _ExportVoidD>('mkpx_export_progress_reset');
  late final _ExportVoidD _exportCancel = _lib.lookupFunction<_ExportVoidC, _ExportVoidD>('mkpx_export_cancel');
  // Replay checkpoints (Journal scrubbing).
  late final _CkptTakeD _ckptTake = _lib.lookupFunction<_CkptTakeC, _CkptTakeD>('mkpx_checkpoint_take');
  late final _CkptRestoreD _ckptRestore = _lib.lookupFunction<_CkptRestoreC, _CkptRestoreD>('mkpx_checkpoint_restore');
  late final _U32D _ckptCount = _lib.lookupFunction<_U32C, _U32D>('mkpx_checkpoint_count');
  late final _CkptIdsD _ckptIds = _lib.lookupFunction<_CkptIdsC, _CkptIdsD>('mkpx_checkpoint_ids');
  late final _FreeD _ckptClear = _lib.lookupFunction<_FreeC, _FreeD>('mkpx_checkpoint_clear');
  late final _StateD _docHash = _lib.lookupFunction<_StateC, _StateD>('mkpx_doc_hash');
  // Timelapse export (the frame pipeline + the push-mode WebP/GIF encoder).
  late final _TlFrameD _tlFrame = _lib.lookupFunction<_TlFrameC, _TlFrameD>('mkpx_timelapse_frame');
  late final _TlOverlayD _tlOverlay = _lib.lookupFunction<_TlOverlayC, _TlOverlayD>('mkpx_timelapse_set_overlay');
  late final _TlBeginD _tlBegin = _lib.lookupFunction<_TlBeginC, _TlBeginD>('mkpx_tl_encode_begin');
  late final _TlPushD _tlPush = _lib.lookupFunction<_TlPushC, _TlPushD>('mkpx_tl_encode_push');
  late final _TlEndD _tlEnd = _lib.lookupFunction<_TlEndC, _TlEndD>('mkpx_tl_encode_end');
  late final _ExportVoidD _tlAbort = _lib.lookupFunction<_ExportVoidC, _ExportVoidD>('mkpx_tl_encode_abort');

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

  /// Playback status in one O(log frames) scalar call: (current play frame, µs until the
  /// visible frame can next change). The wait is a LOWER bound (never an overestimate),
  /// so a timer armed with it cannot show a frame late — see Session::play_status.
  /// Powers the hybrid ticker/timer playback clock. [battery F15/R3]
  (int, int) get playStatus {
    final v = _playStatusRaw(_s);
    return (v >>> 32, v & 0xFFFFFFFF);
  }
  int get primaryColor => _primary(_s); // 0xRRGGBBAA

  /// Run a DSL script; returns null on success or an error message.
  String? run(String script) {
    BatteryStats.dslRun();
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
  ///
  /// Returns a **view into a reused native scratch buffer** — no per-call malloc/free and no
  /// Dart-heap copy (the two per-pointer-move costs the fromList version paid). [audit C-1/#5]
  ///
  /// CONTRACT: the returned list is valid only until the next [display]/[compositeFrame] call, which
  /// overwrites the same buffer. Both callers (`_redraw`, `_decodePlayFrame`) consume it
  /// synchronously — `premultiplyRgbaInPlace` then `ui.decodeImageFromPixels`, which copies its input
  /// synchronously (via `ImmutableBuffer.fromUint8List` → native `_init`) before returning, so the
  /// buffer is free to reuse the moment `_decode` is invoked, even under overlapping redraws. Do NOT
  /// store the result, hand it to an isolate, or await before decoding. This safety is coupled to
  /// the engine's synchronous-copy behavior — RE-VERIFY on any Flutter/engine upgrade.
  Uint8List display({bool onion = false, bool grid = false, bool checker = true}) {
    BatteryStats.display();
    final cap = displayWidth * displayHeight * 4; // storage-sized under the overscan view
    final out = _ensureScratch(cap);
    final n = _display(_s, onion ? 1 : 0, grid ? 1 : 0, checker ? 1 : 0, out, cap);
    return out.asTypedList(n < 0 ? 0 : n);
  }

  /// One frame's composited RGBA. Same reused-scratch-buffer contract as [display] — see its doc.
  Uint8List compositeFrame(int frame) {
    BatteryStats.composite();
    final cap = width * height * 4;
    final out = _ensureScratch(cap);
    final n = _composite(_s, frame, out, cap);
    return out.asTypedList(n < 0 ? 0 : n);
  }

  String stateJson() {
    final p = _state(_s);
    final s = p.toDartString();
    _freeStr(p);
    return s;
  }

  /// Upper-bound estimate of the `.mkpx` payload [save] would produce (unique tile payload
  /// bytes). The engine's document budget already guarantees this stays under 320 MiB; exposed
  /// for telemetry and future pre-save checks.
  int saveEstimate() => _saveEstimate(_s);

  /// Engine-accounted memory census (tile-deduped) as JSON — see `probe::mem_report` on the Rust
  /// side. Powers the memory stress lab.
  String memJson() {
    final p = _memJson(_s);
    final s = p.toDartString();
    _freeStr(p);
    return s;
  }

  /// Unique colors used by the artwork as JSON: `{"colors":["#RRGGBBAA",...]}`, or
  /// `{"over_limit":true}` past 256 uniques (the engine aborts the scan early).
  String usedColorsJson() {
    final p = _usedColors(_s);
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

  /// The clipboard's pixels at native `w`×`h` (straight RGBA bytes) — the caller reads the
  /// dimensions from the state probe's `clipboard_size`. Empty when the clipboard is empty
  /// (or the size is stale).
  Uint8List clipboardRgba(int w, int h) {
    final cap = w * h * 4;
    if (cap <= 0) return Uint8List(0);
    final out = malloc<Uint8>(cap);
    final n = _clipboardRgba(_s, out, cap);
    final bytes = n > 0 ? Uint8List.fromList(out.asTypedList(n)) : Uint8List(0);
    malloc.free(out);
    return bytes;
  }

  /// Low-64-bit content hash of one layer (within `frame`) — for layer thumbnail cache invalidation.
  int layerHash(int frame, int layer) => _layerHash(_s, frame, layer);

  // ---- replay checkpoints (Journal scrubbing; see editor/replay/replay_host.dart) ----

  /// Take a replay checkpoint. Returns its STABLE id (>= 0), or -1 while a gesture/draft is
  /// open (retry at the next journal line). Older ids may be evicted by the engine's byte
  /// budget — resync with [checkpointIds] after takes.
  int checkpointTake() => _ckptTake(_s);

  /// Restore checkpoint [id]; false when the id is unknown (evicted/cleared).
  bool checkpointRestore(int id) => _ckptRestore(_s, id) == 0;

  int checkpointCount() => _ckptCount(_s);

  /// Live checkpoint ids, ascending. The engine caps live checkpoints at 512.
  List<int> checkpointIds() {
    const cap = 512;
    final out = malloc<Uint32>(cap);
    final n = _ckptIds(_s, out, cap);
    final ids = List<int>.generate(n < cap ? n : cap, (i) => out[i]);
    malloc.free(out);
    return ids;
  }

  /// Drop every checkpoint, freeing the retained tiles (call when the Replay view closes).
  void checkpointClear() => _ckptClear(_s);

  /// The document content hash as 32 hex digits — a replay-validation oracle (it excludes
  /// palettes/active_frame/selection by design; crash-sync markers use the byte-level FNV).
  String docHash() {
    final p = _docHash(_s);
    if (p == nullptr) return '';
    final s = p.toDartString();
    _freeStr(p);
    return s;
  }

  // ---- timelapse export (editor/replay/timelapse_export.dart) ----

  /// One timelapse output frame from the current session state: composite(frame) →
  /// flatten transparency → integer upscale ×scale → center-pad to outW×outH → overlay
  /// blit → RGBA8888 (format 0) or tightly-packed I420/BT.601 (format 1; even dims
  /// required). Empty on failure. bgRgba is 0xRRGGBBAA (alpha ignored — padding is
  /// opaque). [checker] flattens transparency over the editor canvas's checker (clipped
  /// to the artwork; padding stays bgRgba) instead of over bgRgba.
  Uint8List timelapseFrame(int frame, int scale, int outW, int outH, int bgRgba, int format,
      {bool checker = false}) {
    final lenPtr = malloc<Uint64>();
    final ptr = _tlFrame(_s, frame, scale, outW, outH, bgRgba, checker ? 1 : 0, format, lenPtr);
    final len = lenPtr.value;
    malloc.free(lenPtr);
    if (ptr == nullptr) return Uint8List(0);
    final bytes = Uint8List.fromList(ptr.asTypedList(len));
    _freeBytes(ptr, len);
    return bytes;
  }

  /// Register (or clear, with null) the process-wide finale overlay — the wordmark —
  /// blitted onto every subsequent [timelapseFrame] at (x, y) in OUTPUT coordinates.
  bool setTimelapseOverlay(Uint8List? rgba, int w, int h, int x, int y) {
    if (rgba == null || rgba.isEmpty || w == 0 || h == 0) {
      return _tlOverlay(nullptr, 0, 0, 0, 0) == 0;
    }
    final p = malloc<Uint8>(rgba.length);
    p.asTypedList(rgba.length).setAll(0, rgba);
    final rc = _tlOverlay(p, w, h, x, y); // the engine copies; free immediately
    malloc.free(p);
    return rc == 0;
  }

  /// Begin a push-mode timelapse encode (0 = GIF, 1 = animated lossless WebP) at output
  /// resolution w×h. One at a time, process-wide.
  bool tlEncodeBegin(int format, int w, int h) => _tlBegin(format, w, h) == 0;

  /// Push one RGBA output frame with its display duration. False aborts the encode.
  bool tlEncodePush(Uint8List rgba, int durationMs) {
    final p = malloc<Uint8>(rgba.length);
    p.asTypedList(rgba.length).setAll(0, rgba);
    final rc = _tlPush(p, rgba.length, durationMs);
    malloc.free(p);
    return rc == 0;
  }

  /// Finish the push-mode encode; empty on failure/no encode in flight.
  Uint8List tlEncodeEnd() {
    final lenPtr = malloc<Uint64>();
    final ptr = _tlEnd(lenPtr);
    final len = lenPtr.value;
    malloc.free(lenPtr);
    if (ptr == nullptr) return Uint8List(0);
    final bytes = Uint8List.fromList(ptr.asTypedList(len));
    _freeBytes(ptr, len);
    return bytes;
  }

  /// Drop an in-flight push-mode encode (cancel/cleanup). Idempotent.
  void tlEncodeAbort() => _tlAbort();

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
  ///
  /// Checks [outlinePresent] first: when nothing could be outlined (the plain-drawing hot
  /// path) this returns empty without the storage-sized malloc + FFI fill + Dart-heap copy
  /// that used to run per pointer event regardless. [battery F13]
  Uint8List outlineMask() {
    if (!outlinePresent) return Uint8List(0);
    BatteryStats.outlineMask();
    final cap = displayWidth * displayHeight; // storage-sized under the overscan view
    if (cap <= 0) return Uint8List(0);
    final out = malloc<Uint8>(cap);
    final n = _outline(_s, out, cap);
    final bytes = n > 0 ? Uint8List.fromList(out.asTypedList(n)) : Uint8List(0);
    malloc.free(out);
    return bytes;
  }

  /// Whether [outlineMask] could be non-empty — a cheap scalar (no mask is built).
  /// Conservative: true may still yield an empty mask; false never hides one.
  bool get outlinePresent => _outlinePresent(_s) != 0;

  Uint8List save() {
    // calloc (not malloc) so a null/failed return can't leave `len` reading uninitialized memory;
    // nullptr-guard like the export* paths; free the native buffer in a finally so an OutOfMemory
    // from the Dart-heap copy — most likely exactly when the process is already at its ceiling —
    // can't leak the whole serialized document. [audit] This is the 5-second autosave path.
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

  /// Serialize to a **compact** (DEFLATE-wrapped) `.mkpx` — for the explicit "Save" / portable export
  /// only. Autosave and library persistence use [save] (plain, cheap); both forms load back via
  /// [load], which auto-detects the envelope.
  Uint8List saveCompact() {
    // Same hardening as [save]: zero-init length, nullptr guard, free-in-finally. [audit]
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

  /// [save] with META entries riding inside the file (`META` chunk, format spec §11): [meta]
  /// is packed via [packMkpxMeta] and spliced by the FFI periphery. Empty [meta] == [save].
  Uint8List saveWithMeta(Map<String, String> meta) => _saveViaMeta(_saveMeta, meta);

  /// [saveCompact] with META entries (the splice happens before the DEFLATE wrap).
  Uint8List saveCompactWithMeta(Map<String, String> meta) => _saveViaMeta(_saveCompactMeta, meta);

  Uint8List _saveViaMeta(_SaveMetaD fn, Map<String, String> meta) {
    // Same hardening as [save]: zero-init length, nullptr guard, free-in-finally. [audit]
    final packed = utf8.encode(packMkpxMeta(meta));
    final metaPtr = packed.isEmpty ? nullptr : malloc<Uint8>(packed.length);
    if (metaPtr != nullptr) metaPtr.asTypedList(packed.length).setAll(0, packed);
    final lenPtr = calloc<Uint64>();
    try {
      final p = fn(_s, metaPtr, packed.length, lenPtr);
      if (p == nullptr) return Uint8List(0);
      final len = lenPtr.value;
      try {
        return Uint8List.fromList(p.asTypedList(len));
      } finally {
        _freeBytes(p, len);
      }
    } finally {
      calloc.free(lenPtr);
      if (metaPtr != nullptr) malloc.free(metaPtr);
    }
  }

  /// Read the string META entries out of `.mkpx` bytes — plain or compact, auto-detected —
  /// without loading the document. Empty map when the file carries none; null when the bytes
  /// are not a readable `.mkpx`. Static (session-free), like the background decode helpers.
  static Map<String, String>? readMkpxMeta(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final p = malloc<Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    try {
      final res = _sReadMeta(p, bytes.length);
      if (res == nullptr) return null;
      try {
        return unpackMkpxMeta(res.toDartString());
      } finally {
        _sFreeString(res);
      }
    } finally {
      malloc.free(p);
    }
  }

  LoadStatus load(Uint8List data) {
    final p = malloc<Uint8>(data.length);
    p.asTypedList(data.length).setAll(0, data);
    final rc = _load(_s, p, data.length);
    malloc.free(p);
    return loadStatusFromRc(rc);
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

  /// Apply a [DecodedImage] (from [decodeImageInBackground]) to the document — the placement
  /// half of [importImage], same `mode`/`asLayer`/crop semantics. Runs on the calling isolate
  /// against the live session, so it belongs on the UI isolate; the expensive decode already
  /// happened in the background. The caller still owns `img` (dispose it in a `finally`).
  ImportStatus importDecoded(DecodedImage img,
      {int mode = 0, bool asLayer = true, int startFrame = 0, int cropX = 0, int cropY = 0, int cropW = 0, int cropH = 0}) {
    if (img._freed) return ImportStatus.failed;
    final rc = _importDecoded(_s, Pointer<Uint8>.fromAddress(img._addr), img._len, mode,
        asLayer ? 1 : 0, startFrame, cropX, cropY, cropW, cropH);
    return switch (rc) {
      0 => ImportStatus.ok,
      -2 => ImportStatus.refused,
      _ => ImportStatus.failed,
    };
  }

  // `scale` on every export is an integer nearest-neighbor upscale (1..=32, clamped engine-side).
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

  /// Animated GIF export. GIF holds 1-bit transparency, so the engine thresholds alpha at 128;
  /// the returned flag is true when semi-transparent pixels were actually flattened — the
  /// caller uses it to tell the artist the look changed.
  (Uint8List, bool) exportGif({int scale = 1}) {
    final lenPtr = malloc<Uint64>();
    final flagsPtr = malloc<Uint32>();
    final p = _exportGif(_s, scale, lenPtr, flagsPtr);
    final out = p == nullptr ? Uint8List(0) : Uint8List.fromList(p.asTypedList(lenPtr.value));
    if (p != nullptr) _freeBytes(p, lenPtr.value);
    final flattened = (flagsPtr.value & 1) != 0;
    malloc.free(lenPtr);
    malloc.free(flagsPtr);
    return (out, flattened);
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

  void dispose() {
    if (_scratch != nullptr) {
      malloc.free(_scratch);
      _scratch = nullptr;
      _scratchCap = 0;
    }
    _freeS(_s);
  }

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

  // Session-free decode + free, bound on the static library handle so a background isolate
  // (and DecodedImage.dispose) can call them without owning an Engine instance.
  static final _DecodeImageD _sDecodeImage =
      _staticLib.lookupFunction<_DecodeImageC, _DecodeImageD>('mkpx_decode_image');
  static final _FreeBytesD _sFreeBytes =
      _staticLib.lookupFunction<_FreeBytesC, _FreeBytesD>('mkpx_free_bytes');
  static final _FreeStringD _sFreeString =
      _staticLib.lookupFunction<_FreeStringC, _FreeStringD>('mkpx_free_string');
  static final _ReadMetaD _sReadMeta =
      _staticLib.lookupFunction<_ReadMetaC, _ReadMetaD>('mkpx_read_meta');

  /// Decode an image file (GIF/PNG/APNG/JPEG/BMP/WebP) into engine-native decoded frames **off
  /// the UI thread** — the expensive half of an import (audit #3). Only the resulting buffer's
  /// native ADDRESS crosses back from the isolate: both isolates load the same engine library,
  /// so the buffer lives in shared process memory (the same property the export progress
  /// atomics rely on), and the opaque session pointer still never crosses [audit F-12]. Falls
  /// back to a synchronous decode if the isolate can't run. Returns the decoded image plus
  /// [ImportStatus.ok], or a null image plus the failure kind: [ImportStatus.tooLarge] when
  /// the file is valid but over the codec's decode size limits, [ImportStatus.failed]
  /// otherwise. The caller owns the image — dispose it in a `finally`.
  static Future<(DecodedImage?, ImportStatus)> decodeImageInBackground(Uint8List bytes) async {
    (int, int, int) r;
    try {
      r = await Isolate.run(() => _decodeImageNative(bytes));
    } catch (_) {
      r = _decodeImageNative(bytes);
    }
    if (r.$1 == 0) {
      return (null, r.$3 == -3 ? ImportStatus.tooLarge : ImportStatus.failed);
    }
    return (DecodedImage._(r.$1, r.$2), ImportStatus.ok);
  }

  /// (address, length, status) of a malloc'd decoded-frames blob; address 0 on failure with
  /// mkpx_decode_image's status code (-1 undecodable, -3 too large).
  static (int, int, int) _decodeImageNative(Uint8List bytes) {
    final p = malloc<Uint8>(bytes.length);
    final lenPtr = malloc<Uint64>();
    final statusPtr = malloc<Int32>();
    try {
      p.asTypedList(bytes.length).setAll(0, bytes);
      final out = _sDecodeImage(p, bytes.length, lenPtr, statusPtr);
      return out == nullptr ? (0, 0, statusPtr.value) : (out.address, lenPtr.value, 0);
    } finally {
      malloc.free(p);
      malloc.free(lenPtr);
      malloc.free(statusPtr);
    }
  }

  /// Build a throwaway document from a decoded raster (`width`×`height`, any supported still or
  /// animation) and encode it to `format` ('gif' | 'webp' | 'png') at `scale`, **off the UI thread**.
  /// Used by the shared share flow to re-render a Club artwork's downloaded pixels to a shareable
  /// GIF / lossless WebP / PNG. Progress is reported via [exportProgressStatic]. Returns
  /// (bytes, flattened): bytes empty on failure; flattened is true only for a GIF whose
  /// semi-transparent pixels were thresholded to 1-bit alpha (see [exportGif]).
  static Future<(Uint8List, bool)> encodeRasterInBackground(Uint8List raster,
      {required int width, required int height, required String format, int scale = 1}) async {
    try {
      return await Isolate.run(() => _encodeRaster(raster, width, height, format, scale));
    } catch (_) {
      return _encodeRaster(raster, width, height, format, scale);
    }
  }

  static (Uint8List, bool) _encodeRaster(Uint8List raster, int width, int height, String format, int scale) {
    final e = Engine(width, height);
    try {
      // Stretch the whole render onto a native-sized canvas (integer nearest → exact native pixels
      // when the render is a clean integer upscale), pulling in every animation frame.
      if (!e.importImage(raster, mode: 1, asLayer: false, startFrame: 0)) return (Uint8List(0), false);
      switch (format) {
        case 'webp':
          return (e.exportWebp(scale: scale), false);
        case 'gif':
          return e.exportGif(scale: scale);
        default:
          return (e.exportPng(0, scale: scale), false); // static → PNG of the single frame
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
  /// Returns (bytes, flattened): bytes empty on failure; flattened is true only for a GIF whose
  /// semi-transparent pixels were thresholded to 1-bit alpha (see [exportGif]).
  static Future<(Uint8List, bool)> encodeInBackground(Uint8List docBytes,
      {required String format, int frame = 0, int layer = 0, int scale = 1}) async {
    try {
      return await Isolate.run(() => _encodeFromBytes(docBytes, format: format, frame: frame, layer: layer, scale: scale));
    } catch (_) {
      return _encodeFromBytes(docBytes, format: format, frame: frame, layer: layer, scale: scale);
    }
  }

  static (Uint8List, bool) _encodeFromBytes(Uint8List docBytes,
      {required String format, int frame = 0, int layer = 0, int scale = 1}) {
    final e = Engine(8, 8);
    try {
      if (!e.load(docBytes).loaded) return (Uint8List(0), false);
      switch (format) {
        case 'webp':
          return (e.exportWebp(scale: scale), false);
        case 'gif':
          return e.exportGif(scale: scale);
        case 'frame-webp':
          return (e.exportFrameWebp(frame, scale: scale), false);
        case 'layer-png':
          return (e.exportLayerPng(frame, layer, scale: scale), false);
        case 'layer-webp':
          return (e.exportLayerWebp(frame, layer, scale: scale), false);
        default:
          return (e.exportPng(frame, scale: scale), false);
      }
    } finally {
      e.dispose();
    }
  }
}

List<int> utf8Encode(String s) => const Utf8Encoder().convert(s);
