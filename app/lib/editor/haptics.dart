// Haptic cues shared by the drag-reorder surfaces (row-3 tool grid, palette list).

import 'package:flutter/services.dart';

/// The drop-commit cue: two sharp ticks in quick succession. selectionClick is the one
/// haptic that demonstrably fires wherever the per-reflow ticks do — Android gates the
/// impact effects (lightImpact → VIRTUAL_KEY et al.) behind device settings on some
/// phones — and doubling it keeps the commit distinguishable from a single reflow tick.
void hapticDropConfirm() {
  HapticFeedback.selectionClick();
  Future<void>.delayed(const Duration(milliseconds: 70), HapticFeedback.selectionClick);
}
