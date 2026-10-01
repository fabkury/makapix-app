import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makapix_club/l10n/l10n.dart';

import '../../models/club_error.dart';
import '../../state/auth_controller.dart';

/// Settings → Account → Danger zone: permanently delete the signed-in account
/// (App Store guideline 5.1.1(v)). Explains what deletion means, requires the
/// user to type DELETE, then calls `POST /user/delete-account` (202 — the
/// server deactivates immediately and erases data asynchronously), confirms,
/// signs out locally, and returns to the root (signed-out welcome).
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});
  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final _confirm = TextEditingController();
  bool _busy = false;

  /// The delete button arms when the field holds the confirmation word — "DELETE" in English,
  /// each language's own word otherwise, so it can be typed on that language's keyboard.
  bool get _armed => _confirm.text.trim() == context.l10n.deleteAccountConfirmWord;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(clubApiClientProvider).requestAccountDeletion();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.deleteAccountDoneTitle),
          content: Text(ctx.l10n.deleteAccountDoneBody),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.commonOk)),
          ],
        ),
      );
      if (!mounted) return;
      await ref.read(authControllerProvider.notifier).logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ClubError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = ref.watch(authControllerProvider).me?.user.handle;
    final l10n = context.l10n;
    final word = l10n.deleteAccountConfirmWord;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountDelete)),
      body: CenteredContent(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF2A1518),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(l10n.deleteAccountPermanent,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.redAccent)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _bullet(handle != null
                      ? l10n.deleteAccountBullet1(handle)
                      : l10n.deleteAccountBullet1NoHandle),
                  _bullet(l10n.deleteAccountBullet2),
                  _bullet(l10n.deleteAccountBullet3),
                  _bullet(l10n.deleteAccountBullet4),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.deleteAccountTypePrompt(word),
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: l10n.deleteAccountTypeLabel(word),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.red.shade700.withValues(alpha: 0.25),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _armed && !_busy ? _delete : null,
            icon: _busy
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_forever),
            label: Text(l10n.deleteAccountButton),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text(l10n.commonCancel),
            ),
          ),
        ],
      )),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  ', style: TextStyle(color: Colors.white70)),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
          ],
        ),
      );
}
