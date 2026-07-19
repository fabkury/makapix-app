import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/pmd.dart';
import '../state/api_providers.dart';
import '../state/pmd_providers.dart';
import '../state/publish_providers.dart' show licensesProvider;
import 'widgets/common.dart';

/// Post Management Dashboard (`SPEC-CLUB.md` §20). The signed-in user's own posts
/// with multi-select bulk actions (hide / unhide / delete / change license) and
/// the async ZIP data export. Mirrors the website's `/u/{sqid}/posts`.
class PostManagementPage extends ConsumerStatefulWidget {
  const PostManagementPage({super.key});
  @override
  ConsumerState<PostManagementPage> createState() => _PostManagementPageState();
}

class _PostManagementPageState extends ConsumerState<PostManagementPage> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 600) {
        ref.read(pmdListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<String?> Function() op, {String? ok}) async {
    final err = await op();
    if (!mounted) return;
    if (err != null) {
      _toast(err);
    } else if (ok != null) {
      _toast(ok);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(pmdListProvider);
    final n = ref.read(pmdListProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.selected.isEmpty ? 'My Posts' : '${s.selected.length} selected'),
        actions: [
          IconButton(
            tooltip: 'Downloads',
            icon: const Icon(Icons.download_outlined),
            onPressed: _openDownloads,
          ),
          if (s.items.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (v) =>
                  v == 'all' ? n.selectAllLoaded() : n.clearSelection(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('Select all (loaded)')),
                PopupMenuItem(value: 'none', child: Text('Clear selection')),
              ],
            ),
        ],
      ),
      body: CenteredContent(child: _body(s, n)),
      bottomNavigationBar: s.selected.isEmpty ? null : _bulkBar(s, n),
    );
  }

  Widget _body(PmdState s, PmdController n) {
    if (!s.initialized && s.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.error != null && s.items.isEmpty) {
      return ClubErrorRetry(message: s.error!, onRetry: n.refresh);
    }
    if (s.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: n.refresh,
        child: ListView(children: const [
          SizedBox(height: 240, child: ClubEmpty(message: 'You have no posts yet.')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: n.refresh,
      child: ListView.separated(
        controller: _sc,
        itemCount: s.items.length + (s.atEnd ? 0 : 1),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          if (i >= s.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            );
          }
          return _row(s.items[i], s.selected.contains(s.items[i].id), n);
        },
      ),
    );
  }

  Widget _row(PmdPostItem p, bool selected, PmdController n) {
    return InkWell(
      onTap: () => n.toggle(p.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(children: [
          Checkbox(value: selected, onChanged: (_) => n.toggle(p.id)),
          SizedBox(
            width: 44,
            height: 44,
            child: Opacity(
                opacity: p.hiddenByUser ? 0.45 : 1,
                child: PixelArtImage(
                    url: p.artUrl,
                    frameCount: p.frameCount,
                    width: p.width,
                    height: p.height)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(p.title.isEmpty ? '(untitled)' : p.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (p.hiddenByUser) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.visibility_off_outlined, size: 14, color: Colors.white38),
                ],
              ]),
              const SizedBox(height: 2),
              Text(
                '${timeAgo(p.createdAt)} · ${_fmt(p.viewCount)} views · '
                '${_fmt(p.reactionCount)} reactions · ${p.licenseIdentifier ?? 'ARR'}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bulkBar(PmdState s, PmdController n) {
    final count = s.selected.length;
    final busy = s.busy;
    return SafeArea(
      child: Material(
        elevation: 8,
        color: const Color(0xFF1B1E22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          // The bar's background spans the window; its actions stay in the centered content column.
          child: CenteredContent(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (busy) const LinearProgressIndicator(minHeight: 2),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(
                onPressed: busy ? null : () => _run(n.hide, ok: 'Hidden.'),
                icon: const Icon(Icons.visibility_off_outlined, size: 18),
                label: const Text('Hide'),
              ),
              TextButton.icon(
                onPressed: busy ? null : () => _run(n.unhide, ok: 'Unhidden.'),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Unhide'),
              ),
              TextButton.icon(
                onPressed: (busy || count > kPmdDeleteMax) ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(count > kPmdDeleteMax ? 'Delete (max $kPmdDeleteMax)' : 'Delete'),
              ),
              TextButton.icon(
                onPressed: busy ? null : _openLicensePicker,
                icon: const Icon(Icons.copyright_outlined, size: 18),
                label: const Text('License'),
              ),
              TextButton.icon(
                onPressed: (busy || count > kPmdBatchMax) ? null : _openDownloadDialog,
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: Text(count > kPmdBatchMax ? 'Download (max $kPmdBatchMax)' : 'Download'),
              ),
            ]),
          ])),
        ),
      ),
    );
  }

  // ---- Delete confirmation ----
  Future<void> _confirmDelete() async {
    final n = ref.read(pmdListProvider.notifier);
    final count = ref.read(pmdListProvider).selected.length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete posts?'),
        content: Text('Delete $count post${count == 1 ? '' : 's'}? They are removed from your '
            'profile and permanently deleted after a 7-day grace period.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes == true) await _run(n.delete, ok: 'Deleted.');
  }

  // ---- License picker ----
  Future<void> _openLicensePicker() async {
    final n = ref.read(pmdListProvider.notifier);
    final picked = await showAppSheet<_LicenseChoice>(
      context: context,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final async = ref.watch(licensesProvider);
        return async.when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SizedBox(
            height: 160,
            child: Center(child: Text(e is ClubError ? e.message : 'Could not load licenses.')),
          ),
          data: (licenses) => ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Set license', style: TextStyle(fontWeight: FontWeight.w600))),
              ListTile(
                title: const Text('None (all rights reserved)'),
                onTap: () => Navigator.pop(ctx, const _LicenseChoice(null, null)),
              ),
              for (final l in licenses)
                ListTile(
                  title: Text(l.title.isEmpty ? l.identifier : l.title),
                  subtitle: Text(l.identifier),
                  onTap: () => Navigator.pop(ctx, _LicenseChoice(l.id, l.identifier)),
                ),
            ],
          ),
        );
      }),
    );
    if (picked == null) return;
    await _run(() => n.setLicense(picked.id, picked.identifier), ok: 'License updated.');
  }

  // ---- Request-download dialog ----
  Future<void> _openDownloadDialog() async {
    var includeExtras = false;
    var sendEmail = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Request download'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('The selected artworks are bundled into one ZIP. Up to '
                '$kPmdBatchMax per request, 8 per day. The link lasts 7 days once ready.'),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: includeExtras,
              onChanged: (v) => setLocal(() => includeExtras = v ?? false),
              title: const Text('Include received comments & reactions'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: sendEmail,
              onChanged: (v) => setLocal(() => sendEmail = v ?? false),
              title: const Text('Email me when the link is ready'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Request')),
          ],
        ),
      ),
    );
    if (go != true) return;
    final n = ref.read(pmdListProvider.notifier);
    final err = await n.requestDownload(
      includeComments: includeExtras,
      includeReactions: includeExtras,
      sendEmail: sendEmail,
    );
    if (!mounted) return;
    if (err != null) {
      _toast(err);
    } else {
      _toast('Download queued.');
      ref.read(bdrListProvider.notifier).refresh();
      _openDownloads();
    }
  }

  // ---- Downloads (BDR) sheet ----
  void _openDownloads() {
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _DownloadsSheet(),
    );
  }

  static String _fmt(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

class _LicenseChoice {
  final int? id;
  final String? identifier;
  const _LicenseChoice(this.id, this.identifier);
}

/// The batch-download jobs, with live status and a Download (save-to-disk) button.
class _DownloadsSheet extends ConsumerWidget {
  const _DownloadsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bdrListProvider);
    final n = ref.read(bdrListProvider.notifier);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            const Expanded(child: Text('Downloads', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
            IconButton(icon: const Icon(Icons.refresh), onPressed: n.refresh),
          ]),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ClubErrorRetry(
              message: e is ClubError ? e.message : 'Could not load downloads.',
              onRetry: n.refresh,
            ),
            data: (items) => items.isEmpty
                ? ListView(controller: scroll, children: const [
                    SizedBox(height: 200, child: ClubEmpty(message: 'No downloads requested yet.')),
                  ])
                : ListView.separated(
                    controller: scroll,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _BdrTile(bdr: items[i]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _BdrTile extends ConsumerStatefulWidget {
  final Bdr bdr;
  const _BdrTile({required this.bdr});
  @override
  ConsumerState<_BdrTile> createState() => _BdrTileState();
}

class _BdrTileState extends ConsumerState<_BdrTile> {
  bool _downloading = false;

  Future<void> _download() async {
    final b = widget.bdr;
    setState(() => _downloading = true);
    try {
      final bytes = await ref.read(pmdApiProvider).downloadBdr(b.id);
      final shortId = b.id.length > 8 ? b.id.substring(0, 8) : b.id;
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save export ZIP',
        fileName: 'makapix-artworks-$shortId.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: Uint8List.fromList(bytes),
      );
      if (path == null) return; // cancelled
      // Desktop returns a path without writing; mobile already wrote via the picker.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved export ZIP.')));
      }
    } on ClubError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bdr;
    final cs = Theme.of(context).colorScheme;
    final (label, color) = switch (b.status) {
      'pending' => ('Pending', Colors.amber),
      'processing' => ('Processing', Colors.lightBlue),
      'ready' => ('Ready', Colors.greenAccent),
      'failed' => ('Failed', Colors.redAccent),
      'expired' => ('Expired', Colors.white38),
      _ => (b.status, Colors.white54),
    };
    return ListTile(
      title: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: TextStyle(color: color, fontSize: 11)),
        ),
        const SizedBox(width: 8),
        Text('${b.artworkCount} artwork${b.artworkCount == 1 ? '' : 's'}'),
      ]),
      subtitle: Text([
        if (b.createdAt != null) 'Requested ${timeAgo(b.createdAt)} ago',
        if (b.isReady && b.expiresAt != null) 'Expires ${timeAgo(b.expiresAt)}',
        if (b.errorMessage != null) b.errorMessage!,
      ].join(' · ')),
      trailing: b.isReady
          ? (_downloading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton(onPressed: _download, child: const Text('Download')))
          : (b.inProgress
              ? Icon(Icons.hourglass_top, color: cs.primary, size: 18)
              : null),
    );
  }
}
