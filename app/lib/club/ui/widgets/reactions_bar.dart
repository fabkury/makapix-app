import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/reactions.dart';
import '../../state/auth_controller.dart';
import '../../state/post_providers.dart';
import '../club_account_page.dart';

/// The curated 5-emoji reaction row with optimistic toggle.
class ReactionsBar extends ConsumerWidget {
  final int postId;
  const ReactionsBar({super.key, required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(reactionsProvider(postId)).value ?? const ReactionTotals();
    final ctrl = ref.read(reactionsProvider(postId).notifier);
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final emoji in kReactionEmojis)
          _Chip(
            emoji: emoji,
            count: totals.countFor(emoji),
            mine: totals.hasMine(emoji),
            onTap: () async {
              if (!signedIn) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubAccountPage()));
                return;
              }
              final err = await ctrl.toggle(emoji);
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
              }
            },
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onTap;
  const _Chip({required this.emoji, required this.count, required this.mine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: mine ? const Color(0x334080C0) : const Color(0xFF222428),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: mine ? const Color(0xFF4080C0) : const Color(0x00000000)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          if (count > 0)
            Padding(padding: const EdgeInsets.only(left: 6), child: Text('$count', style: const TextStyle(fontSize: 13))),
        ]),
      ),
    );
  }
}
