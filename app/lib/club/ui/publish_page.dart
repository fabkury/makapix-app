import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../models/server_config.dart';
import '../publish/conformance.dart';
import '../publish/publish_draft.dart';
import '../state/auth_controller.dart';
import '../state/publish_providers.dart';
import 'artwork_detail_page.dart';
import 'club_account_page.dart';
import 'widgets/common.dart';

/// "Post to Club": conformance gate → metadata/license/visibility → upload.
class PublishPage extends ConsumerStatefulWidget {
  final PublishDraft draft;
  const PublishPage({super.key, required this.draft});
  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _tags = TextEditingController();
  int? _licenseId;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    // Clear any prior success/error from a previous publish.
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(publishControllerProvider.notifier).reset());
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.isSignedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Post to Club')),
        body: SignInPrompt(
          message: 'Sign in to publish to Makapix Club.',
          onSignIn: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubAccountPage())),
        ),
      );
    }
    final pub = ref.watch(publishControllerProvider);
    if (pub.status == PublishStatus.success) {
      return _Success(post: pub.post);
    }
    final cfg = ref.watch(serverConfigProvider).valueOrNull ?? ClubServerConfig.fallback;
    return Scaffold(
      appBar: AppBar(title: const Text('Post to Club')),
      body: _form(cfg, pub),
    );
  }

  Widget _form(ClubServerConfig cfg, PublishState pub) {
    final d = widget.draft;
    final result = ClubConformance(cfg).check(
      width: d.width,
      height: d.height,
      frameCount: d.frameCount,
      byteLength: d.byteLength,
      format: d.format,
    );
    final canPostPublic = ref.watch(authControllerProvider).me?.capabilities['can_post_public'] == true;
    final uploading = pub.status == PublishStatus.uploading;
    final kib = (d.byteLength / 1024).toStringAsFixed(0);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Container(
            height: 160,
            width: 160,
            color: const Color(0xFF0E1012),
            padding: const EdgeInsets.all(8),
            child: Image.memory(d.bytes, fit: BoxFit.contain, filterQuality: FilterQuality.none, gaplessPlayback: true),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '${d.width}×${d.height}  ·  ${d.isAnimated ? '${d.frameCount} frames' : 'static'}  ·  ${d.format.toUpperCase()}  ·  $kib KiB',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ),
        const SizedBox(height: 12),
        _conformanceBanner(result),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          maxLength: 128,
          decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _desc,
          maxLength: 5000,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
              labelText: 'Description (optional)', border: OutlineInputBorder(), counterText: ''),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tags,
          decoration: const InputDecoration(
              labelText: 'Hashtags (comma-separated)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        _licenseDropdown(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Post as hidden'),
          subtitle: const Text('Only you can see it until you unhide.', style: TextStyle(fontSize: 12)),
          value: _hidden,
          onChanged: uploading ? null : (v) => setState(() => _hidden = v),
        ),
        if (!canPostPublic && !_hidden)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Your post will await moderator approval before appearing publicly.',
                style: TextStyle(fontSize: 12, color: Colors.amberAccent)),
          ),
        if (pub.status == PublishStatus.error && pub.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(pub.error!, style: const TextStyle(color: Colors.redAccent)),
          ),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: (result.ok && !uploading) ? _submit : null,
          icon: uploading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload),
          label: Text(uploading ? 'Uploading…' : 'Publish'),
        ),
      ],
    );
  }

  Widget _conformanceBanner(ConformanceResult r) {
    if (r.ok) {
      return _banner(const Color(0x2200C853), const Color(0xFF00C853), Icons.check_circle_outline,
          'Ready to publish — this artwork meets Makapix Club\'s requirements.');
    }
    final msgs = <String>[];
    for (final i in r.issues) {
      switch (i) {
        case ConformanceIssue.overMax:
          msgs.add('Too large — the maximum is 256×256.');
        case ConformanceIssue.underMinNotWhitelisted:
          msgs.add('This size isn\'t allowed. Use 128–256 on both sides, or a standard small size.');
        case ConformanceIssue.fileTooLarge:
          msgs.add('File exceeds the size limit.');
        case ConformanceIssue.unsupportedFormat:
          msgs.add('Unsupported format.');
      }
    }
    if (r.nearestSize != null) {
      msgs.add('Nearest allowed size: ${r.nearestSize![0]}×${r.nearestSize![1]} '
          '(resize in the editor, then try again).');
    }
    return _banner(const Color(0x22FF5252), const Color(0xFFFF5252), Icons.error_outline, msgs.join('\n'));
  }

  Widget _banner(Color bg, Color border, IconData icon, String text) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: border),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _licenseDropdown() {
    final licenses = ref.watch(licensesProvider).valueOrNull ?? const [];
    return DropdownButtonFormField<int?>(
      initialValue: _licenseId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'License', border: OutlineInputBorder()),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('No license (all rights reserved)')),
        for (final l in licenses)
          DropdownMenuItem<int?>(value: l.id, child: Text(l.identifier, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => setState(() => _licenseId = v),
    );
  }

  void _submit() {
    final d = widget.draft;
    ref.read(publishControllerProvider.notifier).submit(
          bytes: d.bytes,
          filename: d.filename,
          title: _title.text.trim().isEmpty ? 'Untitled' : _title.text.trim(),
          description: _desc.text.trim(),
          hashtags: _tags.text.trim(),
          hidden: _hidden,
          licenseId: _licenseId,
        );
  }
}

class _Success extends ConsumerWidget {
  final Post? post;
  const _Success({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sqid = post?.sqid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Posted')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle, color: Color(0xFF00C853), size: 56),
            const SizedBox(height: 12),
            const Text('Published to Makapix Club!', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            if (sqid.isNotEmpty)
              FilledButton.icon(
                onPressed: () {
                  ref.read(publishControllerProvider.notifier).reset();
                  Navigator.pushReplacement(
                      context, MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: sqid)));
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('View post'),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                ref.read(publishControllerProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              child: const Text('Back to editor'),
            ),
          ]),
        ),
      ),
    );
  }
}
