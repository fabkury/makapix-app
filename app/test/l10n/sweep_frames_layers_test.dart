// T4 sweeps: the Frames page and the Layers page, with their menus, sheets, and dialogs —
// batch E4. Both pages run on the scripted hosts of the page tests: no engine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/frames/frame_model.dart';
import 'package:makapix_club/editor/frames/frames_page.dart';
import 'package:makapix_club/editor/layers/layer_model.dart';
import 'package:makapix_club/editor/layers/layers_page.dart';

import '../frames_test_support.dart';
import '../layers_test_support.dart';
import 'sweep.dart';

/// A layer name an artist typed: shown as typed in every language.
const _typed = 'Shading';

/// Twelve frames on a canvas that is not square (the More sheet's rotate note shows), heavy
/// enough that the undo warning shows too. Two layers: one with the engine's own name, one
/// with a name the artist typed.
Widget _frames() {
  final host = FakeFramesHost(
    [
      for (var i = 0; i < 12; i++)
        FrameInfo(id: 100 + i, layers: const [
          LayerInfo(name: 'Layer 1', presentTiles: 9000),
          LayerInfo(name: _typed, presentTiles: 1),
        ]),
    ],
    canvas: (w: 32, h: 48),
  );
  return FramesPage(host: host, columns: 4);
}

/// Six layers covering every tag a row can carry: the engine's names (translated on screen), a
/// copy, an unnamed one, a typed name; hidden, locked, translucent, blended, empty.
Widget _layers({int frames = 3}) {
  final host = FakeLayersHost(
    const [
      LayerRow(id: 500, name: 'Layer 1', presentTiles: 9000),
      LayerRow(id: 501, name: 'Layer 2', presentTiles: 9000, locked: true),
      LayerRow(id: 502, name: 'Layer 2 copy', presentTiles: 1, visible: false),
      LayerRow(id: 503, name: '', presentTiles: 1, opacity: 128),
      LayerRow(id: 504, name: _typed, presentTiles: 1, blend: 'HardLight'),
      LayerRow(id: 505, name: 'Layer 6'),
    ],
    active: 1,
    frames: frames,
    canvas: (w: 32, h: 48),
  );
  return LayersPage(host: host);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).first);
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _tapIcon(WidgetTester tester, IconData icon) async {
  final f = find.byIcon(icon).last;
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(f);
  await settleOpen(tester);
}

Future<void> _openSelectMenu(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await settleOpen(tester);
}

/// Selects frames 2 and 4 (the tiles carry their numbers).
Future<void> _selectFrames(WidgetTester tester) async {
  await _tapText(tester, '2');
  await _tapText(tester, '4');
}

Future<void> _framesMore(WidgetTester tester) async {
  await _selectFrames(tester);
  await _tapIcon(tester, Icons.more_horiz);
}

/// Selects the bottom three layers, the locked one among them (rows carry their numbers).
Future<void> _selectLayers(WidgetTester tester) async {
  await _tapText(tester, '1');
  await _tapText(tester, '2');
  await _tapText(tester, '3');
}

Future<void> _layersMore(WidgetTester tester) async {
  await _selectLayers(tester);
  await _tapIcon(tester, Icons.more_horiz);
}

