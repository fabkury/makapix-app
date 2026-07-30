// Red informational alert: the given size isn't accepted by Makapix Club (the hardcoded
// ClubSizeRules). Shown by dialogs that create or resize publishable art (the Animator's
// New-scene dialog; the editor keeps a private twin for now) — it never blocks creation;
// the creative tools deliberately allow non-publishable sizes.
import 'package:flutter/material.dart';

import 'conformance.dart';

class ClubSizeAlert extends StatelessWidget {
  final int width, height;
  const ClubSizeAlert(this.width, this.height, {super.key});

  @override
  Widget build(BuildContext context) {
    final nearest = ClubSizeRules.nearest(width, height);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Makapix Club doesn\'t accept $width × $height artworks, so it can\'t be posted '
            'to the Club at this size.\nNearest accepted size: ${nearest[0]} × ${nearest[1]}.',
            style: const TextStyle(fontSize: 12, color: Colors.redAccent),
          ),
        ),
      ]),
    );
  }
}
