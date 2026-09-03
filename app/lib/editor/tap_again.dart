// Second-tap confirmation for destructive controls (ADR 0022). A fingertip on "Delete frame" or
// "Delete layer" must not cost work: the first tap only ARMS the control for a short window and
// relabels it "Tap again to confirm"; a second tap inside the window fires; the window's expiry,
// a retarget (a different [TapAgainArm.tap] key), or an explicit [TapAgainArm.disarm] resets it
// silently. Pure Dart over dart:async — no engine, no dialog, no extra tap on the happy path.

import 'dart:async';

import 'package:flutter/material.dart';

/// How long an armed control waits for its confirming second tap.
const Duration kTapAgainWindow = Duration(seconds: 3);

/// The arming state machine, shared by the sheet button and the keyboard "Delete frame" command.
class TapAgainArm {
  TapAgainArm({this.window = kTapAgainWindow, this.onChanged});

  final Duration window;

  /// Fired after every state change — arm, confirm, disarm, and the window's expiry — so a widget
  /// can rebuild and a host can drop a hint.
  final VoidCallback? onChanged;

  Timer? _timer;
  Object? _key;

  bool get armed => _timer != null;

  /// The key the control is currently armed for (`null` when not armed).
  Object? get armedKey => _key;

  /// One tap. Returns `true` when this tap CONFIRMS — a second tap within [window] with the same
  /// [key] — and the caller should act now. Otherwise the control is (re)armed for [key] and
  /// `false` comes back; a tap with a different key while armed re-arms for the new key.
  bool tap([Object? key]) {
    if (armed && _key == key) {
      disarm();
      return true;
    }
    _timer?.cancel();
    _key = key;
    _timer = Timer(window, () {
      _timer = null;
      _key = null;
      onChanged?.call();
    });
    onChanged?.call();
    return false;
  }

  /// Reset without firing. No-op when not armed (so callers can disarm on every rebuild cheaply).
  void disarm() {
    if (!armed) return;
    _timer?.cancel();
    _timer = null;
    _key = null;
    onChanged?.call();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _key = null;
  }
}

/// The destructive button at the bottom of the frame and layer sheets. Resting: a red-text
/// `TextButton`. Armed: a filled red button reading [armedLabel]. [armKey] identifies WHAT the
/// button acts on (the frame or layer index, plus the host's engine-traffic stamp); when it
/// changes between builds the button disarms, so a confirm can never land on a target the user
/// did not arm. A `null` [onConfirmed] disables the button and clears any armed state.
class TapAgainDeleteButton extends StatefulWidget {
  const TapAgainDeleteButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.armKey,
    this.window = kTapAgainWindow,
    this.icon = Icons.delete_outline,
  });

  final String label;
  final VoidCallback? onConfirmed;
  final Object? armKey;
  final Duration window;
  final IconData icon;

  static const String armedLabel = 'Tap again to confirm';

  @override
  State<TapAgainDeleteButton> createState() => _TapAgainDeleteButtonState();
}

class _TapAgainDeleteButtonState extends State<TapAgainDeleteButton> {
  late final TapAgainArm _arm = TapAgainArm(
    window: widget.window,
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void didUpdateWidget(covariant TapAgainDeleteButton old) {
    super.didUpdateWidget(old);
    if (old.armKey != widget.armKey || widget.onConfirmed == null) _arm.disarm();
  }

  @override
  void dispose() {
    _arm.dispose();
    super.dispose();
  }

  void _tap() {
    if (_arm.tap(widget.armKey)) widget.onConfirmed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onConfirmed != null;
    final icon = Icon(widget.icon, size: 18);
    if (_arm.armed && enabled) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
        onPressed: _tap,
        icon: icon,
        label: const Text(TapAgainDeleteButton.armedLabel),
      );
    }
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
      onPressed: enabled ? _tap : null,
      icon: icon,
      label: Text(widget.label),
    );
  }
}
