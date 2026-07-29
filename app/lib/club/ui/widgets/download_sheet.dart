import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/club_error.dart';
import '../../models/post.dart';
import '../../state/api_providers.dart';
import '../../state/auth_controller.dart';
import '../../state/publish_providers.dart';
import 'common.dart';

/// Save-to-device downloads for an artwork (website parity: Download ▸ native /
/// upscaled / alternative format / layers file). Every variant is fetched from
/// the `/d/{sqid}*` router and written via the OS save dialog, like the PMD
/// export ZIP — the share button remains the re-encode-and-share path.
Future<void> showDownloadSheet(BuildContext context, WidgetRef ref, {required Post post}) {
  final messenger = ScaffoldMessenger.of(context);
  final native = post.nativeFile;
  final alternatives = post.files.where((f) => !f.isNative).toList();
  final mkpxEnabled =
      ref.read(serverConfigProvider).valueOrNull?.upload.mkpx.enabled ?? false;
  final showMkpx =
      mkpxEnabled && post.hasMkpx && ref.read(authControllerProvider).isSignedIn;
  final baseName = _safeFileName(post.title.isEmpty ? post.sqid : post.title);

  Future<void> run(
    BuildContext ctx, {
    required Future<Uint8List> Function() fetch,
    required String fileName,
    required String extension,
  }) async {
    Navigator.pop(ctx);
    try {
      final bytes = await fetch();
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save artwork',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      if (path == null) return; // canceled
      // Desktop returns a path without writing; mobile already wrote via the picker.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
      messenger.showSnackBar(SnackBar(content: Text('Saved $fileName')));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.status == 404 ? 'That file is not available.' : e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save the file.')));
    }
  }

  return showAppSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final api = ref.read(postApiProvider);
      return SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('Download', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (native != null)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Native format'),
              subtitle: Text(
                  '${native.format.toUpperCase()} · ${formatFileSize(native.fileBytes)}',
                  style: const TextStyle(fontSize: 11)),
              onTap: () => run(ctx,
                  fetch: () => api.downloadNative(post.sqid),
                  fileName: '$baseName.${native.format}',
                  extension: native.format),
            ),
          ListTile(
            leading: const Icon(Icons.zoom_out_map),
            title: const Text('Upscaled'),
            subtitle: const Text('Nearest-neighbor enlargement · WEBP',
                style: TextStyle(fontSize: 11)),
            onTap: () => run(ctx,
                fetch: () => api.downloadUpscaled(post.sqid),
                fileName: '${baseName}_upscaled.webp',
                extension: 'webp'),
          ),
          for (final f in alternatives)
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(f.format.toUpperCase()),
              subtitle: Text(formatFileSize(f.fileBytes), style: const TextStyle(fontSize: 11)),
              onTap: () => run(ctx,
                  fetch: () => api.downloadFormat(post.sqid, f.format),
                  fileName: '$baseName.${f.format}',
                  extension: f.format),
            ),
          if (showMkpx)
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Layers file (.mkpx)'),
              subtitle: Text(
                  post.mkpxFileBytes != null
                      ? formatFileSize(post.mkpxFileBytes!)
                      : 'The full layered document',
                  style: const TextStyle(fontSize: 11)),
              onTap: () => run(ctx,
                  fetch: () => ref.read(mkpxApiProvider).download(post.sqid),
                  fileName: '$baseName.mkpx',
                  extension: 'mkpx'),
            ),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
}

/// Titles become filenames; strip the characters Windows/Android forbid.
String _safeFileName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'artwork' : cleaned;
}
