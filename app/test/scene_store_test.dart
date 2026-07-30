// SceneStore/SceneMeta (lib/animator/persistence/) — the persistence_test.dart mirror over
// `.mkps`: crash-safe write dance, `.bak` fallback, listing, delete, id shape, meta fps.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/animator/persistence/scene_meta.dart';
import 'package:makapix_club/animator/persistence/scene_store.dart';

Uint8List bytesOf(String s) => Uint8List.fromList(s.codeUnits);

SceneMeta metaFor(String id, {String title = 'T'}) => SceneMeta(
      id: id,
      title: title,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      width: 64,
      height: 64,
      frameCount: 25,
      fpsMilli: 12500,
    );

void main() {
  group('SceneMeta', () {
    test('round-trips through JSON, fps included', () {
      final m = metaFor('scn_a');
      final back = SceneMeta.tryParse(m.encode(),
          fallbackId: 'x', fallbackTime: DateTime.utc(2000));
      expect(back!.id, 'scn_a');
      expect(back.fpsMilli, 12500);
      expect(back.frameCount, 25);
    });

    test('tolerates missing fields and rejects id-less JSON', () {
      final back = SceneMeta.tryParse('{"id":"scn_b"}',
          fallbackId: 'x', fallbackTime: DateTime.utc(2000));
      expect(back!.title, 'Untitled');
      expect(back.fpsMilli, 12500, reason: 'fps falls back to the default rate');
      expect(
          SceneMeta.tryParse('{}', fallbackId: 'x', fallbackTime: DateTime.utc(2000)), isNull);
      expect(SceneMeta.tryParse('garbage', fallbackId: 'x', fallbackTime: DateTime.utc(2000)),
          isNull);
    });
  });

  group('SceneStore', () {
    late Directory base;
    late SceneStore store;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('mkps_store_test');
      store = SceneStore(base);
    });
    tearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    test('ids are scn_-prefixed, unique, and filesystem-safe', () {
      final a = SceneStore.newId(1000, 1);
      final b = SceneStore.newId(1000, 2);
      expect(a, startsWith('scn_'));
      expect(a, isNot(b));
      expect(RegExp(r'^[a-z0-9_]+$').hasMatch(a), isTrue);
    });

    test('writeDoc→readDoc round-trips and keeps a .bak', () async {
      await store.writeDoc('s1', bytesOf('v1'));
      await store.writeDoc('s1', bytesOf('v2'));
      expect(String.fromCharCodes((await store.readDoc('s1'))!), 'v2');
      expect(await File('${store.dirFor('s1').path}/doc.mkps.bak').exists(), isTrue);
    });

    test('empty bytes never clobber; corrupt primary falls back to .bak', () async {
      await store.writeDoc('s2', bytesOf('good'));
      await store.writeDoc('s2', Uint8List(0));
      expect(String.fromCharCodes((await store.readDoc('s2'))!), 'good');

      await store.writeDoc('s2', bytesOf('BAD'));
      final got = await store.readDoc('s2',
          validate: (b) => String.fromCharCodes(b) != 'BAD');
      expect(String.fromCharCodes(got!), 'good', reason: 'validate rejects → .bak wins');
    });

    test('list() is newest-first and skips docless folders', () async {
      await store.writeDoc('old', bytesOf('a'));
      await store.writeMeta(metaFor('old').copyWith(updatedAt: DateTime.utc(2026, 1, 1)));
      await store.writeDoc('new', bytesOf('b'));
      await store.writeMeta(metaFor('new').copyWith(updatedAt: DateTime.utc(2026, 6, 1)));
      await store.writeMeta(metaFor('ghost')); // meta but no doc → skipped
      final list = await store.list();
      expect(list.map((m) => m.id).toList(), ['new', 'old']);
    });

    test('delete removes the folder', () async {
      await store.writeDoc('s3', bytesOf('x'));
      expect(await store.exists('s3'), isTrue);
      await store.delete('s3');
      expect(await store.exists('s3'), isFalse);
    });
  });
}
