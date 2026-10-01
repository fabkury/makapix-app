import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        // Two actions leave a 320 px phone 192 px of title: scale the last few pixels down
        // rather than ellipsize ("Minhas publicações").
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
              s.selected.isEmpty ? l10n.menuMyPosts : l10n.pmdSelected(s.selected.length)),
        ),
        actions: [
          IconButton(
            tooltip: l10n.pmdDownloads,
            icon: const Icon(Icons.download_outlined),
            onPressed: _openDownloads,
          ),
          if (s.items.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (v) =>
                  v == 'all' ? n.selectAllLoaded() : n.clearSelection(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'all', child: Text(l10n.pmdSelectAll)),
                PopupMenuItem(value: 'none', child: Text(l10n.pmdClearSelection)),
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
        child: ListView(children: [
          SizedBox(height: 240, child: ClubEmpty(message: context.l10n.pmdEmpty)),
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
                  child: Text(p.title.isEmpty ? context.l10n.untitledParens : p.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (p.hiddenByUser) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.visibility_off_outlined, size: 14, color: Colors.white38),
                ],
              ]),
              const SizedBox(height: 2),
              Text(
                [
                  timeAgo(p.createdAt),
                  context.l10n.pmdViews(p.viewCount, compactCount(p.viewCount)),
                  context.l10n.pmdReactions(p.reactionCount, compactCount(p.reactionCount)),
                  p.licenseIdentifier ?? context.l10n.pmdNoLicenseShort,
                ].join(' · '),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                maxLines: 2,
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
    final l10n = context.l10n;
    return SafeArea(
      child: Material(
        elevation: 8,
        color: const Color(0xFF1B1E22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          // The bar's background spans the window; its actions stay in the centered content
          // column. Not CenteredContent: its Align takes all the height a bottom bar is offered,
          // and the bar covered the whole page (found by the i18n sweep, 2026-10-01).
          child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (busy) const LinearProgressIndicator(minHeight: 2),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(
                onPressed: busy ? null : () => _run(n.hide, ok: l10n.pmdHiddenToast),
                icon: const Icon(Icons.visibility_off_outlined, size: 18),
                label: Text(l10n.commonHide),
              ),
              TextButton.icon(
                onPressed: busy ? null : () => _run(n.unhide, ok: l10n.pmdUnhiddenToast),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: Text(l10n.commonUnhide),
              ),
              TextButton.icon(
                onPressed: (busy || count > kPmdDeleteMax) ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(
                    count > kPmdDeleteMax ? l10n.pmdDeleteMax(kPmdDeleteMax) : l10n.commonDelete),
              ),
              TextButton.icon(
                onPressed: busy ? null : _openLicensePicker,
                icon: const Icon(Icons.copyright_outlined, size: 18),
                label: Text(l10n.publishLicense),
              ),
              TextButton.icon(
                onPressed: (busy || count > kPmdBatchMax) ? null : _openDownloadDialog,
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: Text(
                    count > kPmdBatchMax ? l10n.pmdDownloadMax(kPmdBatchMax) : l10n.pmdDownload),
              ),
            ]),
          ]))),
        ),
      ),
    );
  }

  // ---- Delete confirmation ----
  Future<void> _confirmDelete() async {
    final n = ref.read(pmdListProvider.notifier);
    final count = ref.read(pmdListProvider).selected.length;
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.pmdDeleteTitle),
        content: Text(ctx.l10n.pmdDeleteBody(count)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.commonDelete)),
        ],
      ),
    );
    if (yes == true) await _run(n.delete, ok: l10n.pmdDeletedToast);
  }

  // ---- License picker ----
  Future<void> _openLicensePicker() async {
    final n = ref.read(pmdListProvider.notifier);
    final l10n = context.l10n;
    final picked = await showAppSheet<_LicenseChoice>(
      context: context,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final async = ref.watch(licensesProvider);
        return async.when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SizedBox(
            height: 160,
            child: Center(child: Text(e is ClubError ? e.message : ctx.l10n.pmdLicensesError)),
          ),
          data: (licenses) => ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                  title: Text(ctx.l10n.pmdSetLicense,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              ListTile(
                title: Text(ctx.l10n.pmdLicenseNone),
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
    await _run(() => n.setLicense(picked.id, picked.identifier), ok: l10n.pmdLicenseUpdated);
  }

  // ---- Request-download dialog ----
  Future<void> _openDownloadDialog() async {
    var includeExtras = false;
    var sendEmail = false;
    final l10n = context.l10n;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(ctx.l10n.pmdRequestTitle),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(ctx.l10n.pmdRequestBody(kPmdBatchMax)),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: includeExtras,
              onChanged: (v) => setLocal(() => includeExtras = v ?? false),
              title: Text(ctx.l10n.pmdIncludeExtras),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: sendEmail,
              onChanged: (v) => setLocal(() => sendEmail = v ?? false),
              title: Text(ctx.l10n.pmdEmailMe),
            ),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.pmdRequestAction)),
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
      _toast(l10n.pmdQueued);
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
            Expanded(
                child: Text(context.l10n.pmdDownloads,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
            IconButton(icon: const Icon(Icons.refresh), onPressed: n.refresh),
          ]),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ClubErrorRetry(
              message: e is ClubError ? e.message : context.l10n.pmdDownloadsError,
              onRetry: n.refresh,
            ),
            data: (items) => items.isEmpty
                ? ListView(controller: scroll, children: [
                    SizedBox(
                        height: 200, child: ClubEmpty(message: context.l10n.pmdDownloadsEmpty)),
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
    final l10n = context.l10n;
    setState(() => _downloading = true);
    try {
      final bytes = await ref.read(pmdApiProvider).downloadBdr(b.id);
      final shortId = b.id.length > 8 ? b.id.substring(0, 8) : b.id;
      final path = await FilePicker.saveFile(
        dialogTitle: l10n.pmdSaveZipTitle,
        fileName: 'makapix-artworks-$shortId.zip', // l10n-ignore: file name
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: Uint8List.fromList(bytes),
      );
      if (path == null) return; // canceled
      // Desktop returns a path without writing; mobile already wrote via the picker.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.pmdSavedZip)));
      }
    } on ClubError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.pmdSaveFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// "Expires in 3 days" — hours on the last day, never less than one.
  static String _expiresIn(AppLocalizations l10n, DateTime at) {
    final left = at.toUtc().difference(DateTime.now().toUtc());
    if (left.inHours < 24) return l10n.pmdExpiresHours(left.inHours < 1 ? 1 : left.inHours);
    return l10n.pmdExpiresDays(left.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bdr;
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final (label, color) = switch (b.status) {
      'pending' => (l10n.bdrPending, Colors.amber),
      'processing' => (l10n.bdrProcessing, Colors.lightBlue),
      'ready' => (l10n.bdrReady, Colors.greenAccent),
      'failed' => (l10n.bdrFailed, Colors.redAccent),
      'expired' => (l10n.bdrExpired, Colors.white38),
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
        Flexible(child: Text(l10n.pmdArtworks(b.artworkCount))),
      ]),
      subtitle: Text([
        if (b.createdAt != null) l10n.pmdRequestedAgo(timeAgo(b.createdAt)),
        if (b.isReady && b.expiresAt != null) _expiresIn(l10n, b.expiresAt!),
        if (b.errorMessage != null) b.errorMessage!,
      ].join(' · ')),
      trailing: b.isReady
          ? (_downloading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton(onPressed: _download, child: Text(l10n.pmdDownload)))
          : (b.inProgress
              ? Icon(Icons.hourglass_top, color: cs.primary, size: 18)
              : null),
    );
  }
}
