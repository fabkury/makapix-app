// Registry integrity for the keyboard Command catalog (DESIGN.md §3-4): ids are a persistent
// contract, so this suite is the tripwire for accidental renames, chord collisions, and tools
// added without a Command. Engine-free by construction.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/keyboard/chords.dart';
import 'package:makapix_club/editor/keyboard/commands.dart';
import 'package:makapix_club/editor/keyboard/default_bindings.dart';
import 'package:makapix_club/editor/tools.dart';

import 'keyboard_test_support.dart';

void main() {
  final commands = buildCommands();
  final byId = {for (final c in commands) c.id: c};
  final defaults = defaultBindings();

  test('command ids are unique', () {
    expect(byId.length, commands.length);
  });

  test('every tool in the catalog has a Command, and vice versa', () {
    for (final t in tools) {
      expect(toolCommandIds.containsKey(t.dsl), isTrue,
          reason: 'tool ${t.dsl} has no command id — a new tool must declare its Command');
      expect(byId.containsKey(toolCommandIds[t.dsl]), isTrue);
    }
    // No tool.* command points at a tool that no longer exists.
    final dslSet = tools.map((t) => t.dsl).toSet();
    for (final dsl in toolCommandIds.keys) {
      expect(dslSet.contains(dsl), isTrue, reason: '$dsl vanished from tools.dart');
    }
  });

  test('every Command has a default Binding and every Binding a Command', () {
    for (final c in commands) {
      expect(defaults[c.id], isNotNull, reason: '${c.id} has no default chord');
      expect(defaults[c.id], isNotEmpty);
    }
    for (final id in defaults.keys) {
      expect(byId.containsKey(id), isTrue, reason: 'binding for unknown command $id');
    }
  });

  test('default chords collide only where the design shares them', () {
    // Enter is shared by draft.commit/playback.toggle, Esc by draft.cancel/playback.stop —
    // the dispatcher resolves those by registry order. Everything else must be unique.
    const allowed = [
      {'draft.commit', 'playback.toggle'},
      {'draft.cancel', 'playback.stop'},
    ];
    final users = <Chord, Set<String>>{};
    defaults.forEach((id, chords) {
      for (final ch in chords) {
        (users[ch] ??= {}).add(id);
      }
    });
    users.forEach((chord, ids) {
      if (ids.length > 1) {
        expect(allowed.any((set) => ids.difference(set).isEmpty), isTrue,
            reason: 'chord ${chord.serialize()} bound by $ids');
      }
    });
  });

  test('labels and categories are presentable', () {
    const categories = {
      'Tools', 'Edit', 'Draft', 'Frames', 'Layers', 'View', 'Playback', 'Color', 'File', 'Panels',
    };
    for (final c in commands) {
      expect(c.label.trim(), isNotEmpty, reason: c.id);
      expect(categories.contains(c.category), isTrue, reason: '${c.id} → ${c.category}');
    }
  });

  test('auto-repeat is granted only to stepping commands', () {
    final repeating = commands.where((c) => c.repeats).map((c) => c.id).toSet();
    expect(repeating, {
      'edit.undo', 'edit.redo',
      'frame.prev', 'frame.next',
      'view.zoomIn', 'view.zoomOut',
      'brush.sizeUp', 'brush.sizeDown',
    });
  });

  test('the core four exist (rebindable-but-never-unbindable in 6.B)', () {
    for (final id in coreCommandIds) {
      expect(byId.containsKey(id), isTrue, reason: id);
      expect(defaults[id], isNotEmpty, reason: id);
    }
  });

  test('all default chords survive a serialize/parse round-trip', () {
    for (final entry in defaults.entries) {
      for (final ch in entry.value) {
        expect(Chord.parse(ch.serialize()), ch, reason: '${entry.key}: ${ch.serialize()}');
      }
    }
  });

  test('modality predicates: Enter/Esc pairs split on draft state', () {
    final a = FakeEditorAccess()..frameCountV = 4;
    a.hasAnyDraftV = true;
    expect(byId['draft.commit']!.enabled(a), isTrue);
    expect(byId['playback.toggle']!.enabled(a), isFalse);
    a.hasAnyDraftV = false;
    expect(byId['draft.commit']!.enabled(a), isFalse);
    expect(byId['playback.toggle']!.enabled(a), isTrue);
    a.isPlayingV = true;
    expect(byId['playback.stop']!.enabled(a), isTrue);
  });

  test('invocations route to the host, not to DSL', () {
    final a = FakeEditorAccess()
      ..canUndoV = true
      ..layerCountV = 3
      ..activeLayerV = 1;
    byId['edit.undo']!.invoke(a);
    byId['tool.pencil']!.invoke(a);
    byId['tool.onion']!.invoke(a);
    byId['layer.up']!.invoke(a);
    byId['frame.next']!.invoke(a);
    byId['color.swap']!.invoke(a);
    expect(a.calls, [
      'undo',
      'selectTool:Pencil',
      'toggleOnion',
      'moveLayer:1',
      'stepFrame:1',
      'swapWithPreviousColor',
    ]);
  });

  test('layer bounds gate layer.up/down', () {
    final a = FakeEditorAccess()
      ..layerCountV = 2
      ..activeLayerV = 1;
    expect(byId['layer.up']!.enabled(a), isFalse); // already topmost
    expect(byId['layer.down']!.enabled(a), isTrue);
    a.activeLayerV = 0;
    expect(byId['layer.up']!.enabled(a), isTrue);
    expect(byId['layer.down']!.enabled(a), isFalse);
  });
}
