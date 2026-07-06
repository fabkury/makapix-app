import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/publish_providers.dart';
import '../state/rules_gate.dart';
import 'widgets/external_links.dart';

/// The one-time, full-screen community-rules gate. Shown before the Club pillar
/// (and the editor's "Post to Club" entry) when the moderation feature is live
/// and this install hasn't accepted the current rules version.
class RulesGatePage extends ConsumerWidget {
  const RulesGatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moderation = ref.watch(serverConfigProvider).valueOrNull?.moderation;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.verified_user_outlined, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Community rules',
                    textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                Text.rich(
                  TextSpan(children: const [
                    TextSpan(text: 'Makapix Club is a shared space. We have '),
                    TextSpan(
                        text: 'zero tolerance',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(
                        text: ' for objectionable content or abusive behavior — content that '
                            'breaks the rules is removed and repeat offenders are banned.'),
                  ]),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if ((moderation?.guidelinesUrl ?? '').isNotEmpty)
                  TextButton(
                    onPressed: () => openExternalUrl(context, moderation!.guidelinesUrl),
                    child: const Text('Read the community rules'),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'You can report any content or user, and block anyone, from inside the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => ref.read(rulesGateProvider.notifier).accept(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Agree and continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
