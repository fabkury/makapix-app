import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/persistence/autosave_controller.dart';
import 'package:makapix_club/editor/persistence/drawing_meta.dart';
import 'package:makapix_club/editor/persistence/drawing_store.dart';

Uint8List bytesOf(String s) => Uint8List.fromList(s.codeUnits);

/// A store that counts doc writes and can be made to fail, for asserting write behaviour.
class CountingStore extends DrawingStore {
  CountingStore(super.base);
  int docWrites = 0;
  bool fail = false;
  @override
  Future<void> writeDoc(String id, Uint8List bytes) async {
    if (fail) throw const FileSystemException('disk full (test)');
    docWrites++;
    await super.writeDoc(id, bytes);
  }
}

DrawingMeta metaFor(String id) => DrawingMeta(
      id: id,
      title: 'T',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      width: 8,
      height: 8,
      frameCount: 1,
    );

void main() {
  late Directory base;
  late CountingStore store;
  late Uint8List current;
  late AutosaveController c;
  Object? lastError;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('mkpx_autosave_test');
    store = CountingStore(base);
    current = bytesOf('v1');
    lastError = null;
    c = AutosaveController(
      id: 'd1',
      store: store,
      serialize: () => current,
      buildMeta: () => metaFor('d1'),
      onError: (e) => lastError = e,
    );
  });
  tearDown(() async {
    await c.stop();
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('a cycle writes only when there was activity', () async {
    await c.debugCycle(); // no activity → no write
    expect(store.docWrites, 0);
    c.markActivity();
    await c.debugCycle();
    expect(store.docWrites, 1);
    expect(await store.readDoc('d1'), bytesOf('v1'));
  });

  test('unchanged bytes do not write again (hash gate)', () async {
    c.markActivity();
    await c.debugCycle();
    expect(store.docWrites, 1);
    c.markActivity(); // active again, but bytes identical
    await c.debugCycle();
    expect(store.docWrites, 1, reason: 'identical content must not rewrite');
  });

  test('changed bytes trigger a new write', () async {
    c.markActivity();
    await c.debugCycle();
    current = bytesOf('v2');
    c.markActivity();
    await c.debugCycle();
    expect(store.docWrites, 2);
    expect(await store.readDoc('d1'), bytesOf('v2'));
  });

  test('flushNow writes even when unchanged', () async {
    c.markActivity();
    await c.debugCycle();
    expect(store.docWrites, 1);
    await c.flushNow(); // same bytes, but a leave/background must persist regardless
    expect(store.docWrites, 2);
  });

  test('empty serialize never writes', () async {
    current = Uint8List(0);
    c.markActivity();
    await c.debugCycle();
    await c.flushNow();
    expect(store.docWrites, 0);
  });

  test('write failure is reported, not thrown', () async {
    store.fail = true;
    c.markActivity();
    await c.debugCycle(); // must not throw
    expect(lastError, isA<FileSystemException>());
    expect(store.docWrites, 0);
  });
}
