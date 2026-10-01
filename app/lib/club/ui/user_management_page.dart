import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../edit/reputation_gear.dart';
import '../models/club_error.dart';
import '../models/umd.dart';
import '../state/api_providers.dart';
import '../state/moderation_providers.dart';
import 'widgets/common.dart';

/// Moderator-only management page for one user — the app counterpart of the
/// website's `/u/{sqid}/manage` (UMD). Reached from the profile overflow menu.
/// The server owner-protects every endpoint (403 for the owner as target).
class UserManagementPage extends ConsumerWidget {
  final String sqid;

  /// Shown in the title while the payload loads (the opener always knows it).
  final String handle;
  const UserManagementPage({super.key, required this.sqid, required this.handle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(umdUserProvider(sqid));
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.umdTitle(handle))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ClubErrorRetry(
          message: e is ClubError
              ? (e.status == 403 ? context.l10n.umdOwnerProtected : e.message)
              : context.l10n.umdLoadFailed,
          onRetry: () async => ref.invalidate(umdUserProvider(sqid)),
        ),
        data: (u) => _UmdBody(user: u),
      ),
    );
  }
}

class _UmdBody extends ConsumerWidget {
  final UmdUserData user;
  const _UmdBody({required this.user});

  void _refresh(WidgetRef ref) => ref.invalidate(umdUserProvider(user.sqid));

  /// Run a moderation call, then refetch the payload; errors become snackbars.
  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() call,
      {required String done, required String failed}) async {
    final messenger = ScaffoldMessenger.of(context);
    final ownerProtected = context.l10n.umdOwnerProtected;
    try {
      await call();
      _refresh(ref);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ClubError catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(e.status == 403 ? ownerProtected : e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(context),
        const SizedBox(height: 16),
        _sectionCard(context, l10n.umdActions, [
          SwitchListTile(
            value: user.autoPublicApproval,
            // One long German word ("Vertrauenswürdig") is wider than a 320 px phone leaves.
            title: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(l10n.umdTrusted),
            ),
            subtitle: Text(l10n.umdTrustedBody),
            secondary: const Icon(Icons.verified_outlined),
            onChanged: (v) => _run(context, ref,
                () => ref.read(moderationApiProvider).setUserTrusted(user.sqid, v),
                done: v ? l10n.umdTrustGranted(user.handle) : l10n.umdTrustRevoked,
                failed: l10n.umdTrustFailed),
          ),
          ListTile(
            leading: Icon(
                user.hiddenByMod ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            title: Text(user.hiddenByMod ? l10n.umdUnhideProfile : l10n.umdHideProfile),
            subtitle:
                Text(user.hiddenByMod ? l10n.umdProfileHiddenNow : l10n.umdHideProfileBody),
            onTap: () => _toggleHidden(context, ref),
          ),
          if (user.isBanned)
            ListTile(
              leading: const Icon(Icons.gavel, color: Colors.redAccent),
              title: Text(user.isPermanentlyBanned
                  ? l10n.umdBannedPermanently
                  : l10n.umdBannedUntil(_fmtDate(user.bannedUntil!))),
              subtitle: Text(l10n.umdBannedBody),
            ),
          // Its own row, like the other actions: as a trailing button, a long "Unban" left the
          // status line 25 px on a phone.
          if (user.isBanned)
            ListTile(
              leading: const Icon(Icons.lock_open),
              title: Text(l10n.umdUnban),
              onTap: () => _unban(context, ref),
            )
          else
            ListTile(
              leading: const Icon(Icons.gavel),
              title: Text(l10n.umdBanUser),
              subtitle: Text(l10n.umdBanUserBody),
              onTap: () => _ban(context, ref),
            ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: Text(l10n.umdRevealEmail),
            subtitle: Text(l10n.umdRevealEmailBody),
            onTap: () => _revealEmail(context, ref),
          ),
        ]),
        const SizedBox(height: 16),
        _ReputationCard(user: user),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Row(children: [
      HandleAvatar(url: user.avatarUrl, handle: user.handle, radius: 28),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('@${user.handle}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 2),
          Text(
            [
              context.l10n.umdReputationLine(user.reputation),
              if (user.roles.any((r) => r != 'user')) user.roles.join(', '),
              if (user.createdAt != null) context.l10n.umdJoined(_fmtDate(user.createdAt!)),
            ].join('  ·  '),
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          if (user.badges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final b in user.badges)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(b, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _sectionCard(BuildContext context, String title, List<Widget> children) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white70)),
          ),
          ...children,
        ]),
      ),
    );
  }

  Future<void> _toggleHidden(BuildContext context, WidgetRef ref) async {
    final hide = !user.hiddenByMod;
    final l10n = context.l10n;
    if (hide) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.umdHideTitle(user.handle)),
          content: Text(ctx.l10n.umdHideBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.commonHide)),
          ],
        ),
      );
      if (yes != true || !context.mounted) return;
    }
    await _run(context, ref,
        () => ref.read(moderationApiProvider).setUserHidden(user.sqid, hide),
        done: hide ? l10n.umdProfileHidden : l10n.umdProfileVisible,
        failed: l10n.umdVisibilityFailed);
  }

  Future<void> _unban(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.umdUnbanTitle(user.handle)),
        content: Text(ctx.l10n.umdUnbanBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.umdUnban)),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    await _run(context, ref, () => ref.read(moderationApiProvider).unbanUser(user.sqid),
        done: l10n.umdUnbanned(user.handle), failed: l10n.umdUnbanFailed);
  }

  Future<void> _ban(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final days = await showBanDurationDialog(context, handle: user.handle);
    if (days == null || !context.mounted) return;
    if (days == kPermanentBan) {
      // Permanent ban gets the irreversible-style second step (it is lifted
      // only by an explicit moderator unban, never by time).
      final second = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.umdBanPermTitle),
          content: Text(ctx.l10n.umdBanPermBody(user.handle)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.umdBanPermAction),
            ),
          ],
        ),
      );
      if (second != true || !context.mounted) return;
    }
    await _run(
        context,
        ref,
        () => ref
            .read(moderationApiProvider)
            .banUser(user.sqid, durationDays: days == kPermanentBan ? null : days),
        done: days == kPermanentBan
            ? l10n.umdBannedPermToast(user.handle)
            : l10n.umdBannedForToast(user.handle, days),
        failed: l10n.umdBanFailed);
  }

  /// Two dialogs by design: consent first (the server audit-logs the reveal
  /// BEFORE returning the address), then the address with a copy affordance.
  Future<void> _revealEmail(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.umdRevealTitle(user.handle)),
        content: Text(ctx.l10n.umdRevealBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.umdRevealAction)),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final String email;
    try {
      email = await ref.read(moderationApiProvider).revealUserEmail(user.sqid);
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.umdRevealFailed)));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('@${user.handle}'),
        content: SelectableText(email.isEmpty ? ctx.l10n.umdNoEmail : email),
        actions: [
          if (email.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: email));
                Navigator.pop(ctx);
                messenger.showSnackBar(SnackBar(content: Text(l10n.emailCopied)));
              },
              child: Text(ctx.l10n.commonCopy),
            ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.commonClose)),
        ],
      ),
    );
  }
}

