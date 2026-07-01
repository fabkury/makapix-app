import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../publish/publish_draft.dart';
import '../state/edit_bridge.dart';
import 'publish_page.dart';

/// The Contribute page — a peer to the feeds (it sits left of Recommended in the swipe pager).
///
/// Two ways to add art to the Club, mirroring the website's Contribute page but without asking
/// which device you're on (this client is always a phone/tablet): draw it in the native Makapix
/// Editor, or upload an image file directly (skipping the editor). The editor hands `lib/club`
/// only bytes; a direct upload hands its file's bytes straight to the same publish flow.
class ContributePage extends ConsumerStatefulWidget {
  const ContributePage({super.key});
  @override
  ConsumerState<ContributePage> createState() => _ContributePageState();
}

class _ContributePageState extends ConsumerState<ContributePage> {
  // Directly uploadable image formats — the four the server's vault accepts.
  static const List<String> _uploadFormats = ['png', 'gif', 'webp', 'bmp'];
  bool _picking = false;

  void _openEditor() => ref.read(openEditorProvider.notifier).state++;

  // Pick an image file, read its dimensions/frame count locally (no engine), and hand it to the
  // same publish flow the editor uses. Conformance (size, format, byte cap) is judged there.
  Future<void> _uploadFile() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _uploadFormats,
        withData: true, // populate `bytes` on every platform (files are ≤ a few MB)
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null) {
        if (mounted) _snack('Could not read that file.');
        return;
      }
      // Decode just enough to size the artwork for the conformance check. `instantiateImageCodec`
      // handles PNG/GIF/WebP/BMP and reports the frame count for animated files.
      final ui.Codec codec;
      try {
        codec = await ui.instantiateImageCodec(bytes);
      } catch (_) {
        if (mounted) _snack("That file isn't a supported image.");
        return;
      }
      final frame = await codec.getNextFrame();
      final draft = PublishDraft(
        bytes: bytes,
        format: _formatOf(f.extension, bytes),
        filename: f.name,
        width: frame.image.width,
        height: frame.image.height,
        frameCount: codec.frameCount,
      );
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublishPage(draft: draft)));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  // Prefer the picked file's extension; fall back to sniffing the magic bytes.
  String _formatOf(String? ext, Uint8List bytes) {
    final e = ext?.toLowerCase();
    if (e != null && _uploadFormats.contains(e)) return e;
    return _sniffFormat(bytes) ?? 'png';
  }

  String? _sniffFormat(Uint8List b) {
    bool at(int i, List<int> sig) =>
        b.length >= i + sig.length && [for (var k = 0; k < sig.length; k++) b[i + k] == sig[k]].every((v) => v);
    if (at(0, [0x89, 0x50, 0x4E, 0x47])) return 'png';
    if (at(0, [0x47, 0x49, 0x46])) return 'gif'; // "GIF"
    if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) return 'webp'; // RIFF….WEBP
    if (at(0, [0x42, 0x4D])) return 'bmp'; // "BM"
    return null;
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Contribute',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Share your pixel art with the Club.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.white54)),
                const SizedBox(height: 28),
                _OptionCard(
                  icon: Icons.brush_outlined,
                  accent: cs.primary,
                  title: 'Makapix Editor',
                  description: 'Create animated pixel art with the built-in Makapix Editor.',
                  onTap: _openEditor,
                ),
                const SizedBox(height: 16),
                _OptionCard(
                  icon: Icons.upload_file_outlined,
                  accent: cs.primary,
                  title: 'Upload a file',
                  description: 'Post a PNG, GIF, WebP, or BMP straight from your device — no editing needed.',
                  onTap: _uploadFile,
                  busy: _picking,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A large, tappable contribute option: icon + title + one-line pitch.
class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool busy;
  const _OptionCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF15171A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A2D31)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: busy
                    ? Center(
                        child: SizedBox(
                            height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: accent)))
                    : Icon(icon, size: 40, color: accent),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(description, style: const TextStyle(fontSize: 13, color: Colors.white54, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.white30),
            ],
          ),
        ),
      ),
    );
  }
}
