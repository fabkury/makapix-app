// The EasingChip — the design's "presets, not graphs" stance made concrete: one compact chip
// in the transport row that shows the selected tween's easing and cycles the curated set on
// tap (linear → ease → ease-in → ease-out → hold). Stateless; the page owns the value.
import 'package:flutter/material.dart';

import 'package:makapix_club/animator/model/scene_rules.dart';

class EasingChip extends StatelessWidget {
  /// The current chip value (one of [kEasingCycle]).
  final String value;
  final ValueChanged<String> onChanged;
  const EasingChip({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final i = kEasingCycle.indexOf(value);
    final next = kEasingCycle[(i + 1) % kEasingCycle.length];
    return Tooltip(
      message: 'Easing of the selected tween — tap to cycle',
      child: ActionChip(
        avatar: const Icon(Icons.animation, size: 16),
        label: Text(easingLabel(value), style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        onPressed: () => onChanged(next),
      ),
    );
  }
}