/// Reputation adjustment (UMD): the website's gamma-1.5 geared slider, plus an
/// exact-value field that stays in sync both ways, and the required reason.
class _ReputationCard extends ConsumerStatefulWidget {
  final UmdUserData user;
  const _ReputationCard({required this.user});

  @override
  ConsumerState<_ReputationCard> createState() => _ReputationCardState();
}

class _ReputationCardState extends ConsumerState<_ReputationCard> {
  double _gear = 0; // slider position ∈ [-1, 1]; the delta derives from it
  final _deltaField = TextEditingController(text: '0');
  final _reason = TextEditingController();
  bool _busy = false;

  int get _delta => deltaFromGear(_gear);

  @override
  void dispose() {
    _deltaField.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _setGear(double t) => setState(() {
        _gear = t;
        _deltaField.text = '${deltaFromGear(t)}';
      });

  void _setDeltaText(String s) {
    final v = int.tryParse(s.trim());
    if (v == null) return; // partial input ("-", empty) — keep the slider put
    setState(() => _gear = gearFromDelta(v));
  }

  Future<void> _apply() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final delta = _delta;
    setState(() => _busy = true);
    try {
      final total = await ref.read(moderationApiProvider).adjustUserReputation(
          widget.user.sqid,
          delta: delta,
          reason: _reason.text.trim());
      ref.invalidate(umdUserProvider(widget.user.sqid));
      _reason.clear();
      _setGear(0);
      messenger.showSnackBar(SnackBar(
          content: Text(l10n.umdRepApplied('${delta > 0 ? '+' : ''}$delta', total))));
    } on ClubError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.umdRepFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final delta = _delta;
    final valid = reputationAdjustValid(delta, _reason.text);
    final l10n = context.l10n;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.umdReputationTitle,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            delta == 0
                ? l10n.umdRepCurrent(widget.user.reputation)
                : '${l10n.umdRepCurrent(widget.user.reputation)}   →   '
                    '${widget.user.reputation + delta} (${delta > 0 ? '+' : ''}$delta)',
            style: const TextStyle(fontSize: 13),
          ),
          // Geared: travel near the center maps to single digits, the ends
          // reach ±1000 (deltaFromGear's gamma bias — same as the website).
          Slider(
            value: _gear,
            min: -1,
            max: 1,
            onChanged: _busy ? null : _setGear,
          ),
          Row(children: [
            SizedBox(
              width: 96,
              child: TextField(
                controller: _deltaField,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: InputDecoration(
                  labelText: l10n.umdRepDelta,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _setDeltaText,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n.umdRepNote,
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            enabled: !_busy,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: l10n.umdRepReason,
              helperText: l10n.umdRepReasonHelper,
              border: const OutlineInputBorder(),
              counterText: '',
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy || !valid ? null : _apply,
              child: Text(_busy ? l10n.umdApplying : l10n.commonApply),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Sentinel returned by [showBanDurationDialog] for a permanent ban.
const int kPermanentBan = -1;

/// Ban-duration preset picker: 1 / 7 / 30 / 90 / 365 days or permanent.
/// Pops the chosen day count, [kPermanentBan] for permanent, null on cancel.
/// Top-level so it's widget-testable.
Future<int?> showBanDurationDialog(BuildContext context, {required String handle}) {
  const presets = [1, 7, 30, 90, 365, kPermanentBan];
  var choice = 7;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(ctx.l10n.banTitle(handle)),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioGroup<int>(
            groupValue: choice,
            onChanged: (v) => setState(() => choice = v ?? choice),
            child: Column(children: [
              for (final days in presets)
                RadioListTile<int>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(days == kPermanentBan
                      ? ctx.l10n.banPermanent
                      : ctx.l10n.daysCount(days)),
                  value: days,
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(ctx.l10n.banNote, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, choice), child: Text(ctx.l10n.banAction)),
        ],
      ),
    ),
  );
}

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}
