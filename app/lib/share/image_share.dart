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
  var scale = 1;
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
            for (final s in const [1, 4, 8, 16, 32])
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
/// and offers Cancel (honoured at the next frame boundary). Returns (bytes, cancelled); bytes is
/// empty on failure or cancellation.
Future<(Uint8List, bool)> encodeWithProgress({
  required BuildContext context,
  required String title,
  required Future<Uint8List> Function() encode,
}) async {
  Engine.resetExportProgressStatic(); // the dialog must not briefly show the PREVIOUS export's bar
  var cancelled = false;
  final future = encode();
  if (context.mounted) {
    var dialogOpen = true;
    Timer? poll;
    var cancelling = false;
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
              onPressed: cancelling
                  ? null
                  : () => setS(() {
                        cancelling = true;
                        cancelled = true;
                        Engine.cancelExportStatic(); // honoured at the next frame boundary
                      }),
              child: Text(cancelling ? 'Cancelling…' : 'Cancel'),
            ),
          ],
        );
      }),
    ).whenComplete(() {
      poll?.cancel();
      dialogOpen = false;
    }));
    final bytes = await future;
    if (dialogOpen && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return (bytes, cancelled);
  }
  return (await future, false);
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
}) async {
  void fail(String m) => onError?.call(m);
  if (width < 1 || height < 1 || width > 256 || height > 256) {
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
  final (bytes, cancelled) = await encodeWithProgress(
    context: context,
    title: 'Rendering ${animated ? chosen : 'PNG'}…',
    encode: () async {
      try {
        final raster = await fetchRaster();
        if (raster.isEmpty) return Uint8List(0);
        return await Engine.encodeRasterInBackground(raster,
            width: width, height: height, format: format, scale: scale);
      } catch (_) {
        return Uint8List(0);
      }
    },
  );
  if (cancelled) return false;
  if (bytes.isEmpty) {
    fail('Could not render the image to share.');
    return false;
  }

  try {
    await shareImageBytes(bytes: bytes, filenameBase: title, ext: ext, mime: mime, text: shareCaption(title, linkUrl));
    return true;
  } catch (e) {
    fail('Could not share: $e');
    return false;
  }
}
