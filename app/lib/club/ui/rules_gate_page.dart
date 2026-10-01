import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:makapix_club/l10n/rich.dart';

import '../state/publish_providers.dart';
import '../state/rules_gate.dart';
import 'widgets/external_links.dart';

/// The explicit "what you're agreeing to" line above the accept button. Names only
/// the documents the server advertised so it never points at a missing link.
String _agreementLine(AppLocalizations l10n, {required bool hasRules, required bool hasTerms}) {
  if (hasRules && hasTerms) return l10n.rulesGateAgreeBoth;
  if (hasTerms) return l10n.rulesGateAgreeTerms;
  return l10n.rulesGateAgreeRules;
}

/// The one-time, full-screen community-rules gate. Shown before the Club pillar
/// (and the editor's "Post to Club" entry) when the moderation feature is live
/// and this install hasn't accepted the current rules version.
class RulesGatePage extends ConsumerWidget {
  const RulesGatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moderation = ref.watch(serverConfigProvider).valueOrNull?.moderation;
    final theme = Theme.of(context);
    final l10n = context.l10n;
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
                Text(l10n.rulesGateTitle,
                    textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                // One message; the bold phrase is marked inside it (lib/l10n/rich.dart).
                Text.rich(
                  TextSpan(children: boldSpans(l10n.rulesGateBody)),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if ((moderation?.guidelinesUrl ?? '').isNotEmpty)
                  TextButton(
                    onPressed: () => openExternalUrl(context, moderation!.guidelinesUrl),
                    child: Text(l10n.rulesGateReadRules),
                  ),
                if ((moderation?.termsUrl ?? '').isNotEmpty)
                  TextButton(
                    onPressed: () => openExternalUrl(context, moderation!.termsUrl),
                    child: Text(l10n.termsOfService),
                  ),
                const SizedBox(height: 8),
                Text(
                  l10n.rulesGateReportNote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 20),
                // Explicit, adaptive agreement line: name only the documents the server
                // actually advertised, so the copy never references a missing link.
                Text(
                  _agreementLine(
                    l10n,
                    hasRules: (moderation?.guidelinesUrl ?? '').isNotEmpty,
                    hasTerms: (moderation?.termsUrl ?? '').isNotEmpty,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.read(rulesGateProvider.notifier).accept(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(l10n.rulesGateAgree),
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
