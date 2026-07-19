import 'package:flutter/material.dart';

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
    final registered = await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RegisterSheet(),
    );
    if (registered == true && mounted) _toast('Player registered.');
  }

  Future<void> _rename(PlayerDevice p) async {
    final controller = TextEditingController(text: p.name ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename player'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Player name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return _toast('Player name cannot be empty.');
    if (trimmed == (p.name ?? '')) return;
    final err = await ref.read(playerControllerProvider.notifier).rename(p.id, trimmed);
    if (!mounted) return;
    _toast(err ?? 'Renamed.');
  }

  Future<void> _delete(PlayerDevice p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete player'),
        content: Text('Remove "${p.displayName}"? It will stop receiving artworks '
            'until it is registered again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final err = await ref.read(playerControllerProvider.notifier).remove(p.id);
    if (!mounted) return;
    _toast(err ?? 'Player deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authControllerProvider.select((a) => a.isSignedIn));
    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Players')),
        body: SignInPrompt(
          message: 'Sign in to register and manage your players.',
          onSignIn: () => Navigator.pop(context),
        ),
      );
    }

    final st = ref.watch(playerControllerProvider);
    final players = st.players;
    final online = players.where((p) => p.isOnline).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Players'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Register player',
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
                      label: const Text('Register a player'),
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
              _stat(context, '$total', 'Total'),
              _stat(context, '$online', 'Online'),
              _stat(context, '${total - online}', 'Offline'),
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
              Text('No players registered', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text(
                'Register a player to display your artworks on a physical device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _openRegister,
                icon: const Icon(Icons.add),
                label: const Text('Register your first player'),
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
                    online ? 'Online' : _offlineLabel(player.lastSeenAt),
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
              tooltip: 'Player options',
              onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Rename'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _offlineLabel(DateTime? lastSeen) {
    if (lastSeen == null) return 'Offline';
    final d = DateTime.now().difference(lastSeen);
    if (d.isNegative || d.inSeconds < 60) return 'Offline · last seen just now';
    if (d.inMinutes < 60) return 'Offline · last seen ${d.inMinutes}m ago';
    if (d.inHours < 24) return 'Offline · last seen ${d.inHours}h ago';
    return 'Offline · last seen ${d.inDays}d ago';
  }
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

  String _friendly(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('invalid') || r.contains('expired') || r.contains('not found')) {
      return 'This code is invalid or has expired.';
    }
    if (r.contains('already registered')) return 'This player is already registered.';
    if (r.contains('maximum') && r.contains('player')) {
      return "You've reached the maximum number of players.";
    }
    return raw;
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    final name = _name.text.trim();
    if (code.length != 6) return setState(() => _error = 'Enter the 6-character code.');
    if (name.isEmpty) return setState(() => _error = 'Enter a name for this player.');
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
          Text('Register a player', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [_CodeFormatter()],
            style: const TextStyle(fontFamily: 'monospace', letterSpacing: 4, fontSize: 20),
            decoration: const InputDecoration(
              labelText: 'Registration code',
              hintText: 'A3F8X2',
              border: OutlineInputBorder(),
              helperText: 'The 6-character code shown on your player.',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            enabled: !_busy,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Player name',
              hintText: 'Living Room Display',
              border: OutlineInputBorder(),
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
                : const Text('Register'),
          ),
        ],
      ),
    );
  }
}
