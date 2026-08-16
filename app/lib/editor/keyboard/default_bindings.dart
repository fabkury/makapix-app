// The default Binding table (DESIGN.md §4, hybrid convention): platform Primary chords for
// system-ish commands, single-letter tool mnemonics designed for Makapix's own tool grid.
// "Primary" resolves to ⌘ on Apple platforms and Ctrl elsewhere at match time (chords.dart).
// As-built amendments to the design draft: X swaps with the PREVIOUS color (the editor has no
// secondary color), and Primary+V switches to the CopyPaste tool before starting the paste draft.
// Arrow keys are deliberately unbound (reserved for a future precision-cursor nudge).
import 'package:flutter/services.dart';

import 'chords.dart';

/// The resolved Binding set the dispatcher matches against: command id → its Chords
/// (most Commands have one; a second entry is an alias, e.g. Redo's Primary+Y).
typedef BindingTable = Map<String, List<Chord>>;

BindingTable defaultBindings() {
  Chord c(LogicalKeyboardKey key) => Chord(key);
  Chord s(LogicalKeyboardKey key) => Chord(key, shift: true);
  Chord p(LogicalKeyboardKey key) => Chord(key, primary: true);
  Chord sp(LogicalKeyboardKey key) => Chord(key, shift: true, primary: true);
  Chord a(LogicalKeyboardKey key) => Chord(key, alt: true);

  return {
    // Draft + playback (Enter/Esc are shared; registry order resolves — commands.dart)
    'draft.commit': [c(LogicalKeyboardKey.enter)],
    'draft.cancel': [c(LogicalKeyboardKey.escape)],
    'playback.toggle': [c(LogicalKeyboardKey.enter)],
    'playback.stop': [c(LogicalKeyboardKey.escape)],
    // Edit
    'edit.undo': [p(LogicalKeyboardKey.keyZ)],
    'edit.redo': [sp(LogicalKeyboardKey.keyZ), p(LogicalKeyboardKey.keyY)],
    'edit.copy': [p(LogicalKeyboardKey.keyC)],
    'edit.paste': [p(LogicalKeyboardKey.keyV)],
    'edit.selectAll': [p(LogicalKeyboardKey.keyA)],
    'edit.deselect': [p(LogicalKeyboardKey.keyD)],
    // Tools
    'tool.pencil': [c(LogicalKeyboardKey.keyP)],
    'tool.brush': [c(LogicalKeyboardKey.keyB)],
    'tool.airbrush': [c(LogicalKeyboardKey.keyA)],
    'tool.eraser': [c(LogicalKeyboardKey.keyE)],
    'tool.fill': [c(LogicalKeyboardKey.keyG)],
    'tool.gradient': [s(LogicalKeyboardKey.keyG)],
    'tool.line': [c(LogicalKeyboardKey.keyL)],
    'tool.shape': [c(LogicalKeyboardKey.keyU)],
    'tool.ruler': [c(LogicalKeyboardKey.keyK)],
    'tool.dodge': [c(LogicalKeyboardKey.keyO)],
    'tool.burn': [s(LogicalKeyboardKey.keyO)],
    'tool.pick': [c(LogicalKeyboardKey.keyI)],
    'tool.move': [c(LogicalKeyboardKey.keyV)],
    'tool.copyPaste': [c(LogicalKeyboardKey.keyC)],
    'tool.select': [c(LogicalKeyboardKey.keyM)],
    'tool.selectColor': [c(LogicalKeyboardKey.keyW)],
    'tool.selectLayer': [s(LogicalKeyboardKey.keyW)],
    'tool.hsv': [c(LogicalKeyboardKey.keyH)],
    'tool.brightness': [s(LogicalKeyboardKey.keyH)],
    'tool.levels': [s(LogicalKeyboardKey.keyL)],
    'tool.flip': [c(LogicalKeyboardKey.keyF)],
    'tool.rotate': [c(LogicalKeyboardKey.keyR)],
    'tool.resize': [s(LogicalKeyboardKey.keyR)],
    'tool.invert': [p(LogicalKeyboardKey.keyI)],
    'tool.play': [s(LogicalKeyboardKey.keyP)],
    'tool.onion': [c(LogicalKeyboardKey.keyN)],
    // Frames
    'frame.prev': [c(LogicalKeyboardKey.comma)],
    'frame.next': [c(LogicalKeyboardKey.period)],
    'frame.add': [s(LogicalKeyboardKey.keyN)],
    'frame.duplicate': [s(LogicalKeyboardKey.keyD)],
    'frame.delete': [p(LogicalKeyboardKey.backspace)],
    // Layers
    'layer.up': [a(LogicalKeyboardKey.bracketRight)],
    'layer.down': [a(LogicalKeyboardKey.bracketLeft)],
    'layer.add': [sp(LogicalKeyboardKey.keyN)],
    // View
    'view.zoomIn': [p(LogicalKeyboardKey.equal)],
    'view.zoomOut': [p(LogicalKeyboardKey.minus)],
    'view.zoomFit': [p(LogicalKeyboardKey.digit0)],
    'view.zoom100': [p(LogicalKeyboardKey.digit1)],
    // Color / brush
    'color.swap': [c(LogicalKeyboardKey.keyX)],
    'brush.sizeUp': [c(LogicalKeyboardKey.bracketRight)],
    'brush.sizeDown': [c(LogicalKeyboardKey.bracketLeft)],
    // File / panels
    'doc.save': [p(LogicalKeyboardKey.keyS)],
    'doc.export': [sp(LogicalKeyboardKey.keyE)],
    'sheet.timeline': [c(LogicalKeyboardKey.keyT)],
    'sheet.layers': [c(LogicalKeyboardKey.keyY)],
    'help.keyboard': [s(LogicalKeyboardKey.slash)], // "?" (Shift+/ folds onto slash)
  };
}
