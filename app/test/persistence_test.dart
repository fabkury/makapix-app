import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/persistence/drawing_meta.dart';
import 'package:makapix_club/editor/persistence/drawing_store.dart';

Uint8List bytesOf(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  group('DrawingMeta', () {
    test('round-trips through JSON', () {
      final m = DrawingMeta(
        id: 'dwg_abc',
        title: 'My Art',
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        updatedAt: DateTime.utc(2026, 6, 7, 8, 9, 10),
        width: 64,
        height: 48,
        frameCount: 3,
      );
      final back = DrawingMeta.tryParse(m.encode())!;
      expect(back.id, 'dwg_abc');
      expect(back.title, 'My Art');
      expect(back.createdAt, m.createdAt);
      expect(back.updatedAt, m.updatedAt);
      expect(back.width, 64);
      expect(back.height, 48);
      expect(back.frameCount, 3);
    });

    test('tolerates missing fields with fallbacks', () {
      final m = DrawingMeta.tryParse('{"id":"dwg_x"}', fallbackTime: DateTime.utc(2020))!;
      expect(m.id, 'dwg_x');
      expect(m.title, 'Untitled');
      expect(m.frameCount, 1);
      expect(m.width, 0);
    });

    test('returns null on garbage or id-less JSON', () {
      expect(DrawingMeta.tryParse('not json'), isNull);
      expect(DrawingMeta.tryParse('{"title":"no id"}'), isNull);
      expect(DrawingMeta.tryParse('{"title":"no id"}', fallbackId: 'dwg_f')!.id, 'dwg_f');
    });
  });

  group('DrawingStore', () {
    late Directory base;
    late DrawingStore store;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('mkpx_store_test');
      store = DrawingStore(base);
    });
    tearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    test('newId is unique and well-formed', () {
      final a = DrawingStore.newId(1700000000000000, 1);
      final b = DrawingStore.newId(1700000000000001, 2);
      expect(a, isNot(b));
      expect(a.startsWith('dwg_'), isTrue);
      expect(RegExp(r'^[A-Za-z0-9_]+$').hasMatch(a), isTrue, reason: 'filesystem-safe');
    });

    test('writeDoc then readDoc round-trips', () async {
      await store.writeDoc('d1', bytesOf('hello'));
      expect(await store.readDoc('d1'), bytesOf('hello'));
      expect(await store.exists('d1'), isTrue);
    });

    test('empty bytes never clobber a good doc', () async {
      await store.writeDoc('d1', bytesOf('good'));
      await store.writeDoc('d1', Uint8List(0));
      expect(await store.readDoc('d1'), bytesOf('good'));
    });

    test('second write keeps the prior copy as .bak', () async {
      await store.writeDoc('d1', bytesOf('v1'));
      await store.writeDoc('d1', bytesOf('v2'));
      expect(await store.docFile('d1').readAsBytes(), bytesOf('v2'));
      final bak = File('${store.dirFor('d1').path}/doc.mkpx.bak');
      expect(await bak.readAsBytes(), bytesOf('v1'));
    });

    test('corrupt primary falls back to .bak via validate', () async {
      await store.writeDoc('d1', bytesOf('v1'));
      await store.writeDoc('d1', bytesOf('v2'));
      // pretend v2 is corrupt: only v1 (the .bak) validates
      final got = await store.readDoc('d1', validate: (b) => String.fromCharCodes(b) == 'v1');
      expect(got, bytesOf('v1'));
    });

    test('readDoc returns null when nothing valid exists', () async {
      expect(await store.readDoc('missing'), isNull);
      await store.writeDoc('d1', bytesOf('v1'));
      expect(await store.readDoc('d1', validate: (_) => false), isNull);
    });

    test('a stray .tmp left by a crash is ignored', () async {
      await store.writeDoc('d1', bytesOf('v1'));
      await File('${store.dirFor('d1').path}/doc.mkpx.tmp').writeAsBytes(bytesOf('partial'));
      expect(await store.readDoc('d1'), bytesOf('v1')); // tmp never read
    });

    test('list reports drawings (with meta) newest-first and skips docless folders', () async {
      await store.writeDoc('old', bytesOf('o'));
      await store.writeMeta(DrawingMeta(
          id: 'old', title: 'Old', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026, 1, 1),
          width: 8, height: 8, frameCount: 1));
      await store.writeDoc('new', bytesOf('n'));
      await store.writeMeta(DrawingMeta(
          id: 'new', title: 'New', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026, 2, 2),
          width: 8, height: 8, frameCount: 1));
      // a folder with meta but no doc must not appear
      await store.writeMeta(DrawingMeta(
          id: 'ghost', title: 'Ghost', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026, 3, 3),
          width: 8, height: 8, frameCount: 1));

      final ls = await store.list();
      expect(ls.map((m) => m.id).toList(), ['new', 'old']);
    });

    test('delete removes the whole drawing folder', () async {
      await store.writeDoc('d1', bytesOf('v1'));
      await store.delete('d1');
      expect(await store.exists('d1'), isFalse);
      expect(await store.dirFor('d1').exists(), isFalse);
    });

    test('writeThumb/writeMeta create and replace atomically', () async {
      await store.writeDoc('d1', bytesOf('v1'));
      await store.writeThumb('d1', bytesOf('PNG1'));
      expect(await store.thumbFile('d1').readAsBytes(), bytesOf('PNG1'));
      await store.writeThumb('d1', bytesOf('PNG2'));
      expect(await store.thumbFile('d1').readAsBytes(), bytesOf('PNG2'));
      expect(await store.readMeta('d1'), isNull); // none written yet
    });
  });
}
