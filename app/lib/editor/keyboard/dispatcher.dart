// EditorKeyboard: the single key-event dispatcher for the editor (DESIGN.md §2.2). One root
// Focus node — deliberately NOT the Shortcuts widget, which can't express Hold bindings or the
// ordered modality gate — resolves each keystroke to a Chord, then invokes the first *enabled*
// Command bound to it (registry order breaks ties: Enter commits a draft before it toggles play).
// Engine-free by construction: everything goes through the EditorAccess host, so widget tests
// drive it with a fake and tester.sendKeyEvent.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cheat_sheet.dart';
import 'chords.dart';
import 'commands.dart';
import 'default_bindings.dart';
import 'editor_access.dart';

/// The Hold binding that springs the temporary Eyedropper. Deliberately a BARE LETTER rather
/// than Alt: Alt is an OS chord modifier, so Alt+Tab and every Alt chord transiently sprang the
/// tool [G-43]. S is home row under the left hand while the right hand draws — the same
/// ergonomics that make Space the pan hold — and Primary+S (Save) still reaches the tap table
/// because a modified pick key is not the hold.
const LogicalKeyboardKey kHoldPickKey = LogicalKeyboardKey.keyS;

/// Commands that ABORT an in-flight Gesture instead of finishing it (ADR 0010).
const Set<String> kCancelGestureCommands = {
  'draft.cancel',
  'playback.stop',
  'edit.undo',
  'edit.redo',
};

class EditorKeyboard extends StatefulWidget {
  const EditorKeyboard({
    super.key,
    required this.access,
    required this.commands,
    required this.bindings,
    required this.child,
  });

  final EditorAccess access;
  final List<CommandDef> commands; // registry order = dispatch priority
  final BindingTable bindings;
  final Widget child;

  @override
  State<EditorKeyboard> createState() => _EditorKeyboardState();
}

