// The Frames page's action bar (ADR 0031): a fixed-height row at the bottom that enables only
// with a non-empty selection. Delete confirms by a second tap (the shared arm also serves the
// keyboard), the nudge buttons hold-to-repeat and disable at the edges, More opens the sheet
// with everything else. Fixed height so the grid never reflows.

import 'dart:async';

import 'package:flutter/material.dart';

import '../tap_again.dart';

const double kFramesActionBarHeight = 56;
const Color _kBarBg = Color(0xFF1A1C1F);

class FramesActionBar extends StatelessWidget {
  const FramesActionBar({
    super.key,
    required this.scale,
    required this.selectedCount,
    required this.canDelete,
    required this.canNudgeLeft,
    required this.canNudgeRight,
    required this.deleteArm,
    required this.armKey,
    required this.onDelete,
    required this.onDuplicate,
    required this.onDuration,
    required this.onNudge,
    required this.onMore,
  });

  final double scale;
  final int selectedCount;
  final bool canDelete;
  final bool canNudgeLeft;
  final bool canNudgeRight;
  final TapAgainArm deleteArm;
  final Object armKey;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onDuration;
  final void Function(int delta) onNudge;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final any = selectedCount > 0;
    return ColoredBox(
      color: _kBarBg,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: kFramesActionBarHeight * scale,
          child: Row(children: [
            Expanded(
              child: Center(
                child: TapAgainDeleteButton(
                  label: 'Delete',
                  armedText: 'Tap again',
                  arm: deleteArm,
                  armKey: armKey,
                  onConfirmed: canDelete ? onDelete : null,
                ),
              ),
            ),
            _BarButton(icon: Icons.control_point_duplicate, label: 'Duplicate', onPressed: any ? onDuplicate : null, scale: scale),
            _BarButton(icon: Icons.timer_outlined, label: 'Duration', onPressed: any ? onDuration : null, scale: scale),
            _HoldRepeatButton(icon: Icons.chevron_left, tooltip: 'Shift left', enabled: any && canNudgeLeft, onFire: () => onNudge(-1), scale: scale),
            _HoldRepeatButton(icon: Icons.chevron_right, tooltip: 'Shift right', enabled: any && canNudgeRight, onFire: () => onNudge(1), scale: scale),
            _BarButton(icon: Icons.more_horiz, label: 'More', onPressed: any ? onMore : null, scale: scale),
          ]),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, required this.onPressed, required this.scale});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null ? Colors.white24 : Colors.white;
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22 * scale, color: color),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10 * scale, color: color)),
        ]),
      ),
    );
  }
}

/// Fires once on tap; a long press keeps firing every 90 ms until release.
class _HoldRepeatButton extends StatefulWidget {
  const _HoldRepeatButton({required this.icon, required this.tooltip, required this.enabled, required this.onFire, required this.scale});
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onFire;
  final double scale;

  @override
  State<_HoldRepeatButton> createState() => _HoldRepeatButtonState();
}

class _HoldRepeatButtonState extends State<_HoldRepeatButton> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled ? Colors.white : Colors.white24;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onFire : null,
        onLongPressStart: widget.enabled
            ? (_) {
                widget.onFire();
                _timer = Timer.periodic(const Duration(milliseconds: 90), (_) {
                  if (widget.enabled) {
                    widget.onFire();
                  } else {
                    _stop();
                  }
                });
              }
            : null,
        onLongPressEnd: (_) => _stop(),
        onLongPressCancel: _stop,
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: Center(child: Icon(widget.icon, size: 28 * widget.scale, color: color)),
        ),
      ),
    );
  }
}
