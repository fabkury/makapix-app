import 'dart:async';

import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makapix_club/l10n/l10n.dart';

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
    if (_newPw.text != _confirmPw.text) return _toast(context.l10n.authPasswordsDontMatch);
    final changed = context.l10n.accountPasswordChanged;
    setState(() => _pwBusy = true);
    try {
      await ref.read(clubApiClientProvider).changePassword(_current.text, _newPw.text);
      _current.clear();
      _newPw.clear();
      _confirmPw.clear();
      _toast(changed);
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
      _handleMsg = context.l10n.handleChecking;
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
    final updated = context.l10n.accountHandleUpdated;
    try {
      await ref.read(clubApiClientProvider).changeHandle(handle);
      await ref.read(authControllerProvider.notifier).reloadMe();
      setState(() => _handleMsg = '');
      _toast(updated);
    } on ClubError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _handleBusy = false);
    }
  }

  Future<void> _unlink(AuthIdentity id) async {
    final unlinked = context.l10n.accountUnlinked(_loginLabel(context.l10n, id));
    try {
      await ref.read(clubApiClientProvider).unlinkProvider(id.provider, id.id);
      setState(() => _providers = ref.read(clubApiClientProvider).listProviders());
      _toast(unlinked);
    } on ClubError catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).me;
    final l10n = context.l10n;
    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.accountTitle)),
        body: SignInPrompt(
            message: l10n.accountSignInPrompt, onSignIn: () => Navigator.pop(context)),
      );
    }
    if (!_handleInit) {
      _handle.text = me.user.handle;
      _handleInit = true;
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountTitle)),
      body: CenteredContent(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(l10n.accountChangePassword, [
            TextField(
              controller: _current,
              obscureText: _obscure,
              enabled: !_pwBusy,
              decoration: InputDecoration(
                labelText: l10n.accountCurrentPassword,
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
              decoration: InputDecoration(
                labelText: l10n.authNewPassword,
                border: const OutlineInputBorder(),
                helperText: l10n.authPasswordHelper,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmPw,
              obscureText: _obscure,
              enabled: !_pwBusy,
              decoration: InputDecoration(
                  labelText: l10n.accountConfirmNewPassword, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _pwBusy ? null : _changePassword,
                child: _pwBusy
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.accountChangePassword),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _section(l10n.accountChangeHandle, [
            TextField(
              controller: _handle,
              enabled: !_handleBusy,
              autocorrect: false,
              decoration: InputDecoration(
                  labelText: l10n.accountHandle, prefixText: '@', border: const OutlineInputBorder()),
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
                    : Text(l10n.accountUpdateHandle),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _section(l10n.accountLinkedLogins, [_providersList()]),
          const SizedBox(height: 8),
          _section(l10n.accountDangerZone, [
            Text(
              l10n.accountDeleteIntro,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
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
                label: Text(l10n.accountDelete),
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
          final l10n = context.l10n;
          if (snap.hasError) {
            return Text(l10n.accountLinkedLoadError, style: const TextStyle(color: Colors.white54));
          }
          final items = snap.data ?? const <AuthIdentity>[];
          if (items.isEmpty) {
            return Text(l10n.accountLinkedEmpty, style: const TextStyle(color: Colors.white54));
          }
          final canUnlink = items.length > 1;
          return Column(
            children: [
              for (final id in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(id.isGithub ? Icons.code : Icons.alternate_email, size: 20),
                  title: Text(_loginLabel(l10n, id)),
                  subtitle: id.email != null
                      ? Text(id.email!, style: const TextStyle(color: Colors.white54, fontSize: 12))
                      : null,
                  trailing: TextButton(
                    onPressed: canUnlink ? () => _unlink(id) : null,
                    child: Text(l10n.accountUnlink),
                  ),
                ),
              if (!canUnlink)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l10n.accountCantUnlinkOnly,
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ),
            ],
          );
        },
      );

  /// A linked login's name: "GitHub (octocat)", "Email & password", or the raw provider id.
  String _loginLabel(AppLocalizations l10n, AuthIdentity id) =>
      id.isPassword ? l10n.accountLoginPassword : id.label;

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
