// Test support for the Layers page (ADR 0033): a scripted LayersHost and a pump helper that
// pushes the page over a base route so its pops are real. No engine.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/layers/layer_model.dart';
import 'package:makapix_club/editor/layers/layers_host.dart';
import 'package:makapix_club/editor/layers/layers_page.dart';

class FakeLayersHost implements LayersHost {
  FakeLayersHost(this.layers, {this.active = 0, this.frames = 1, this.canvas = (w: 32, h: 32)});

  @override
  List<LayerRow> layers;
  int active;
  int frames;
  ({int w, int h}) canvas;
  bool canUndoV = false;
  bool canRedoV = false;
  int seq = 0;

  final List<String> scripts = [];

  /// The refusal to return from the next [run] (consumed once).
  String? refusal;

  /// Mutates [layers] to model the engine's effect; returns a refusal or null.
  String? Function(String dsl)? onRun;

  int thumbRequests = 0;
  final Map<int, int> hashes = {};
  final List<int> sheetsOpened = [];
  int undos = 0;
  int redos = 0;

  @override
  int get activeLayerIndex => active;

  @override
  int get activeFrameIndex => 0;

  @override
  int get frameCount => frames;

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
  int layerHash(int index) => hashes[index] ?? index;

  @override
  Future<void> openLayerSheet(int index) async => sheetsOpened.add(index);
}

/// `n` layers with ids 500..500+n-1 named "L1".."Ln" (bottom first), one tile each.
List<LayerRow> fakeLayers(int n) => [for (var i = 0; i < n; i++) LayerRow(id: 500 + i, name: 'L${i + 1}', presentTiles: 1)];

/// Pushes the page over a base route; the pop value lands in [popped] (a one-element list).
Future<List<LayersPageResult?>> pumpLayersPage(WidgetTester t, FakeLayersHost host, {Size size = const Size(400, 800)}) async {
  final popped = <LayersPageResult?>[];
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () async {
            final r = await Navigator.of(ctx).push<LayersPageResult>(MaterialPageRoute(builder: (_) => LayersPage(host: host)));
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
