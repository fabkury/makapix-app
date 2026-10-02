import 'dart:io';

import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/license_option.dart';
import '../models/mention_markup.dart';
import '../models/post.dart';
import '../models/server_config.dart';
import '../publish/conformance.dart';
import '../publish/provenance_fields.dart';
import '../publish/publish_draft.dart';
import '../state/auth_controller.dart';
import '../state/publish_providers.dart';
import '../state/rules_gate.dart';
import 'package:makapix_club/share/artwork_rescale.dart';
import 'artwork_detail_page.dart';
import 'club_account_page.dart';
import 'rules_gate_page.dart';
import 'widgets/common.dart';
import 'widgets/mention_field.dart';

/// "Post to Club": conformance gate → metadata/license/visibility → upload.
class PublishPage extends ConsumerStatefulWidget {
  final PublishDraft draft;
  const PublishPage({super.key, required this.draft});
  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage> {
  int get _maxMentions =>
      ref.read(serverConfigProvider).valueOrNull?.maxMentionsPerText ??
      kMaxMentionsPerText;

  final _title = TextEditingController();
  final _desc = TextEditingController();
  late final MentionComposer _mentions = MentionComposer(controller: _desc);
  final _descFocus = FocusNode();
  final _tags = TextEditingController();
  int? _licenseId;
  bool _hidden = false;
  // Sharing the layers file is opt-out: editor publishes default to attaching it. _submit
  // re-checks the capability/size gates so the hidden-tile cases can't send it anyway.
  bool _shareLayers = true;
  // The owner's Remixable choice (public, server default true). An ND license forces it off
  // (server rule L5: remixable=true + ND license is a 422) — the toggle disables then.
  bool _remixable = true;
  // Set only by the user's explicit choice in the lineage-refusal dialog (a declared parent is
  // gone or no longer Remixable): retry the publish without `remixed_from`. Never automatic.
  bool _stripRemixClaim = false;
  String _appVersion = '';

  /// The draft starts as [widget.draft] but the scale-to-nearest remedy can
  /// replace it (new bytes/dimensions/format), so the page reads this copy.
  late PublishDraft _draft = widget.draft;
  bool _scaling = false;

  @override
  void initState() {
    super.initState();
    final src = widget.draft.source;
    if (src != null) {
      _title.text = src.title;
      _desc.text = appL10n.publishRemixDescription(src.title, src.ownerHandle);
    }
    // Clear any prior success/error from a previous publish.
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(publishControllerProvider.notifier).reset());
    // For the provenance declaration (client=app/<version>, editor_version).
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    }).catchError((_) {/* provenance stays version-less — never blocks publishing */});
  }

  @override
  void dispose() {
    _title.dispose();
    _mentions.dispose();
    _descFocus.dispose();
    _desc.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Post to Club" pushes this page on the editor navigator without entering
    // the Club pillar, so it carries its own rules gate (ugc-safety R1).
    if (ref.watch(rulesGateProvider) == RulesGate.show) {
      return const RulesGatePage();
    }
    final auth = ref.watch(authControllerProvider);
    if (!auth.isSignedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.publishTitle)),
        body: SignInPrompt(
          message: context.l10n.publishSignIn,
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
      appBar: AppBar(title: Text(context.l10n.publishTitle)),
      body: CenteredContent(child: _form(cfg, pub)),
    );
  }

  Widget _form(ClubServerConfig cfg, PublishState pub) {
    final d = _draft;
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
    final l10n = context.l10n;
    // An explicit ListView padding replaces the safe-area inset, so the bottom must add the
    // system inset back (gesture bar / home indicator) plus breathing room: the Publish button
    // used to sit flush against the very bottom of the screen (2026-09-01).
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + bottomInset),
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
            [
              '${d.width}×${d.height}',
              d.isAnimated ? l10n.artworkFrames(d.frameCount) : l10n.artworkStatic,
              if (d.isAnimated && d.totalDurationMs != null)
                l10n.publishLoopSeconds(
                    NumberFormat('0.0', l10n.localeName).format(d.totalDurationMs! / 1000)),
              d.format.toUpperCase(),
              '$kib\u00A0KiB', // l10n-ignore: unit symbol
            ].join('  ·  '),
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ),
        const SizedBox(height: 12),
        _conformanceBanner(result),
        // Scale-to-nearest remedy (website /submit has full scaling options; we
        // offer the one-tap fix). Hidden for editor drafts that carry a layers
        // file — scaling the render would desync it from the document; the
        // editor's Resize tool is the right fix there.
        if (!result.ok && result.nearestSize != null && d.mkpxBytes == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: (_scaling || uploading) ? null : () => _scaleToNearest(result.nearestSize!),
              icon: _scaling
                  ? const SizedBox(
                      height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_size_select_small),
              label: Text(l10n.publishScaleTo(result.nearestSize![0], result.nearestSize![1])),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          maxLength: 128,
          decoration:
              InputDecoration(labelText: l10n.postTitleLabel, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        MentionField(
          composer: _mentions,
          focusNode: _descFocus,
          // No post exists yet, so only the graph and search tiers apply.
          postId: null,
          enabled: ref.watch(serverConfigProvider).valueOrNull?.mentionsEnabled ?? false,
          maxMentions: _maxMentions,
          child: TextField(
            controller: _desc,
            focusNode: _descFocus,
            maxLength: 5000,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
                labelText: l10n.publishDescriptionOptional,
                border: const OutlineInputBorder(),
                counterText: ''),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tags,
          decoration: InputDecoration(
              labelText: l10n.postHashtagsLabel,
              helperText: l10n.postHashtagsHelper,
              border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        _licenseDropdown(),
        _remixableTile(uploading),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.publishHidden),
          subtitle: Text(l10n.publishHiddenSubtitle, style: const TextStyle(fontSize: 12)),
          value: _hidden,
          onChanged: uploading ? null : (v) => setState(() => _hidden = v),
        ),
        ..._shareLayersTile(cfg, uploading),
        if (!canPostPublic && !_hidden)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l10n.publishAwaitsApproval,
                style: const TextStyle(fontSize: 12, color: Colors.amberAccent)),
          ),
        ..._remixDeclarationNote(),
        if (pub.status == PublishStatus.error && pub.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(pub.error!, style: const TextStyle(color: Colors.redAccent)),
          ),
        const SizedBox(height: 4),
        if (d.source != null && d.source!.isOwner) ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4080C0)),
            onPressed: (result.ok && !uploading) ? _replace : null,
            icon: const Icon(Icons.published_with_changes),
            label: Text(l10n.publishReplace),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
                // Server-side rule: replacing a post's artwork drops its layers file.
                d.source!.hasMkpx && cfg.upload.mkpx.enabled
                    ? '${l10n.publishReplaceNote}\n${l10n.publishReplaceDropsLayers}'
                    : l10n.publishReplaceNote,
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ),
        ],
        FilledButton.icon(
          onPressed: (result.ok && !uploading) ? _submit : null,
          icon: uploading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload),
          label: Text(uploading
              ? l10n.publishUploading
              : (d.source != null ? l10n.publishAsNew : l10n.publishAction)),
        ),
      ],
    );
  }

  /// The currently selected license, if any.
  LicenseOption? _selectedLicense() {
    final licenses = ref.read(licensesProvider).valueOrNull ?? const [];
    for (final l in licenses) {
      if (l.id == _licenseId) return l;
    }
    return null;
  }

  /// The upload device's form factor for `source_details.device_type`.
  String _deviceType() {
    if (Platform.isAndroid || Platform.isIOS) {
      return isTabletish(context) ? 'tablet' : 'mobile';
    }
    return 'desktop';
  }

  /// "Allow remixes": the public per-post permission (server default true). An ND license
  /// forces it off — the server would 422 the contradiction (`remixable_conflicts_with_license`).
  Widget _remixableTile(bool uploading) {
    final nd = _selectedLicense()?.isNoDerivatives ?? false;
    final effective = !nd && _remixable;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(context.l10n.publishAllowRemixes),
      subtitle: Text(
        nd ? context.l10n.publishNdNoRemixes : context.l10n.publishAllowRemixesBody,
        style: const TextStyle(fontSize: 12),
      ),
      value: effective,
      onChanged: (uploading || nd) ? null : (v) => setState(() => _remixable = v),
    );
  }

  /// Transparency line when this publish will declare public lineage.
  List<Widget> _remixDeclarationNote() {
    final parents = _draft.provenance?.parents ?? const [];
    if (parents.isEmpty || _stripRemixClaim) return const [];
    final src = _draft.source;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          src != null
              ? context.l10n.publishRemixNote(src.title, src.ownerHandle)
              : context.l10n.publishRemixNoteCount(parents.length),
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ),
    ];
  }

  Map<String, String> _provenanceFields({required bool replacing}) => provenanceFormFields(
        appVersion: _appVersion,
        platform: Platform.operatingSystem,
        deviceType: _deviceType(),
        provenance: _draft.provenance,
        replacedSqid: replacing ? _draft.source?.sqid : null,
        // The Remixable toggle belongs to upload (and later PATCH) — replace ignores it. An ND
        // license omits the field: the server applies its own effective default (false).
        remixable: replacing || (_selectedLicense()?.isNoDerivatives ?? false) ? null : _remixable,
        declareParents: !_stripRemixClaim,
      );

  /// After an upload/replace refused with 422 `remix_not_allowed` / `parent_not_found`: surface
  /// it and let the USER decide whether to publish without the remix declaration (the server
  /// asked that clients never strip it silently).
  Future<void> _offerStripRemixClaim({required bool replacing}) async {
    final pub = ref.read(publishControllerProvider);
    final gone = pub.errorCode == 'parent_not_found';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gone ? ctx.l10n.publishParentGoneTitle : ctx.l10n.publishRemixOffTitle),
        content: Text(
          '${gone ? ctx.l10n.publishParentGoneBody : ctx.l10n.publishRemixOffBody}\n\n'
          '${ctx.l10n.publishStripClaimBody}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.commonCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.publishStripClaimAction),
          ),
        ],
      ),
    );
    if (proceed == true && mounted) {
      setState(() => _stripRemixClaim = true);
      if (replacing) {
        await _replace();
      } else {
        await _submit();
      }
    }
  }

  Future<void> _replace() async {
    final d = _draft;
    await ref.read(publishControllerProvider.notifier).replace(
          postId: d.source!.postId,
          bytes: d.bytes,
          filename: d.filename,
          provenanceFields: _provenanceFields(replacing: true),
        );
    if (!mounted) return;
    if (ref.read(publishControllerProvider).isLineageRefusal && !_stripRemixClaim) {
      await _offerStripRemixClaim(replacing: true);
    }
  }

  /// One-tap conformance remedy: nearest-neighbor rescale of the draft to the
  /// nearest allowed size (engine isolate; frames + durations survive). The
  /// output re-encodes as lossless WebP (animated) or PNG (static) — GIF would
  /// re-quantize and BMP has no encoder.
  Future<void> _scaleToNearest(List<int> size) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _scaling = true);
    final d = _draft;
    final format = d.isAnimated ? 'webp' : 'png';
    final bytes =
        await rescaleArtworkBytes(d.bytes, width: size[0], height: size[1], format: format);
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _scaling = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.publishScaleFailed)));
      return;
    }
    setState(() {
      _scaling = false;
      _draft = PublishDraft(
        bytes: bytes,
        format: format,
        filename: _scaledFilename(d.filename, format),
        width: size[0],
        height: size[1],
        frameCount: d.frameCount,
        source: d.source,
        mkpxBytes: null, // remedy is hidden when a layers file exists
        totalDurationMs: d.totalDurationMs,
      );
    });
    messenger.showSnackBar(SnackBar(content: Text(l10n.publishScaled(size[0], size[1]))));
  }

  static String _scaledFilename(String name, String ext) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '$base-scaled.$ext';
  }

  /// "Share the layers (.mkpx) file" toggle. Present only when the server
  /// advertises the capability (`upload.mkpx.enabled`) and the draft came from
  /// the editor (direct file uploads carry no document). Oversize documents get
  /// a disabled toggle with the reason instead of a server 413.
  List<Widget> _shareLayersTile(ClubServerConfig cfg, bool uploading) {
    final mkpx = _draft.mkpxBytes;
    final rules = cfg.upload.mkpx;
    if (!rules.enabled || mkpx == null) return const [];
    final tooLarge = mkpx.length > rules.maxFileBytes;
    if (tooLarge && _shareLayers) _shareLayers = false;
    final kib = (mkpx.length / 1024).toStringAsFixed(0);
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.publishShareLayers),
        subtitle: Text(
          tooLarge
              ? context.l10n.publishLayersTooLarge(
                  kib, (rules.maxFileBytes / (1024 * 1024)).toStringAsFixed(0))
              : context.l10n.publishShareLayersBody(kib),
          style: TextStyle(fontSize: 12, color: tooLarge ? Colors.amberAccent : null),
        ),
        value: _shareLayers,
        onChanged: (uploading || tooLarge) ? null : (v) => setState(() => _shareLayers = v),
      ),
    ];
  }

  Widget _conformanceBanner(ConformanceResult r) {
    final l10n = context.l10n;
    if (r.ok) {
      return _banner(const Color(0x2200C853), const Color(0xFF00C853), Icons.check_circle_outline,
          l10n.publishReady);
    }
    final msgs = <String>[];
    for (final i in r.issues) {
      switch (i) {
        case ConformanceIssue.overMax:
          msgs.add(l10n.publishTooLarge);
        case ConformanceIssue.underMinNotWhitelisted:
          msgs.add(l10n.publishSizeNotAllowed);
        case ConformanceIssue.fileTooLarge:
          msgs.add(l10n.publishFileTooLarge);
        case ConformanceIssue.unsupportedFormat:
          msgs.add(l10n.publishUnsupportedFormat);
      }
    }
    if (r.nearestSize != null) {
      // The one-tap scale button renders right below when there's no layers
      // file; editor drafts with one keep the resize-in-the-editor guidance.
      msgs.add(_draft.mkpxBytes == null
          ? l10n.publishNearestSize(r.nearestSize![0], r.nearestSize![1])
          : l10n.publishNearestSizeEditor(r.nearestSize![0], r.nearestSize![1]));
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
      decoration: InputDecoration(
          labelText: context.l10n.publishLicense, border: const OutlineInputBorder()),
      items: [
        DropdownMenuItem<int?>(
            value: null,
            child: Text(context.l10n.publishNoLicense, overflow: TextOverflow.ellipsis)),
        for (final l in licenses)
          DropdownMenuItem<int?>(value: l.id, child: Text(l.identifier, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => setState(() => _licenseId = v),
    );
  }

  Future<void> _submit() async {
    final d = _draft;
    // Mirror the tile's visibility/size gates: with the opt-out default, _shareLayers can be
    // true while the tile never showed (capability off) — never send the file in those cases.
    final rules = (ref.read(serverConfigProvider).valueOrNull ?? ClubServerConfig.fallback).upload.mkpx;
    final mkpx = d.mkpxBytes;
    final sendMkpx = _shareLayers && rules.enabled && mkpx != null && mkpx.length <= rules.maxFileBytes;
    await ref.read(publishControllerProvider.notifier).submit(
          bytes: d.bytes,
          filename: d.filename,
          title: _title.text.trim().isEmpty ? context.l10n.untitled : _title.text.trim(),
          description: _mentions.serialized(maxMentions: _maxMentions).trim(),
          // The server splits on the ASCII comma; Chinese and Japanese keyboards type "，" or "、".
          hashtags: _tags.text.replaceAll(RegExp('[，、]'), ',').trim(),
          hidden: _hidden,
          licenseId: _licenseId,
          mkpxBytes: sendMkpx ? mkpx : null,
          provenanceFields: _provenanceFields(replacing: false),
        );
    if (!mounted) return;
    if (ref.read(publishControllerProvider).isLineageRefusal && !_stripRemixClaim) {
      await _offerStripRemixClaim(replacing: false);
    }
  }
}

class _Success extends ConsumerWidget {
  final Post? post;
  const _Success({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sqid = post?.sqid ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.publishedTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle, color: Color(0xFF00C853), size: 56),
            const SizedBox(height: 12),
            Text(context.l10n.publishedBody,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            if (sqid.isNotEmpty)
              FilledButton.icon(
                onPressed: () {
                  ref.read(publishControllerProvider.notifier).reset();
                  Navigator.pushReplacement(
                      context, MaterialPageRoute(builder: (_) => ArtworkDetailPage(sqid: sqid)));
                },
                icon: const Icon(Icons.open_in_new),
                label: Text(context.l10n.publishedView),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                ref.read(publishControllerProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              child: Text(context.l10n.publishedBack),
            ),
          ]),
        ),
      ),
    );
  }
}
