import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/replay/mp4_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('club.makapix.app/timelapse');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('start/feed/finish sequence with the contract argument shapes', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'finish' ? '/tmp/out.mp4' : null;
    });

    final enc = Mp4EncoderChannel();
    await enc.start(width: 1080, height: 1080, fps: 30, bitrateBps: 2500000, path: '/tmp/out.mp4');
    final f0 = Uint8List(1080 * 1080 * 3 ~/ 2);
    await enc.feed(f0, 0);
    await enc.feed(f0, 33333);
    final path = await enc.finish();

    expect(path, '/tmp/out.mp4');
    expect(calls.map((c) => c.method).toList(), ['start', 'feed', 'feed', 'finish']);
    final start = calls.first.arguments as Map;
    expect(start['width'], 1080);
    expect(start['height'], 1080);
    expect(start['fps'], 30);
    expect(start['bitrateBps'], 2500000);
    expect(start['path'], '/tmp/out.mp4');
    // PTS strictly increasing, bytes tightly-packed I420 length.
    final ptss = calls.where((c) => c.method == 'feed').map((c) => (c.arguments as Map)['ptsUs'] as int).toList();
    expect(ptss, [0, 33333]);
    expect(((calls[1].arguments as Map)['bytes'] as Uint8List).length, 1080 * 1080 * 3 ~/ 2);
  });

  test('abort swallows platform errors (cleanup is best-effort)', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'ENCODE_FAILED');
    });
    final enc = Mp4EncoderChannel();
    await enc.abort(); // must not throw
  });

  test('a missing host handler surfaces from start (platform without the channel)', () async {
    final enc = Mp4EncoderChannel();
    expect(
      () => enc.start(width: 2, height: 2, fps: 30, bitrateBps: 1, path: 'x'),
      throwsA(isA<MissingPluginException>()),
    );
  });

  test('encoder errors propagate from feed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'feed') {
        throw PlatformException(code: 'ENCODE_FAILED', message: 'stalled');
      }
      return null;
    });
    final enc = Mp4EncoderChannel();
    await enc.start(width: 2, height: 2, fps: 30, bitrateBps: 1, path: 'x');
    expect(() => enc.feed(Uint8List(6), 0), throwsA(isA<PlatformException>()));
  });
}
