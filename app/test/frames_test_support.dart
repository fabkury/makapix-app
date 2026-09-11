// Test support for the Frames page (ADR 0031): a scripted FramesHost and a pump helper that
// pushes the page over a base route so its pops are real. No engine.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/frames/frame_model.dart';
import 'package:makapix_club/editor/frames/frames_host.dart';
import 'package:makapix_club/editor/frames/frames_page.dart';

class FakeFramesHost implements FramesHost {
  FakeFramesHost(this.frames, {this.active = 0, this.canvas = (w: 32, h: 32)});

  @override
  List<FrameInfo> frames;
  int active;
  ({int w, int h}) canvas;
  bool canUndoV = false;
  bool canRedoV = false;
  int seq = 0;

  final List<String> scripts = [];

  /// The refusal to return from the next [run] (consumed once).
  String? refusal;

  /// Mutates [frames] to model the engine's effect; returns a refusal or null.
  String? Function(String dsl)? onRun;

  int thumbRequests = 0;
  int hashCalls = 0;
  final Map<int, int> hashes = {};
  final List<int> sheetsOpened = [];
  int undos = 0;
  int redos = 0;

  @override
  int get activeFrameIndex => active;

  @override
  int get frameCount => frames.length;

  @override
  ({int w, int h}) get canvasSize => canvas;

  @override
  bool get canUndo => canUndoV;

  @override
  bool get canRedo => canRedoV;

  @override
  int get sendSeq => seq;

  @override
  String? run(String dsl) {
    scripts.add(dsl);
    seq++;
    final r = refusal;
    refusal = null;
    if (r != null) return r;
    return onRun?.call(dsl);
  }

  @override
  void undo() => undos++;

  @override
  void redo() => redos++;

  @override
  Uint8List thumbBytes(int index, int tw, int th) {
    thumbRequests++;
    final b = Uint8List(tw * th * 4);
    for (var i = 0; i < b.length; i += 4) {
      b[i] = 200;
      b[i + 1] = 100;
      b[i + 2] = 50;
      b[i + 3] = 255;
    }
    return b;
  }

  @override
  int frameHash(int index) {
    hashCalls++;
    return hashes[index] ?? index;
  }

  @override
  Future<void> openFrameSheet(int index) async => sheetsOpened.add(index);
}

/// `n` frames with ids 100..100+n-1, 100 ms each, one layer named "Layer 1" holding one tile.
List<FrameInfo> fakeFrames(int n, {List<String> layerNames = const ['Layer 1']}) => [
      for (var i = 0; i < n; i++)
        FrameInfo(id: 100 + i, layers: [for (final name in layerNames) LayerInfo(name: name, presentTiles: 1)]),
    ];

/// Pushes the page over a base route; the pop value lands in [popped] (a one-element list).
Future<List<int?>> pumpFramesPage(WidgetTester t, FakeFramesHost host, {int columns = 4, Size size = const Size(400, 800)}) async {
  final popped = <int?>[];
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () async {
            final r = await Navigator.of(ctx).push<int>(MaterialPageRoute(builder: (_) => FramesPage(host: host, columns: columns)));
            popped.add(r);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return popped;
}
