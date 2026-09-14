// The Frames page's action bar (ADR 0031): a fixed-height row at the bottom that enables only
// with a non-empty selection. Delete confirms by a second tap (the shared arm also serves the
// keyboard), the Shift pair (‹ › under one "Shift" label) hold-to-repeats and disables at the
// edges, More opens the sheet with everything else (batch Set duration included). Fixed height
// so the grid never reflows.

import 'dart:async';

import 'package:flutter/material.dart';

import '../tap_again.dart';

const double kFramesActionBarHeight = 56;
const Color _kBarBg = Color(0xFF1A1C1F);

/// Slot widths as flex shares: Delete gets more room than the icon items (its "Tap again"
/// label is the widest thing on the bar; 2026-09-14, after the Pixel pass), the Shift pair two
/// items' worth.
const int _kDeleteFlex = 5;
const int _kItemFlex = 3;

/// The icon box every bar item shares, so the labels under them sit on one line.
const double _kIconBox = 22;

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
              flex: _kDeleteFlex,
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
            _ShiftGroup(
              scale: scale,
              enabled: any,
              canLeft: any && canNudgeLeft,
              canRight: any && canNudgeRight,
              onNudge: onNudge,
            ),
            _BarButton(icon: Icons.more_horiz, label: 'More', onPressed: any ? onMore : null, scale: scale),
          ]),
        ),
      ),
    );
  }
}

TextStyle _labelStyle(double scale, Color color) => TextStyle(fontSize: 10 * scale, color: color);

/// The icon-over-label column: [icon] is centered in a [_kIconBox]-tall slot (an OverflowBox,
/// so a larger chevron still lines up with the neighbors), the label right under it.
Widget _iconOverLabel({required Widget icon, required Widget label, required double scale}) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: _kIconBox * scale,
          child: OverflowBox(maxHeight: 32 * scale, child: icon), // width stays the parent's (the chevron row fills it)
        ),
        const SizedBox(height: 2),
        label,
      ],
    );

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
      flex: _kItemFlex,
      child: InkWell(
        onTap: onPressed,
        child: _iconOverLabel(
          icon: Icon(icon, size: _kIconBox * scale, color: color),
          label: Text(label, style: _labelStyle(scale, color)),
          scale: scale,
        ),
      ),
    );
  }
}

/// The ‹ › pair with one shared "Shift" label under it. Two invisible full-height hold-to-repeat
/// targets underneath; the two chevrons and the label are painted once, above them, in the
/// same icon-over-label column the neighbors use, so every label in the bar lines up.
class _ShiftGroup extends StatelessWidget {
  const _ShiftGroup({required this.scale, required this.enabled, required this.canLeft, required this.canRight, required this.onNudge});
  final double scale;
  final bool enabled;
  final bool canLeft;
  final bool canRight;
  final void Function(int delta) onNudge;

  @override
  Widget build(BuildContext context) {
    final labelColor = enabled ? Colors.white : Colors.white24;
    Widget chevron(IconData icon, bool on) => Expanded(
          child: Center(child: Icon(icon, size: 30 * scale, color: on ? Colors.white : Colors.white24)),
        );
    return Expanded(
      flex: 2 * _kItemFlex,
      child: Stack(fit: StackFit.expand, children: [
        Row(children: [
          _HoldRepeatTarget(label: 'Shift left', enabled: canLeft, onFire: () => onNudge(-1)),
          _HoldRepeatTarget(label: 'Shift right', enabled: canRight, onFire: () => onNudge(1)),
        ]),
        IgnorePointer(
          child: _iconOverLabel(
            icon: Row(children: [chevron(Icons.chevron_left, canLeft), chevron(Icons.chevron_right, canRight)]),
            label: Text('Shift', style: _labelStyle(scale, labelColor)),
            scale: scale,
          ),
        ),
      ]),
    );
  }
}

/// An invisible hit target: fires once on tap; a long press keeps firing every 90 ms until
/// release. Its face is painted by the parent.
class _HoldRepeatTarget extends StatefulWidget {
  const _HoldRepeatTarget({required this.label, required this.enabled, required this.onFire});
  final String label;
  final bool enabled;
  final VoidCallback onFire;

  @override
  State<_HoldRepeatTarget> createState() => _HoldRepeatTargetState();
}

class _HoldRepeatTargetState extends State<_HoldRepeatTarget> {
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
          enabled: widget.enabled,
          label: widget.label,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
