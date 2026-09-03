// Shared image-share flow — the ONE code path behind both the editor's ☰ menu → Share and the
// Club artwork Share button. Lives at lib/share (a neutral module, not lib/club) because it uses
// the Rust engine as an offline codec (GIF / lossless WebP / PNG at scale, with progress); lib/club
// keeps its own code engine-free and just calls in here with already-downloaded bytes.
//
// Three reusable pieces (scale/format dialog · encode-with-progress · share-the-file) plus a
// high-level `shareRasterArtwork` used by the Club. The engine stays network-free: callers pass the
// raster bytes in; the download (if any) is theirs.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makapix_club/engine_ffi.dart';

// Warn (red alert + explicit re-confirmation) when an export's total output — width × height ×
// scale² × frames — exceeds this. ~64 million pixels ≈ 256 MB of RGBA work per pass, about where a
// mid-to-upper-range Android phone starts to struggle.
const kExportWarnPixels = 64 * 1000 * 1000;

// Last-used Share format for animations (GIF/WebP), shared by the editor and the Club so the choice
// carries across both.
const kShareFormatPref = 'share.animFormat_v1';

// The integer upscale factors offered in the export/share dialog (nearest-neighbor, pixels stay
// crisp). 2× was added to 1/4/8/16/32 so the smart default can land nearer the target on
// non-power-of-2 canvases.
const kExportScaleFactors = [1, 2, 4, 8, 16, 32];

// Target output size (longest side, px) the smart default aims for. Landing near this means most
// viewers/platforms display the artwork at (or below) its native size instead of applying smoothed
// bilinear/bicubic upscaling, which would blur the pixel art.
const kExportTargetLongestPx = 1024;

/// Pick the upscale factor whose output lands CLOSEST to [kExportTargetLongestPx] on the artwork's
/// longest side, so the export displays natively without smoothed upscaling. Factors that would trip
/// the very-large-export warning (see [kExportWarnPixels]) are skipped so the default stays one-tap;
/// on a tie the larger factor wins (leans toward never-upscaled). Falls back to the smallest factor
/// if every factor is too large (e.g. a huge many-frame animation).
int smartDefaultExportScale({
  required int width,
  required int height,
  required int frames,
  List<int> factors = kExportScaleFactors,
  int target = kExportTargetLongestPx,
  int warnPixels = kExportWarnPixels,
}) {
  final longest = width > height ? width : height;
  int? best;
  var bestDist = 1 << 62;
  for (final f in factors) {
    final totalPx = width * f * height * f * frames;
    if (totalPx > warnPixels) continue; // never auto-pick a size that raises the red re-confirm
    final dist = (longest * f - target).abs();
    if (best == null || dist <= bestDist) {
      // `<=` so that on an exact tie the later (larger) factor wins.
      best = f;
      bestDist = dist;
    }
  }
  return best ?? factors.first;
}

/// The caption text that accompanies a shared image. Title in quotes + the link when both exist.
String shareCaption(String title, String? url) {
  final t = title.trim();
  final u = (url ?? '').trim();
  if (t.isEmpty) return u;
  if (u.isEmpty) return t;
  return '"$t" — $u';
}

/// A filesystem-safe base name from an artwork title (falls back to "makapix").
String sanitizeShareFilename(String title) {
  final s = title.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return s.isEmpty ? 'makapix' : s;
}

