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

  bool _isPrimaryModifierKey(LogicalKeyboardKey k) => primaryIsMeta()
      ? k == LogicalKeyboardKey.metaLeft || k == LogicalKeyboardKey.metaRight
      : k == LogicalKeyboardKey.controlLeft || k == LogicalKeyboardKey.controlRight;

  // The overlay arm/disarm machine. Never consumes anything — Primary keeps being a modifier.
  void _trackOverlay(KeyEvent event, {required bool gated}) {
    if (_isPrimaryModifierKey(event.logicalKey)) {
      if (event is KeyDownEvent && !gated) {
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
    final isAlt = key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight;
    final isSpace = key == LogicalKeyboardKey.space;
    if (!isAlt && !isSpace) return null;
    if (event is KeyUpEvent) {
      if (isSpace && _spaceHeld) {
        _spaceHeld = false;
        widget.access.setSpacePan(false);
        return KeyEventResult.handled;
      }
      if (isAlt && _pickHeld) {
        _pickHeld = false;
        widget.access.endHoldPick();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (gated) return KeyEventResult.ignored; // text field / covered route: keys pass through
    if (event is KeyRepeatEvent) {
      // A held hold-key auto-repeats; the hold is level-triggered, so swallow the chatter.
      return (isSpace && _spaceHeld) || (isAlt && _pickHeld)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (isSpace) {
      if (HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.isAltPressed ||
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        return KeyEventResult.ignored; // modified Space is not the pan hold
      }
      if (!_spaceHeld) {
        _spaceHeld = true;
        widget.access.setSpacePan(true);
      }
      return KeyEventResult.handled;
    }
    // Alt down: spring the temporary Eyedropper — but never mid-draft (the tool switch would
    // cancel the draft) and never mid-drag (the stroke would change meaning under the finger).
    if (!_pickHeld && !widget.access.hasAnyDraft && !widget.access.pointerActive) {
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
    for (final cmd in candidates) {
      if (!cmd.enabled(widget.access)) continue;
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
          if (!has) releaseAllHolds();
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
