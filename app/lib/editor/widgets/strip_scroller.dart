import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Desktop scroll affordances for the editor's tool/film strips (the frame film roll, the
/// layer strip, row-1 tool options, the palette row, the row-3 tool grid, and the sheet
/// mini-stacks). Wrap the strip's scrollable; two behaviors come with it:
///
///  - **Mouse wheel scrolls a horizontal strip.** Flutter drops wheel events whose delta
///    doesn't match the scrollable's axis, so a horizontal strip is wheel-dead on desktop.
///    A pure vertical wheel delta is remapped onto the strip's controller; wheel-down moves
///    toward the end (the browser tab-strip convention). Events with a horizontal component
///    (trackpad sideways swipes) and Shift+wheel (the framework transposes those itself)
///    already reach the scrollable and are left alone — acting on them too would double-scroll.
///  - **Mouse drag scrolls the strip** in either orientation (the mouse is excluded from
///    ScrollBehavior.dragDevices by default). Tile taps keep working — a drag needs slop —
///    and the tool grid's LongPressDraggable still wins its arena (it needs a hold, not a
///    swipe), exactly as with touch.
class StripScroller extends StatelessWidget {
  const StripScroller({super.key, required this.axis, this.controller, required this.child});

  /// The wrapped scrollable's axis. The wheel remap applies only when horizontal; a vertical
  /// strip already handles the wheel natively and only gains mouse drag.
  final Axis axis;

  /// The wrapped scrollable's controller (the wheel remap drives it directly). Null disables
  /// the remap and keeps just the drag affordance.
  final ScrollController? controller;

  final Widget child;

  void _onPointerSignal(PointerSignalEvent e) {
    final c = controller;
    if (c == null || e is! PointerScrollEvent) return;
    if (e.scrollDelta.dx != 0) return; // horizontal component: the scrollable handles it
    if (HardwareKeyboard.instance.isShiftPressed) return; // Shift+wheel: framework transposes
    if (!c.hasClients) return;
    final pos = c.position;
    final target =
        (pos.pixels + e.scrollDelta.dy).clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
    if (target != pos.pixels) pos.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final dragScrollable = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: PointerDeviceKind.values.toSet(),
      ),
      child: child,
    );
    if (axis != Axis.horizontal) return dragScrollable;
    return Listener(onPointerSignal: _onPointerSignal, child: dragScrollable);
  }
}
