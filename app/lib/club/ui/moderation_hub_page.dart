import 'package:flutter/material.dart';
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
      appBar: AppBar(title: const Text('Moderation')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Pending approval'),
            subtitle: const Text('Artworks awaiting public visibility'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PendingApprovalPage())),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Text(
              'Post and comment actions live where the content is: the artwork '
              'page’s menu, each comment’s Mod menu, and User Management on '
              'profiles. The website’s Moderator Dashboard has the rest '
              '(reports, pulse, audit log, metrics).',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}