class _EditorKeyboardState extends State<EditorKeyboard> with WidgetsBindingObserver {
  final FocusNode _node = FocusNode(debugLabel: 'EditorKeyboard', skipTraversal: true);
  // Chord → the Commands it can fire, in registry order.
  late Map<Chord, List<CommandDef>> _byChord;
  // Hold-binding state (Space-pan / Alt-eyedrop). Begin/end must pair exactly: a keyUp the
  // editor never sees (dialog opened, app backgrounded, focus lost) is force-released, so a
  // held mode can never survive its key (DESIGN.md §2.3 "stuck-state recovery").
  bool _spaceHeld = false;
  bool _pickHeld = false;
  bool _constrainHeld = false;
  // Hold-Primary cheat-sheet overlay (DESIGN.md §2.5): the Primary modifier held alone for
  // [_kOverlayDelay] shows the sheet; any other key, or release, hides it.
  static const _kOverlayDelay = Duration(milliseconds: 600);
  Timer? _overlayTimer;
  bool _overlayVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rebuildTable();
  }

  @override
  void didUpdateWidget(EditorKeyboard old) {
    super.didUpdateWidget(old);
    if (old.commands != widget.commands || old.bindings != widget.bindings) _rebuildTable();
  }

  void _rebuildTable() {
    final table = <Chord, List<CommandDef>>{};
    for (final cmd in widget.commands) {
      for (final chord in widget.bindings[cmd.id] ?? const <Chord>[]) {
        (table[chord] ??= []).add(cmd);
      }
    }
    _byChord = table;
  }

  @override
  void dispose() {
    releaseAllHolds();
    WidgetsBinding.instance.removeObserver(this);
    _node.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding swallows keyUps; a hold must never survive it.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      releaseAllHolds();
    }
  }

  /// Force-release every active hold (lifecycle, focus loss, teardown).
  void releaseAllHolds() {
    if (_spaceHeld) {
      _spaceHeld = false;
      widget.access.setSpacePan(false);
    }
    if (_pickHeld) {
      _pickHeld = false;
      widget.access.endHoldPick();
    }
    if (_constrainHeld) {
      _constrainHeld = false;
      widget.access.setConstrain(false);
    }
    _hideOverlay();
  }

  void _hideOverlay() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
    if (_overlayVisible && mounted) setState(() => _overlayVisible = false);
  }

  static bool _anyModifierDown() =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// Re-derive the hold states from the physical keyboard when focus comes back with a key
  /// still down — otherwise each hold recovered differently, or not at all [G-44]. Space is not
  /// readable this way; its KeyRepeat re-arms it instead.
  void _rederiveHolds() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final shift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    if (shift != _constrainHeld) {
      _constrainHeld = shift;
      widget.access.setConstrain(shift);
    }
    final pick = pressed.contains(kHoldPickKey) && !_anyModifierDown();
    if (pick && !_pickHeld && !widget.access.hasAnyDraft && !widget.access.interactionActive) {
      _pickHeld = true;
      widget.access.beginHoldPick();
    }
  }

  bool _isPrimaryModifierKey(LogicalKeyboardKey k) => primaryIsMeta()
      ? k == LogicalKeyboardKey.metaLeft || k == LogicalKeyboardKey.metaRight
      : k == LogicalKeyboardKey.controlLeft || k == LogicalKeyboardKey.controlRight;

  // The overlay arm/disarm machine. Never consumes anything — Primary keeps being a modifier.
  void _trackOverlay(KeyEvent event, {required bool gated}) {
    if (_isPrimaryModifierKey(event.logicalKey)) {
      // Never over an in-progress Gesture — the reference card is not what the artist is
      // asking for while a stroke is live [G-12].
      if (event is KeyDownEvent && !gated && !widget.access.interactionActive) {
        _overlayTimer ??= Timer(_kOverlayDelay, () {
          if (mounted) setState(() => _overlayVisible = true);
        });
      } else if (event is KeyUpEvent) {
        _hideOverlay();
      }
      return; // repeats of the held modifier keep the overlay up
    }
    if (event is KeyDownEvent) _hideOverlay(); // a chord was meant, not the reference card
  }

  // Shift is both a chord modifier AND the constrain hold, so it is tracked level-triggered
  // and NEVER consumed — shifted chords and text-field capitals keep working. Ungated: no
  // drag can be live while a text field or covered route has the keyboard, so mirroring the
  // physical key is harmless there and correct everywhere else.
  void _trackConstrain(KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.shiftLeft && key != LogicalKeyboardKey.shiftRight) return;
    final held = event is! KeyUpEvent;
    if (held != _constrainHeld) {
      _constrainHeld = held;
      widget.access.setConstrain(held);
    }
  }

  // The Hold-binding state machine. Runs before the tap table; returns null when the event is
  // not a hold key. KeyUps release even when the gates have changed since the press.
  KeyEventResult? _handleHolds(KeyEvent event, {required bool gated}) {
    final key = event.logicalKey;
    final isPick = key == kHoldPickKey;
    final isSpace = key == LogicalKeyboardKey.space;
    if (!isPick && !isSpace) return null;
    // A MODIFIED pick key is not the hold — it is a chord (Primary+S is Save), so hand it to
    // the tap table. Mirrors the bare-modifier check Space has always had. Moving off Alt is
    // what removes the Alt+Tab / Alt-chord spring entirely rather than papering it [G-43].
    if (isPick && event is! KeyUpEvent && _anyModifierDown()) return null;
    if (event is KeyUpEvent) {
      if (isSpace && _spaceHeld) {
        _spaceHeld = false;
        widget.access.setSpacePan(false);
        return KeyEventResult.handled;
      }
      if (isPick && _pickHeld) {
        _pickHeld = false;
        widget.access.endHoldPick();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (gated) return KeyEventResult.ignored; // text field / covered route: keys pass through
    if (event is KeyRepeatEvent) {
      // A held hold-key auto-repeats; the hold is level-triggered, so swallow the chatter.
      return (isSpace && _spaceHeld) || (isPick && _pickHeld)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (isSpace) {
      if (_anyModifierDown()) {
        return KeyEventResult.ignored; // modified Space is not the pan hold
      }
      if (!_spaceHeld) {
        _spaceHeld = true;
        widget.access.setSpacePan(true);
      }
      return KeyEventResult.handled;
    }
    // Pick key down: spring the temporary Eyedropper — but never mid-draft (the tool switch
    // would cancel the draft) and never mid-Gesture (the stroke would change meaning under the
    // finger; the predicate now covers the pen too, so a precision line survives [G-43]).
    if (!_pickHeld && !widget.access.hasAnyDraft && !widget.access.interactionActive) {
      _pickHeld = true;
      widget.access.beginHoldPick();
    }
    return KeyEventResult.handled;
  }

  // A TextField (or any editable) owns the keyboard while focused: every Chord passes through.
  // Belt-and-braces — an editable inside a dialog route isn't in this node's focus chain anyway.
  bool _textEditingActive() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    // The focused node attaches inside EditableText's own Focus wrapper, so check the
    // ancestor chain, not just the attach context's widget.
    return ctx.widget is EditableText || ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // Gate: a focused editable, or a covered editor (dialog, sheet, the ☰ popup, a pushed
    // page), hears nothing; Flutter's own Esc-dismiss closes those routes.
    _trackConstrain(event);
    final gated =
        _textEditingActive() || !(ModalRoute.of(context)?.isCurrent ?? true);
    _trackOverlay(event, gated: gated);
    final hold = _handleHolds(event, gated: gated);
    if (hold != null) return hold;
    if (event is KeyUpEvent) return KeyEventResult.ignored; // taps fire on the way down
    if (gated) return KeyEventResult.ignored;
    final chord = Chord.fromEvent(event);
    if (chord == null) return KeyEventResult.ignored;
    final candidates = _byChord[chord];
    if (candidates == null) return KeyEventResult.ignored;
    // ADR 0010. Mid-Gesture, Esc and Undo/Redo abort the Gesture and stop there — one keystroke
    // undoes one thing, and mid-stroke the thing you mean is the stroke [G-05]. This runs BEFORE
    // the enabled filter on purpose: "abort this gesture" is meaningful even when nothing is
    // drafted, nothing is playing, and there is nothing to undo.
    if (widget.access.interactionActive &&
        candidates.any((c) => kCancelGestureCommands.contains(c.id))) {
      widget.access.cancelInteraction();
      return KeyEventResult.handled;
    }
    for (final cmd in candidates) {
      if (!cmd.enabled(widget.access)) continue;
      // Every other Command finishes the Gesture first, then runs [G-02, G-04, G-06].
      if (widget.access.interactionActive) widget.access.finishInteraction();
      // A bound Chord is consumed even when the key repeat is unwanted, so held keys
      // never leak (e.g. a held P must not type into anything beneath).
      if (event is! KeyRepeatEvent || cmd.repeats) cmd.invoke(widget.access);
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled; // bound but nothing enabled: swallow, never fall through
  }

  // Keep the dispatcher armed: focus normally returns after a route pops, but if it lands on
  // the bare scope instead, the next tap anywhere in the editor re-arms the keyboard.
  void _rearmOnTap(PointerDownEvent _) {
    if (_node.hasFocus) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (_textEditingActive()) return;
    _node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _rearmOnTap,
      child: Focus(
        focusNode: _node,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        // Losing focus (a dialog/sheet took over) means keyUps stop arriving — force-release.
        onFocusChange: (has) {
          if (!has) {
            releaseAllHolds();
          } else {
            _rederiveHolds(); // a key may still be down from before the route took focus [G-44]
          }
        },
        child: Stack(fit: StackFit.passthrough, children: [
          widget.child,
          if (_overlayVisible)
            Positioned.fill(
              child: KeyboardOverlay(commands: widget.commands, bindings: widget.bindings),
            ),
        ]),
      ),
    );
  }
}
