import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/persistence/autosave_controller.dart';
import 'package:makapix_club/editor/persistence/drawing_meta.dart';
import 'package:makapix_club/editor/persistence/drawing_store.dart';

Uint8List bytesOf(String s) => Uint8List.fromList(s.codeUnits);

/// A store that counts doc writes and can be made to fail, for asserting write behavior.
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

  test('flushNow skips the write when nothing changed since the last save', () async {
    // [battery F11] Android's resumed→inactive→hidden→paused walk triggers several
    // flushNow calls per backgrounding; identical bytes are already on disk.
    c.markActivity();
    await c.debugCycle();
    expect(store.docWrites, 1);
    await c.flushNow(); // same bytes → same hash → no rewrite, no fsync
    expect(store.docWrites, 1);
  });

  test('flushNow still writes changed bytes, and the first save of a document', () async {
    await c.flushNow(); // nothing saved yet → must write
    expect(store.docWrites, 1);
    current = bytesOf('v2');
    await c.flushNow();
    expect(store.docWrites, 2);
    expect(await store.readDoc('d1'), bytesOf('v2'));
  });

  test('pause cancels the timer; resume re-arms it; stop wins over resume', () async {
    // [battery F12] Backgrounding pauses the 5 s wakeups; foregrounding resumes them.
    c.start();
    expect(c.timerActive, isTrue);
    c.pause();
    expect(c.timerActive, isFalse);
    c.resume();
    expect(c.timerActive, isTrue);
    await c.stop();
    expect(c.timerActive, isFalse);
    c.resume(); // after stop() the controller is done — resume must not revive it
    expect(c.timerActive, isFalse);
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

  group('preWrite (the Journal write-ahead hook)', () {
    test('receives the fnv of the exact bytes, BEFORE writeDoc', () async {
      final events = <String>[];
      final hooked = AutosaveController(
        id: 'd1',
        store: _OrderStore(base, events),
        serialize: () => current,
        buildMeta: () => metaFor('d1'),
        preWrite: (fnv) async {
          events.add('preWrite:${fnv.toRadixString(16)}');
        },
      );
      current = bytesOf('v1');
      hooked.markActivity();
      await hooked.debugCycle();
      await hooked.stop();
      final expected = AutosaveController.fnv1a64(bytesOf('v1')).toRadixString(16);
      expect(events, ['preWrite:$expected', 'writeDoc', 'writeMeta'],
          reason: 'journal marker must be durably ahead of the doc write');
    });

    test('a throwing preWrite never blocks the doc write', () async {
      final hooked = AutosaveController(
        id: 'd1',
        store: store,
        serialize: () => current,
        buildMeta: () => metaFor('d1'),
        preWrite: (_) async => throw StateError('journal broke'),
      );
      hooked.markActivity();
      await hooked.debugCycle();
      await hooked.stop();
      expect(store.docWrites, 1, reason: 'the document is authoritative');
    });

    test('fnv1a64 golden vector', () {
      // Standard FNV-1a-64 of "a" is 0xaf63dc4c8601ec8c; the controller masks to 63 bits.
      expect(AutosaveController.fnv1a64(Uint8List.fromList('a'.codeUnits)),
          0xaf63dc4c8601ec8c & 0x7FFFFFFFFFFFFFFF);
    });
  });
}

/// Records the relative order of preWrite/writeDoc/writeMeta for the ordering test.
class _OrderStore extends DrawingStore {
  _OrderStore(super.base, this.events);
  final List<String> events;

  @override
  Future<void> writeDoc(String id, Uint8List bytes) async {
    events.add('writeDoc');
    await super.writeDoc(id, bytes);
  }

  @override
  Future<void> writeMeta(DrawingMeta meta) async {
    events.add('writeMeta');
    await super.writeMeta(meta);
  }
}
