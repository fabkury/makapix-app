import 'dart:async';

import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/account_validators.dart';
import '../../models/account.dart';
import '../../models/club_error.dart';
import '../../state/auth_controller.dart';
import '../widgets/common.dart';
import 'delete_account_page.dart';

/// Settings → Account: change password, change handle, and view/unlink linked
/// logins. Reached from [SettingsPage] and the signed-in account view.
class AccountManagementPage extends ConsumerStatefulWidget {
  const AccountManagementPage({super.key});
  @override
  ConsumerState<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends ConsumerState<AccountManagementPage> {
  // change-password
  final _current = TextEditingController();
  final _newPw = TextEditingController();
  final _confirmPw = TextEditingController();
  bool _pwBusy = false;
  bool _obscure = true;

  // change-handle
  final _handle = TextEditingController();
  Timer? _handleDebounce;
  bool _handleBusy = false;
  String _handleMsg = '';
  Color _handleColor = Colors.white54;
  bool _handleInit = false;

  // linked logins
  Future<List<AuthIdentity>>? _providers;

  @override
  void initState() {
    super.initState();
    _providers = ref.read(clubApiClientProvider).listProviders();
  }

  @override
  void dispose() {
    _handleDebounce?.cancel();
    _current.dispose();
    _newPw.dispose();
    _confirmPw.dispose();
    _handle.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _changePassword() async {
    final err = validatePasswordError(_newPw.text);
    if (err != null) return _toast(err);
    if (_newPw.text != _confirmPw.text) return _toast('Passwords don\'t match.');
    setState(() => _pwBusy = true);
    try {
      await ref.read(clubApiClientProvider).changePassword(_current.text, _newPw.text);
      _current.clear();
      _newPw.clear();
      _confirmPw.clear();
      _toast('Password changed.');
    } on ClubError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _pwBusy = false);
    }
  }

  void _onHandleChanged(String v, String currentHandle) {
    _handleDebounce?.cancel();
    if (v.trim().toLowerCase() == currentHandle.toLowerCase()) {
      setState(() => _handleMsg = '');
      return;
    }
    final local = validateHandleError(v);
    if (local != null) {
      setState(() {
        _handleMsg = local;
        _handleColor = Colors.orangeAccent;
      });
      return;
    }
    setState(() {
      _handleMsg = 'Checking…';
      _handleColor = Colors.white54;
    });
    _handleDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final res = await ref.read(clubApiClientProvider).checkHandle(v.trim());
        if (!mounted) return;
        setState(() {
          _handleMsg = res.message;
          _handleColor = res.available ? Colors.greenAccent : Colors.redAccent;
        });
      } on ClubError catch (e) {
        if (mounted) setState(() => _handleMsg = e.message);
      }
    });
  }

  Future<void> _changeHandle(String currentHandle) async {
    final handle = _handle.text.trim();
    if (handle.toLowerCase() == currentHandle.toLowerCase()) return;
    final err = validateHandleError(handle);
    if (err != null) return _toast(err);
    setState(() => _handleBusy = true);
    try {
      await ref.read(clubApiClientProvider).changeHandle(handle);
      await ref.read(authControllerProvider.notifier).reloadMe();
      setState(() => _handleMsg = '');
      _toast('Handle updated.');
    } on ClubError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _handleBusy = false);
    }
  }

  Future<void> _unlink(AuthIdentity id) async {
    try {
      await ref.read(clubApiClientProvider).unlinkProvider(id.provider, id.id);
      setState(() => _providers = ref.read(clubApiClientProvider).listProviders());
      _toast('Unlinked ${id.label}.');
    } on ClubError catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).me;
    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: SignInPrompt(
            message: 'Sign in to manage your account.', onSignIn: () => Navigator.pop(context)),
      );
    }
    if (!_handleInit) {
      _handle.text = me.user.handle;
      _handleInit = true;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: CenteredContent(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Change password', [
            TextField(
              controller: _current,
              obscureText: _obscure,
              enabled: !_pwBusy,
              decoration: InputDecoration(
                labelText: 'Current password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newPw,
              obscureText: _obscure,
              enabled: !_pwBusy,
              decoration: const InputDecoration(
                labelText: 'New password',
                border: OutlineInputBorder(),
                helperText: 'At least 8 characters, with a letter and a number.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmPw,
              obscureText: _obscure,
              enabled: !_pwBusy,
              decoration:
                  const InputDecoration(labelText: 'Confirm new password', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _pwBusy ? null : _changePassword,
                child: _pwBusy
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Change password'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _section('Change handle', [
            TextField(
              controller: _handle,
              enabled: !_handleBusy,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: 'Handle', prefixText: '@', border: OutlineInputBorder()),
              onChanged: (v) => _onHandleChanged(v, me.user.handle),
            ),
            if (_handleMsg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(_handleMsg, style: TextStyle(color: _handleColor, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _handleBusy ? null : () => _changeHandle(me.user.handle),
                child: _handleBusy
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Update handle'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _section('Linked logins', [_providersList()]),
          const SizedBox(height: 8),
          _section('Danger zone', [
            const Text(
              'Permanently delete your account, including all your posts, '
              'comments, reactions, and profile data.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                ),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DeleteAccountPage())),
                icon: const Icon(Icons.delete_forever_outlined, size: 20),
                label: const Text('Delete account'),
              ),
            ),
          ]),
        ],
      )),
    );
  }

  Widget _providersList() => FutureBuilder<List<AuthIdentity>>(
        future: _providers,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          if (snap.hasError) {
            return const Text('Could not load linked logins.',
                style: TextStyle(color: Colors.white54));
          }
          final items = snap.data ?? const <AuthIdentity>[];
          if (items.isEmpty) {
            return const Text('No linked logins.', style: TextStyle(color: Colors.white54));
          }
          final canUnlink = items.length > 1;
          return Column(
            children: [
              for (final id in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(id.isGithub ? Icons.code : Icons.alternate_email, size: 20),
                  title: Text(id.label),
                  subtitle: id.email != null
                      ? Text(id.email!, style: const TextStyle(color: Colors.white54, fontSize: 12))
                      : null,
                  trailing: TextButton(
                    onPressed: canUnlink ? () => _unlink(id) : null,
                    child: const Text('Unlink'),
                  ),
                ),
              if (!canUnlink)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text("You can't unlink your only login method.",
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
            ],
          );
        },
      );

  Widget _section(String title, List<Widget> children) => Card(
        color: const Color(0xFF15171A),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
}
