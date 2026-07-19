import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';

import '../../models/player_device.dart';

/// A modal that lists the online players and returns the one the user picks (or null if
/// dismissed). Used by the Player Bar when more than one device is online.
Future<PlayerDevice?> showSelectPlayer(
  BuildContext context,
  List<PlayerDevice> online, {
  String? selectedId,
  String title = 'Choose a player',
}) {
  return showAppSheet<PlayerDevice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final p in online)
              ListTile(
                leading: Icon(
                  p.id == selectedId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: p.id == selectedId ? cs.primary : null,
                ),
                title: Text(p.displayName),
                subtitle: p.deviceModel != null ? Text(p.deviceModel!) : null,
                onTap: () => Navigator.pop(ctx, p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