void main() {
  const fixture = [_typed];

  // ---- Frames page ----
  sweepScreen('Frames page', build: _frames);
  sweepScreen('Frames page, two selected', build: _frames, act: _selectFrames);
  sweepScreen('Frames page, select menu', build: _frames, act: _openSelectMenu);
  sweepScreen('Frames page, tile menu', build: _frames, act: (tester) async {
    await tester.longPress(find.text('3').first);
    await settleOpen(tester);
  });
  sweepScreen('Frames page, More sheet', build: _frames, act: _framesMore);
  sweepScreen('Frames page, More sheet, end', build: _frames, act: (tester) async {
    await _framesMore(tester);
    await tester.ensureVisible(find.byIcon(Icons.lock_open).last);
  });
  sweepScreen('Frames page, range dialog with an error', build: _frames, act: (tester) async {
    await _openSelectMenu(tester);
    await tester.tap(find.byType(PopupMenuItem<String>).at(3));
    await settleOpen(tester);
    await tester.enterText(find.byType(TextField), '2-99');
  });
  sweepScreen('Frames page, Every Nth dialog', build: _frames, act: (tester) async {
    await _openSelectMenu(tester);
    await tester.tap(find.byType(PopupMenuItem<String>).at(4));
  });
  sweepScreen('Frames page, shift dialog', build: _frames, act: (tester) async {
    await _framesMore(tester);
    await _tapIcon(tester, Icons.moving);
    await tester.enterText(find.byType(TextField), '99');
  });
  sweepScreen('Frames page, duration dialog', build: _frames, act: (tester) async {
    await _framesMore(tester);
    await _tapIcon(tester, Icons.timer_outlined);
  });
  sweepScreen('Frames page, scale dialog with an error', build: _frames, act: (tester) async {
    await _framesMore(tester);
    await _tapText(tester, '× …');
    await settleOpen(tester);
    await tester.enterText(find.byType(TextField), '50');
  });
  sweepScreen('Frames page, layer name picker', build: _frames, allowLatin: fixture, act: (tester) async {
    await _framesMore(tester);
    await _tapIcon(tester, Icons.layers_clear);
  });

  // ---- Layers page ----
  sweepScreen('Layers page', build: _layers, allowLatin: fixture);
  sweepScreen('Layers page, locked layers refuse a merge', build: _layers, allowLatin: fixture, act: (tester) async {
    await _selectLayers(tester);
    await _tapIcon(tester, Icons.call_merge);
  });
  sweepScreen('Layers page, select menu', build: _layers, allowLatin: fixture, act: _openSelectMenu);
  sweepScreen('Layers page, row menu', build: _layers, allowLatin: fixture, act: (tester) async {
    await tester.longPress(find.text('3').first);
    await settleOpen(tester);
  });
  sweepScreen('Layers page, More sheet', build: _layers, allowLatin: fixture, act: _layersMore);
  sweepScreen('Layers page, More sheet, end', build: () => _layers(frames: 1), allowLatin: fixture, act: (tester) async {
    await _layersMore(tester);
    await tester.ensureVisible(find.byIcon(Icons.open_with).last);
  });
  sweepScreen('Layers page, select-by sheet', build: _layers, allowLatin: fixture, act: (tester) async {
    await _openSelectMenu(tester);
    await tester.tap(find.byType(PopupMenuItem<String>).at(4));
  });
  sweepScreen('Layers page, range dialog with an error', build: _layers, allowLatin: fixture, act: (tester) async {
    await _openSelectMenu(tester);
    await tester.tap(find.byType(PopupMenuItem<String>).at(3));
    await settleOpen(tester);
    await tester.enterText(find.byType(TextField), '2-99');
  });
  sweepScreen('Layers page, opacity dialog', build: _layers, allowLatin: fixture, act: (tester) async {
    await _layersMore(tester);
    await _tapIcon(tester, Icons.opacity);
  });
  sweepScreen('Layers page, blend list', build: _layers, allowLatin: fixture, act: (tester) async {
    await _layersMore(tester);
    await _tapIcon(tester, Icons.gradient);
  });
  sweepScreen('Layers page, rename dialog', build: _layers, allowLatin: fixture, act: (tester) async {
    await _layersMore(tester);
    await _tapIcon(tester, Icons.drive_file_rename_outline);
  });
  sweepScreen('Layers page, copy to frames dialog with an error', build: _layers, allowLatin: fixture, act: (tester) async {
    await _layersMore(tester);
    await _tapIcon(tester, Icons.dynamic_feed);
    await tester.enterText(find.byType(TextField), '0');
  });
}
