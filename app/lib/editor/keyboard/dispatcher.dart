// EditorKeyboard: the single key-event dispatcher for the editor (DESIGN.md §2.2). One root
// Focus node — deliberately NOT the Shortcuts widget, which can't express Hold bindings or the
// ordered modality gate — resolves each keystroke to a Chord, then invokes the first *enabled*
// Command bound to it (registry order breaks ties: Enter commits a draft before it toggles play).
// Engine-free by construction: everything goes through the EditorAccess host, so widget tests
// drive it with a fake and tester.sendKeyEvent.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _EditorKeyboardState extends State<EditorKeyboard> {
  final FocusNode _node = FocusNode(debugLabel: 'EditorKeyboard', skipTraversal: true);
  // Chord → the Commands it can fire, in registry order.
  late Map<Chord, List<CommandDef>> _byChord;

  @override
  void initState() {
    super.initState();
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
    _node.dispose();
    super.dispose();
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
    if (event is KeyUpEvent) return KeyEventResult.ignored; // Hold bindings land in stage 2
    if (_textEditingActive()) return KeyEventResult.ignored;
    // A covered editor (dialog, sheet, the ☰ popup, a pushed page) hears nothing; Flutter's
    // own Esc-dismiss closes those routes.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return KeyEventResult.ignored;
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
        child: widget.child,
      ),
    );
  }
}
