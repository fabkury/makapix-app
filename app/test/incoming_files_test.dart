// The "Open in Makapix" receiving end (lib/shell/incoming_files.dart): classification of
// incoming filenames, dispatch onto the cross-pillar bridges, and the MethodChannel drain
// protocol against a mocked native side. No engine, no network — the bytes are opaque here
// (validation happens in the pillars' landings, driven by cargo tests + the mkpx harness).
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/state/edit_bridge.dart';
import 'package:makapix_club/shell/incoming_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('incomingFileKind', () {
    test('classifies the two document types, case-insensitively', () {
      expect(incomingFileKind('ball.mkps'), IncomingFileKind.scene);
      expect(incomingFileKind('Ball.MKPS'), IncomingFileKind.scene);
      expect(incomingFileKind('sprite.mkpx'), IncomingFileKind.drawing);
      expect(incomingFileKind('SPRITE.MkPx'), IncomingFileKind.drawing);
    });

    test('rejects everything else', () {
      expect(incomingFileKind('archive.zip'), isNull);
      expect(incomingFileKind('noextension'), isNull);
      expect(incomingFileKind('mkps'), isNull, reason: 'no dot — not an extension');
      expect(incomingFileKind('scene.mkps.png'), isNull, reason: 'only the final extension counts');
    });
  });

  group('incomingFileTitle', () {
    test('strips the final extension only', () {
      expect(incomingFileTitle('Bouncing ball.mkps'), 'Bouncing ball');
      expect(incomingFileTitle('archive.tar.gz'), 'archive.tar');
      expect(incomingFileTitle('noextension'), 'noextension');
    });

    test('falls back to Untitled when nothing usable remains', () {
      expect(incomingFileTitle('.mkps'), 'Untitled');
      expect(incomingFileTitle(''), 'Untitled');
    });
  });

  group('dispatchIncomingFile', () {
    test('.mkps lands on the Animator bridge with the title stripped', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final bytes = Uint8List.fromList([1, 2, 3]);

      expect(dispatchIncomingFile(container, 'Bouncing ball.mkps', bytes), isTrue);

      final req = container.read(pendingAnimatorProvider);
      expect(req, isA<OpenSceneBytes>());
      final scene = req as OpenSceneBytes;
      expect(scene.title, 'Bouncing ball');
      expect(scene.bytes, same(bytes));
      expect(container.read(pendingLocalLibraryProvider), isNull);
    });

    test('.mkpx lands on the editor bridge with the full filename', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final bytes = Uint8List.fromList([4, 5]);

      expect(dispatchIncomingFile(container, 'Sprite.mkpx', bytes), isTrue);

      final req = container.read(pendingLocalLibraryProvider);
      expect(req, isA<OpenDrawingBytes>());
      final drawing = req as OpenDrawingBytes;
      expect(drawing.name, 'Sprite.mkpx',
          reason: 'the editor landing shows the filename and strips the extension itself');
      expect(drawing.bytes, same(bytes));
      expect(container.read(pendingAnimatorProvider), isNull);
    });

    test('unrecognized files are refused and set no bridge', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(dispatchIncomingFile(container, 'notes.txt', Uint8List(1)), isFalse);

      expect(container.read(pendingAnimatorProvider), isNull);
      expect(container.read(pendingLocalLibraryProvider), isNull);
    });
  });

  group('IncomingFiles channel', () {
    tearDown(() {
      IncomingFiles.detach();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(IncomingFiles.channel, null);
    });

    // Install a mock native side whose queue is drained by 'drainPendingFiles'.
    void mockNativeQueue(List<Map<Object?, Object?>> queue) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(IncomingFiles.channel, (call) async {
        if (call.method != 'drainPendingFiles') return null;
        final drained = List.of(queue);
        queue.clear();
        return drained;
      });
    }

    test('attach drains anything queued before Flutter was up (cold start)', () async {
      final queue = [
        <Object?, Object?>{'name': 'ball.mkps', 'bytes': Uint8List.fromList([9])},
      ];
      mockNativeQueue(queue);

      final received = <String>[];
      await IncomingFiles.attach((name, bytes) => received.add('$name:${bytes.length}'));

      expect(received, ['ball.mkps:1']);
      expect(queue, isEmpty, reason: 'the drain consumed the native queue');
    });

    test('a filesPending nudge triggers another drain (warm open)', () async {
      final queue = <Map<Object?, Object?>>[];
      mockNativeQueue(queue);

      final received = <String>[];
      await IncomingFiles.attach((name, bytes) => received.add(name));
      expect(received, isEmpty);

      // The native side queues a file and nudges.
      queue.add(<Object?, Object?>{'name': 'sprite.mkpx', 'bytes': Uint8List.fromList([1, 2])});
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        IncomingFiles.channel.name,
        IncomingFiles.channel.codec.encodeMethodCall(const MethodCall('filesPending')),
        (_) {},
      );

      expect(received, ['sprite.mkpx']);
    });

    test('malformed or empty payloads are skipped', () async {
      final queue = [
        <Object?, Object?>{'name': 'empty.mkps', 'bytes': Uint8List(0)},
        <Object?, Object?>{'bytes': Uint8List.fromList([1])},
        <Object?, Object?>{'name': 'ok.mkps', 'bytes': Uint8List.fromList([1])},
      ];
      mockNativeQueue(queue);

      final received = <String>[];
      await IncomingFiles.attach((name, bytes) => received.add(name));

      expect(received, ['ok.mkps']);
    });

    test('attach is harmless on platforms without a native leg', () async {
      // No mock handler installed → MissingPluginException inside the drain.
      await IncomingFiles.attach((name, bytes) => fail('nothing should arrive'));
    });
  });
}