/// Scale (+ optional format) picker. Returns (scale, format) — format is '' when none was offered —
/// or null on Cancel. A very large chosen size raises a red re-confirmation on the first press.
Future<(int, String)?> showExportScaleDialog({
  required BuildContext context,
  required int width,
  required int height,
  required int frames,
  String title = 'Export size',
  String action = 'Export',
  List<String> formats = const [],
  String initialFormat = '',
}) {
  var scale = smartDefaultExportScale(width: width, height: height, frames: frames);
  var format = formats.contains(initialFormat) ? initialFormat : (formats.isEmpty ? '' : formats.first);
  var warned = false;
  return showDialog<(int, String)>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final ow = width * scale, oh = height * scale;
      final totalPx = ow * oh * frames;
      final big = totalPx > kExportWarnPixels;
      return AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (formats.isNotEmpty) ...[
            Wrap(spacing: 6, children: [
              for (final f in formats)
                ChoiceChip(
                  label: Text(f),
                  selected: format == f,
                  selectedColor: const Color(0xFF30A050),
                  onSelected: (_) => setS(() => format = f),
                ),
            ]),
            const SizedBox(height: 6),
          ],
          Wrap(spacing: 6, children: [
            for (final s in kExportScaleFactors)
              ChoiceChip(
                label: Text('$s×'),
                selected: scale == s,
                selectedColor: const Color(0xFF30A050),
                onSelected: (_) => setS(() {
                  scale = s;
                  warned = false; // a newly chosen size gets its own re-confirmation
                }),
              ),
          ]),
          const SizedBox(height: 10),
          Text(
            frames > 1 ? 'Output: $ow × $oh px, $frames frames' : 'Output: $ow × $oh px',
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
          if (warned)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0x33E05050),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE05050)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber, color: Color(0xFFE05050), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Very large export: ${(totalPx / 1e6).toStringAsFixed(0)} million pixels. '
                      'This can take a long time and a lot of memory. $action anyway?',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFE05050)),
                    ),
                  ),
                ]),
              ),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: warned ? FilledButton.styleFrom(backgroundColor: const Color(0xFFE05050)) : null,
            onPressed: () {
              if (big && !warned) {
                setS(() => warned = true); // first press on a huge size only raises the alert
                return;
              }
              Navigator.pop(ctx, (scale, format));
            },
            child: Text(warned ? '$action anyway' : action),
          ),
        ],
      );
    }),
  );
}

/// Run `encode` behind a modal progress dialog that polls the engine's process-wide export progress
/// and offers Cancel (honored at the next frame boundary). Returns (bytes, canceled, flattened);
/// bytes is empty on failure or cancellation. `flattened` rides through from the encoder — true
/// only for a GIF whose semi-transparent pixels were thresholded to 1-bit alpha, so the caller
/// can tell the artist the look changed.
Future<(Uint8List, bool, bool)> encodeWithProgress({
  required BuildContext context,
  required String title,
  required Future<(Uint8List, bool)> Function() encode,
}) async {
  Engine.resetExportProgressStatic(); // the dialog must not briefly show the PREVIOUS export's bar
  var canceled = false;
  final future = encode();
  if (context.mounted) {
    var dialogOpen = true;
    Timer? poll;
    var canceling = false;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        poll ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (ctx.mounted) setS(() {});
        });
        final (done, total) = Engine.exportProgressStatic;
        return AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LinearProgressIndicator(value: total > 0 ? done / total : null),
            const SizedBox(height: 10),
            Text(
              total > 0 ? '${(100 * done / total).floor()}%' : 'Preparing…',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: canceling
                  ? null
                  : () => setS(() {
                        canceling = true;
                        canceled = true;
                        Engine.cancelExportStatic(); // honored at the next frame boundary
                      }),
              child: Text(canceling ? 'Canceling…' : 'Cancel'),
            ),
          ],
        );
      }),
    ).whenComplete(() {
      poll?.cancel();
      dialogOpen = false;
    }));
    final (bytes, flattened) = await future;
    if (dialogOpen && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return (bytes, canceled, flattened);
  }
  final (bytes, flattened) = await future;
  return (bytes, false, flattened);
}

/// Write already-encoded image bytes to a temp file and open the system share sheet, optionally with
/// accompanying `text` (a caption / link). A fresh per-share cache subdir is used and the PREVIOUS
/// one pruned (a receiver may read the file lazily after the sheet closes).
Future<void> shareImageBytes({
  required Uint8List bytes,
  required String filenameBase,
  required String ext,
  required String mime,
  String? text,
}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/share');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final f = File('${dir.path}/${sanitizeShareFilename(filenameBase)}.$ext');
  await f.writeAsBytes(bytes);
  final params = (text != null && text.trim().isNotEmpty)
      ? ShareParams(files: [XFile(f.path, mimeType: mime)], text: text)
      : ShareParams(files: [XFile(f.path, mimeType: mime)]);
  await SharePlus.instance.share(params);
}

/// The on-disk name a shared video gets: sanitized STEM + preserved extension (defaulting
/// to .mp4 when none was given). [sanitizeShareFilename] eats dots, and receivers type
/// files by extension — sanitizing the whole name once shipped an extensionless video that
/// WhatsApp filed as a document and Reddit rejected outright.
String videoShareFileName(String filename) {
  final dot = filename.lastIndexOf('.');
  final stem = dot <= 0 ? filename : filename.substring(0, dot);
  final ext = dot <= 0 ? '.mp4' : filename.substring(dot);
  return '${sanitizeShareFilename(stem)}$ext';
}

