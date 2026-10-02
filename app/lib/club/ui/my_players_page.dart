import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/player_api.dart';
import '../models/player_device.dart';
import '../state/auth_controller.dart';
import '../state/player_providers.dart';
import 'widgets/common.dart';

/// "My Players": register, list, rename and delete the physical pixel-display devices the
/// signed-in user owns. Playback control (send / prev / next / adjustments) lives in the
/// bottom Player Bar, so this screen is purely device lifecycle + status.
class MyPlayersPage extends ConsumerStatefulWidget {
  const MyPlayersPage({super.key});
  @override
  ConsumerState<MyPlayersPage> createState() => _MyPlayersPageState();
}

class _MyPlayersPageState extends ConsumerState<MyPlayersPage> {
  @override
  void initState() {
    super.initState();
    // Pull a fresh list on open (the controller also polls every 15 s in the background).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(playerControllerProvider.notifier).refresh();
    });
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _openRegister() async {
    final l10n = context.l10n;
    final registered = await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RegisterSheet(),
    );
    if (registered == true && mounted) _toast(l10n.playersRegistered);
  }

  Future<void> _rename(PlayerDevice p) async {
    final controller = TextEditingController(text: p.name ?? '');
    final l10n = context.l10n;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.playersRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: ctx.l10n.playersName,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.commonCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(ctx.l10n.commonSave),
          ),
        ],
      ),
    );
    if (newName == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return _toast(l10n.playersNameEmpty);
    if (trimmed == (p.name ?? '')) return;
    final err = await ref.read(playerControllerProvider.notifier).rename(p.id, trimmed);
    if (!mounted) return;
    _toast(err ?? l10n.playersRenamed);
  }

  Future<void> _delete(PlayerDevice p) async {
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.playersDeleteTitle),
        content: Text(ctx.l10n.playersDeleteBody(p.displayName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final err = await ref.read(playerControllerProvider.notifier).remove(p.id);
    if (!mounted) return;
    _toast(err ?? l10n.playersDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authControllerProvider.select((a) => a.isSignedIn));
    final l10n = context.l10n;
    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.myPlayers)),
        body: SignInPrompt(
          message: l10n.playersSignIn,
          onSignIn: () => Navigator.pop(context),
        ),
      );
    }

    final st = ref.watch(playerControllerProvider);
    final players = st.players;
    final online = players.where((p) => p.isOnline).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myPlayers),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.playersRegisterTooltip,
            onPressed: _openRegister,
          ),
        ],
      ),
      body: CenteredContent(
          child: RefreshIndicator(
        onRefresh: () => ref.read(playerControllerProvider.notifier).refresh(),
        child: (st.loading && players.isEmpty)
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _statsBar(context, total: players.length, online: online),
                  const SizedBox(height: 16),
                  if (players.isEmpty)
                    _emptyState(context)
                  else ...[
                    for (final p in players) ...[
                      _PlayerTile(
                        player: p,
                        onRename: () => _rename(p),
                        onDelete: () => _delete(p),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _openRegister,
                      icon: const Icon(Icons.add),
                      label: Text(l10n.playersRegisterA),
                    ),
                  ],
                ],
              ),
      )),
    );
  }

  Widget _statsBar(BuildContext context, {required int total, required int online}) => Card(
        color: const Color(0xFF15171A),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat(context, '$total', context.l10n.playersTotal),
              _stat(context, '$online', context.l10n.playersOnline),
              _stat(context, '${total - online}', context.l10n.playersOffline),
            ],
          ),
        ),
      );

  Widget _stat(BuildContext context, String value, String label) => Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.5)),
        ],
      );

  Widget _emptyState(BuildContext context) => Card(
        color: const Color(0xFF15171A),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          child: Column(
            children: [
              const Icon(Icons.cast_outlined, size: 48, color: Colors.white24),
              const SizedBox(height: 12),
              Text(context.l10n.playersEmptyTitle,
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                context.l10n.playersEmptyBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _openRegister,
                icon: const Icon(Icons.add),
                label: Text(context.l10n.playersRegisterFirst),
              ),
            ],
          ),
        ),
      );
}

