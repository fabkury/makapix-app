import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/player_device.dart';
import '../../state/auth_controller.dart';
import '../../state/player_providers.dart';
import '../my_players_page.dart';
import 'select_player_overlay.dart';

/// Height of the bar's content row (excludes the bottom safe-area inset).
const double kPlayerBarHeight = 64;

/// A bar pinned to the bottom of the Club pillar that appears whenever the signed-in user owns
/// at least one online player device. Lets the user push the current artwork/channel to a device,
/// swap back/next, pause/resume, and (via the ⋮ menu) adjust brightness/rotation/mirror and switch
/// the active device. Returns an empty box when there's nothing to control, so it costs no layout.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authControllerProvider.select((a) => a.isSignedIn));
    // Only touch the player controller once signed in, so a signed-out session never starts the
    // poll timer (keeps widget tests free of pending timers, and avoids needless polling).
    if (!signedIn) return const SizedBox.shrink();
    final st = ref.watch(playerControllerProvider);
    final active = st.activePlayer;
    if (!st.hasOnlinePlayer || active == null) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final target = ref.watch(playerSendTargetProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final pending = st.pendingFor(active.id);
    final caps = active.capabilities;
    final isPaused = pending?.isPaused ?? active.isPaused ?? false;

    Future<void> run(Future<String?> Function() action, {String? okMessage}) async {
      final err = await action();
      if (!context.mounted) return;
      final msg = err ?? okMessage;
      if (msg != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }

    return Material(
      color: cs.surface,
      elevation: 8,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        // The bottom safe-area inset is consumed once by ClubPillar's SafeArea, so the bar is a
        // plain fixed-height row here.
        child: SizedBox(
          height: kPlayerBarHeight,
          child: Row(
            children: [
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Player options',
                  onPressed: () => _openAdjustments(context),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      Text(
                        target?.label ?? 'Nothing selected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (caps.pause)
                  IconButton(
                    icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                    tooltip: isPaused ? 'Resume' : 'Pause',
                    onPressed: () => controller.setPaused(active.id, !isPaused),
                  ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  tooltip: 'Previous',
                  onPressed: () => run(() => controller.swapBack(active.id)),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Next',
                  onPressed: () => run(() => controller.swapNext(active.id)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: IconButton.filled(
                    icon: const Icon(Icons.cast),
                    tooltip: 'Send to player',
                    onPressed: target == null
                        ? null
                        : () => run(
                              () => controller.send(active.id, target),
                              okMessage: 'Sent to ${active.displayName}',
                            ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  void _openAdjustments(BuildContext context) {
    showAppSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _AdjustmentsSheet(),
    );
  }
}

/// The ⋮ menu: switch active device, and adjust brightness / rotation / mirror — each gated on
/// the active device's declared capabilities.
class _AdjustmentsSheet extends ConsumerStatefulWidget {
  const _AdjustmentsSheet();
  @override
  ConsumerState<_AdjustmentsSheet> createState() => _AdjustmentsSheetState();
}

class _AdjustmentsSheetState extends ConsumerState<_AdjustmentsSheet> {
  // Local slider position while dragging; cleared (→ follows device/pending) once released.
  double? _dragBrightness;

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(playerControllerProvider);
    final active = st.activePlayer;
    if (active == null) return const SizedBox.shrink();
    final controller = ref.read(playerControllerProvider.notifier);
    final pending = st.pendingFor(active.id);
    final caps = active.capabilities;
    final online = st.onlinePlayers;

    final effRotation = pending?.rotation ?? active.rotation;
    final effMirror = pending?.mirror ?? active.mirror;
    final effBrightness = (pending?.brightness ?? active.brightness)?.toDouble();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (online.length > 1) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cast),
                title: const Text('Player'),
                subtitle: Text(active.displayName),
                trailing: const Icon(Icons.unfold_more),
                onTap: () async {
                  final chosen = await showSelectPlayer(context, online,
                      selectedId: st.activePlayerId);
                  if (chosen != null) controller.setActivePlayer(chosen.id);
                },
              ),
              const Divider(),
            ],
            if (caps.brightness != null) ...[
              const Text('Brightness'),
              Slider(
                min: caps.brightness!.min.toDouble(),
                max: caps.brightness!.max.toDouble(),
                divisions: _divisions(caps.brightness!),
                value: (_dragBrightness ?? effBrightness ?? caps.brightness!.min.toDouble())
                    .clamp(caps.brightness!.min.toDouble(), caps.brightness!.max.toDouble()),
                onChanged: (v) => setState(() => _dragBrightness = v),
                onChangeEnd: (v) {
                  controller.setBrightness(active.id, v.round());
                  setState(() => _dragBrightness = null);
                },
              ),
              const SizedBox(height: 8),
            ],
            if (caps.rotation.isNotEmpty) ...[
              const Text('Rotation'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final v in caps.rotation)
                    ChoiceChip(
                      label: Text('$v°'),
                      selected: v == effRotation,
                      onSelected: (_) => controller.setRotation(active.id, v),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (caps.mirror.isNotEmpty) ...[
              const Text('Mirror'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final v in caps.mirror)
                    ChoiceChip(
                      label: Text(_mirrorLabel(v)),
                      selected: v == effMirror,
                      onSelected: (_) => controller.setMirror(active.id, v),
                    ),
                ],
              ),
            ],
            if (caps.hasAdjustments || online.length > 1) const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cast_outlined),
              title: const Text('Manage players'),
              subtitle: const Text('Register, rename or remove devices'),
              onTap: () {
                final nav = Navigator.of(context);
                nav.pop(); // dismiss the sheet
                nav.push(MaterialPageRoute(builder: (_) => const MyPlayersPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  int? _divisions(BrightnessSpec spec) {
    final step = spec.step <= 0 ? 1 : spec.step;
    final n = ((spec.max - spec.min) / step).round();
    return n > 0 ? n : null;
  }

  String _mirrorLabel(String v) => switch (v) {
        'none' => 'None',
        'h' => 'Horizontal',
        'v' => 'Vertical',
        'both' => 'Both',
        _ => v,
      };
}