/// Share an already-encoded video FILE (the Timelapse export's MP4) through the system
/// share sheet. Same per-share cache-subdir prune as [shareImageBytes]; the source file is
/// MOVED into it (the export wrote a temp file we own). Only the STEM is sanitized — the
/// sanitizer eats dots, and receivers type files by extension (an extensionless share made
/// WhatsApp file the video as a document and Reddit reject it outright).
Future<void> shareVideoFile(String path, {required String filename, String? text}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/share');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final dest = '${dir.path}/${videoShareFileName(filename)}';
  File shared;
  try {
    shared = await File(path).rename(dest);
  } on FileSystemException {
    shared = await File(path).copy(dest); // cross-volume rename fallback
  }
  final params = (text != null && text.trim().isNotEmpty)
      ? ShareParams(files: [XFile(shared.path, mimeType: 'video/mp4')], text: text)
      : ShareParams(files: [XFile(shared.path, mimeType: 'video/mp4')]);
  await SharePlus.instance.share(params);
}

/// High-level share of a raster artwork's PIXELS (a downloaded render), re-encoded to a shareable
/// GIF / lossless WebP (animations) or PNG (stills) at a user-chosen scale, with a "title — link"
/// caption accompanying the file. This is what the Club's Share button calls; the editor reuses the
/// lower-level pieces above with its live document.
///
/// The scale/format dialog opens first (no bytes needed yet); [fetchRaster] then runs UNDER the
/// progress dialog, so the download + import + encode are all covered by one "Preparing…/%" UI. The
/// thunk must not throw — any failure surfaces as an empty result. [width]/[height] are the artwork's
/// native (logical) pixel size. Returns true if the share sheet was opened.
Future<bool> shareRasterArtwork({
  required BuildContext context,
  required Future<Uint8List> Function() fetchRaster,
  required int width,
  required int height,
  required int frameCount,
  required String title,
  String? linkUrl,
  void Function(String message)? onError,
  // Non-fatal heads-up (e.g. "semi-transparent pixels were flattened" on a GIF share); the
  // caller supplies the toast, mirroring onError.
  void Function(String message)? onNotice,
}) async {
  void fail(String m) => onError?.call(m);
  if (width < Engine.minDim || height < Engine.minDim || width > Engine.maxDim || height > Engine.maxDim) {
    fail('This artwork can’t be shared as an image.');
    return false;
  }
  final animated = frameCount > 1;
  final prefs = await SharedPreferences.getInstance();
  final remembered = prefs.getString(kShareFormatPref) ?? 'GIF';
  if (!context.mounted) return false;

  final choice = await showExportScaleDialog(
    context: context,
    width: width,
    height: height,
    frames: frameCount,
    title: 'Share',
    action: 'Share',
    formats: animated ? const ['GIF', 'WebP'] : const [],
    initialFormat: remembered,
  );
  if (choice == null) return false;
  final (scale, chosen) = choice;
  if (animated) await prefs.setString(kShareFormatPref, chosen);

  // Stills always PNG (receiver compatibility — mirrors the editor's Share). Animations: GIF
  // (default) or lossless WebP.
  final (format, ext, mime) = !animated
      ? ('png', 'png', 'image/png')
      : chosen == 'WebP'
          ? ('webp', 'webp', 'image/webp')
          : ('gif', 'gif', 'image/gif');

  if (!context.mounted) return false;
  final (bytes, canceled, flattened) = await encodeWithProgress(
    context: context,
    title: 'Rendering ${animated ? chosen : 'PNG'}…',
    encode: () async {
      try {
        final raster = await fetchRaster();
        if (raster.isEmpty) return (Uint8List(0), false);
        return await Engine.encodeRasterInBackground(raster,
            width: width, height: height, format: format, scale: scale);
      } catch (_) {
        return (Uint8List(0), false);
      }
    },
  );
  if (canceled) return false;
  if (bytes.isEmpty) {
    fail('Could not render the image to share.');
    return false;
  }
  if (flattened) onNotice?.call('GIF holds no partial transparency — semi-transparent pixels were flattened');

  try {
    await shareImageBytes(bytes: bytes, filenameBase: title, ext: ext, mime: mime, text: shareCaption(title, linkUrl));
    return true;
  } catch (e) {
    fail('Could not share: $e');
    return false;
  }
}
