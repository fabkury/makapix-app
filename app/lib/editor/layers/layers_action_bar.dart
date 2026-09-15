// The Layers page's action bar (ADR 0033): a fixed-height row at the bottom that enables only
// with a non-empty selection. Delete confirms by a second tap (the shared arm also serves the
// keyboard), Merge acts on the selected run, the Shift pair (▲ ▼ under one "Shift" label)
// hold-to-repeats and disables at the edges, More opens the sheet with everything else. Fixed
// height so the list never reflows. Same skeleton as the Frames bar (frames_action_bar.dart),
// with the layer verbs on it.

import 'dart:async';

import 'package:flutter/material.dart';

import '../tap_again.dart';

const double kLayersActionBarHeight = 56;
const Color _kBarBg = Color(0xFF1A1C1F);
const int _kDeleteFlex = 5;
const int _kItemFlex = 3;
const double _kIconBox = 22;

class LayersActionBar extends StatelessWidget {
  const LayersActionBar({
    super.key,
    required this.scale,
    required this.selectedCount,
    required this.canMerge,
    required this.canShiftUp,
    required this.canShiftDown,
    required this.deleteArm,
    required this.armKey,
    required this.onDelete,
    required this.onMerge,
    required this.onShift,
    required this.onMore,
  });

  final double scale;
  final int selectedCount;
  final bool canMerge;
  final bool canShiftUp;
  final bool canShiftDown;
  final TapAgainArm deleteArm;
  final Object armKey;
  final VoidCallback onDelete;
  final VoidCallback onMerge;

  /// +1 = toward the top of the stack, −1 = toward the bottom.
  final void Function(int delta) onShift;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final any = selectedCount > 0;
    return ColoredBox(
      color: _kBarBg,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: kLayersActionBarHeight * scale,
          child: Row(children: [
            Expanded(
              flex: _kDeleteFlex,
              child: Center(
                child: TapAgainDeleteButton(
                  label: 'Delete',
                  armedText: 'Tap again',
                  arm: deleteArm,
                  armKey: armKey,
                  onConfirmed: any ? onDelete : null,
                ),
              ),
            ),
            _BarButton(icon: Icons.call_merge, label: 'Merge', onPressed: canMerge ? onMerge : null, scale: scale),
            _ShiftGroup(scale: scale, enabled: any, canUp: any && canShiftUp, canDown: any && canShiftDown, onShift: onShift),
            _BarButton(icon: Icons.more_horiz, label: 'More', onPressed: any ? onMore : null, scale: scale),
          ]),
        ),
      ),
    );
  }
}

TextStyle _labelStyle(double scale, Color color) => TextStyle(fontSize: 10 * scale, color: color);

Widget _iconOverLabel({required Widget icon, required Widget label, required double scale}) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: _kIconBox * scale, child: OverflowBox(maxHeight: 32 * scale, child: icon)),
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

/// The ▲ ▼ pair with one shared "Shift" label under it, over two invisible hold-to-repeat
/// targets (the Frames bar's construction).
class _ShiftGroup extends StatelessWidget {
  const _ShiftGroup({required this.scale, required this.enabled, required this.canUp, required this.canDown, required this.onShift});
  final double scale;
  final bool enabled;
  final bool canUp;
  final bool canDown;
  final void Function(int delta) onShift;

  @override
  Widget build(BuildContext context) {
    final labelColor = enabled ? Colors.white : Colors.white24;
    Widget chevron(IconData icon, bool on) => Expanded(child: Center(child: Icon(icon, size: 30 * scale, color: on ? Colors.white : Colors.white24)));
    return Expanded(
      flex: 2 * _kItemFlex,
      child: Stack(fit: StackFit.expand, children: [
        Row(children: [
          _HoldRepeatTarget(label: 'Shift up', enabled: canUp, onFire: () => onShift(1)),
          _HoldRepeatTarget(label: 'Shift down', enabled: canDown, onFire: () => onShift(-1)),
        ]),
        IgnorePointer(
          child: _iconOverLabel(
            icon: Row(children: [chevron(Icons.expand_less, canUp), chevron(Icons.expand_more, canDown)]),
            label: Text('Shift', style: _labelStyle(scale, labelColor)),
            scale: scale,
          ),
        ),
      ]),
    );
  }
}

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
        child: Semantics(button: true, enabled: widget.enabled, label: widget.label, child: const SizedBox.expand()),
      ),
    );
  }
}
