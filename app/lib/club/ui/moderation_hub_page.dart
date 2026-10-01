import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pending_approval_page.dart';

/// The moderator hub reached from the home hamburger menu (moderator-only
/// entry). Today it hosts the pending-approval queue; future moderation
/// surfaces (reports queue, audit log…) get tiles here rather than more
/// hamburger entries.
class ModerationHubPage extends ConsumerWidget {
  const ModerationHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.menuModeration)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(context.l10n.pendingTitle),
            subtitle: Text(context.l10n.modHubPendingSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PendingApprovalPage())),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Text(
              context.l10n.modHubNote,
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}