/// A single device row: name, status, model/firmware, last-seen, and a rename/delete menu.
class _PlayerTile extends StatelessWidget {
  final PlayerDevice player;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  const _PlayerTile({required this.player, required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final online = player.isOnline;
    final metaParts = <String>[
      if ((player.deviceModel ?? '').trim().isNotEmpty) player.deviceModel!.trim(),
      if ((player.firmwareVersion ?? '').trim().isNotEmpty) 'v${player.firmwareVersion!.trim()}',
    ];
    return Card(
      color: const Color(0xFF15171A),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 12),
              child: Icon(Icons.circle,
                  size: 12, color: online ? const Color(0xFF10B981) : Colors.white24),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(player.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    online
                        ? context.l10n.playersOnline
                        : _offlineLabel(context.l10n, player.lastSeenAt),
                    style: TextStyle(
                      color: online ? const Color(0xFF10B981) : Colors.white54,
                      fontSize: 12.5,
                    ),
                  ),
                  if (metaParts.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(metaParts.join(' · '),
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: context.l10n.playerOptions,
              onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Row(children: [
                    const Icon(Icons.edit_outlined, size: 18),
                    const SizedBox(width: 10),
                    Flexible(child: Text(ctx.l10n.commonRename)),
                  ]),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    const SizedBox(width: 10),
                    Flexible(
                        child: Text(ctx.l10n.commonDelete, style: const TextStyle(color: Colors.redAccent))),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _offlineLabel(AppLocalizations l10n, DateTime? lastSeen) => lastSeen == null
      ? l10n.playersOffline
      : l10n.playersOfflineSeen(timeAgo(lastSeen));
}

/// Uppercases input and keeps only [A-Z0-9], capped at 6 chars — matches the registration-code
/// alphabet (the server upper-cases too, and excludes ambiguous 0/O/I/1/L at generation time).
class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = normalizeRegistrationCode(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The register bottom sheet: a 6-char code + a name, submitted to `PlayerController.register`.
/// Pops `true` on success.
class _RegisterSheet extends ConsumerStatefulWidget {
  const _RegisterSheet();
  @override
  ConsumerState<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends ConsumerState<_RegisterSheet> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  /// The server answers a failed registration in English prose; the known cases are matched
  /// by their wording and shown in the app's language (docs/i18n/PLAN.md, L4 server text).
  String _friendly(String raw) {
    final l10n = context.l10n;
    final r = raw.toLowerCase();
    if (r.contains('invalid') || r.contains('expired') || r.contains('not found')) {
      return l10n.playersCodeInvalid;
    }
    if (r.contains('already registered')) return l10n.playersAlreadyRegistered;
    if (r.contains('maximum') && r.contains('player')) return l10n.playersMaxReached;
    return raw;
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    final name = _name.text.trim();
    if (code.length != 6) return setState(() => _error = context.l10n.playersEnterCode);
    if (name.isEmpty) return setState(() => _error = context.l10n.playersEnterName);
    setState(() {
      _busy = true;
      _error = null;
    });
    final err =
        await ref.read(playerControllerProvider.notifier).register(code: code, name: name);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = _friendly(err);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sit above the keyboard.
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.playersRegisterA, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [_CodeFormatter()],
            style: const TextStyle(fontFamily: 'monospace', letterSpacing: 4, fontSize: 20),
            decoration: InputDecoration(
              labelText: context.l10n.playersCode,
              hintText: 'A3F8X2',
              border: const OutlineInputBorder(),
              helperText: context.l10n.playersCodeHelper,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            enabled: !_busy,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: context.l10n.playersName,
              hintText: context.l10n.playersNameHint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.l10n.playersRegisterAction),
          ),
        ],
      ),
    );
  }
}
