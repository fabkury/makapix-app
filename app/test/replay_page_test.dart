import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/replay/replay_host.dart';
import 'package:makapix_club/editor/replay/replay_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Engine-free host: 4×4 frames whose top-left pixel encodes the position, seeks recorded.
class FakeReplayHost implements ReplayHost {
  FakeReplayHost({this.actions = 9000, this.failWith});

  final int actions;
  final String? failWith;
  final List<int> seeks = [];
  int _pos = 0;
  bool _ready = false;
  bool disposed = false;
  final ValueNotifier<double> _progress = ValueNotifier(0);

  @override
  int get actionCount => actions;
  @override
  List<int> get visiblePositions => List<int>.generate(actions, (i) => i + 1);
  @override
  bool get ready => _ready;
  @override
  String? get initError => failWith;
  @override
  ValueListenable<double> get initProgress => _progress;
  @override
  int get position => _pos;
  @override
  List<int> get endFrameDurationsUs => const [100000];
  @override
  (int, int) get endSize => (4, 4);

  @override
  Future<void> init() async {
    if (failWith != null) return;
    _progress.value = 1;
    _pos = actions;
    _ready = true;
  }

  @override
  Future<void> seek(int position) async {
    _pos = position;
    seeks.add(position);
  }

  @override
  (Uint8List, int, int) currentFrame() {
    final px = Uint8List(4 * 4 * 4);
    px[0] = _pos % 256;
    px[3] = 255;
    return (px, 4, 4);
  }

  @override
  void dispose() {
    disposed = true;
    _progress.dispose();
  }
}

Future<void> pumpReplay(WidgetTester tester, FakeReplayHost host, {VoidCallback? onShare}) async {
  await tester.pumpWidget(MaterialApp(
    home: ReplayPage(host: host, title: 'My drawing', onShareTimelapse: onShare),
  ));
  await tester.pump(); // settle init
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ready host: auto-play starts and sweeps toward the end', (tester) async {
    final host = FakeReplayHost(actions: 9000);
    await pumpReplay(tester, host);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget, reason: 'auto-play begins on ready');
    await tester.pump(const Duration(milliseconds: 200));
    expect(host.seeks, isNotEmpty);
    // 9000 actions → 30 s sweep floor → 10 actions per 33 ms tick.
    expect(host.seeks.first, lessThan(100));
    // Cleanly tear down the sweep timer.
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('slider drag pauses and seeks; no HUD text', (tester) async {
    final host = FakeReplayHost(actions: 1000);
    await pumpReplay(tester, host);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    host.seeks.clear();
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(80, 0));
    await tester.pump();
    expect(host.seeks, isNotEmpty, reason: 'dragging the thumb seeks');
    expect(find.byIcon(Icons.play_arrow), findsOneWidget, reason: 'dragging pauses the sweep');
    // No HUD: no tool/color/counter text beyond the title.
    expect(find.textContaining('actions'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('init error shows the message and no controls', (tester) async {
    final host = FakeReplayHost(failWith: 'Part of this replay is missing (a chapter base file).');
    await pumpReplay(tester, host);
    expect(find.textContaining('missing'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('share action invokes the handler', (tester) async {
    var shared = 0;
    final host = FakeReplayHost(actions: 100);
    await pumpReplay(tester, host, onShare: () => shared++);
    await tester.tap(find.byIcon(Icons.movie_outlined));
    expect(shared, 1);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
  });

  testWidgets('share action hidden without a handler', (tester) async {
    final host = FakeReplayHost(actions: 100);
    await pumpReplay(tester, host);
    expect(find.byIcon(Icons.movie_outlined), findsNothing);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
  });

  testWidgets('dispose cancels the sweep and disposes the host', (tester) async {
    final host = FakeReplayHost(actions: 500);
    await pumpReplay(tester, host);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(host.disposed, isTrue);
  });

  testWidgets('backgrounding pauses a running sweep; inactive does not', (tester) async {
    final host = FakeReplayHost(actions: 9000);
    await pumpReplay(tester, host);
    expect(find.byIcon(Icons.pause), findsOneWidget, reason: 'auto-play is running');

    // `inactive` (focus loss, permission prompts) keeps the sweep running — house style.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byIcon(Icons.pause), findsOneWidget);

    // `paused` (actually backgrounded) stops the 30 Hz replay loop. While paused the test
    // binding disables frames, so the icon is asserted after resume — which also checks
    // that resuming does NOT auto-restart the sweep (resume is manual). [battery F7]
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(); // settle any in-flight seek
    final seeksWhilePaused = host.seeks.length;
    await tester.pump(const Duration(milliseconds: 500));
    expect(host.seeks.length, seeksWhilePaused, reason: 'no ticks while backgrounded');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget,
        reason: 'sweep paused on background and stays paused after resume');
  });

  testWidgets('duration chips: default 30s, switching retunes a RUNNING sweep + persists',
      (tester) async {
    final host = FakeReplayHost(actions: 9000);
    await pumpReplay(tester, host);
    expect(find.text('15s'), findsOneWidget);
    expect(find.text('30s'), findsOneWidget);
    expect(find.text('60s'), findsOneWidget);
    // Default 30 s → 9000/(30·30) = 10 actions/tick.
    await tester.pump(const Duration(milliseconds: 40));
    expect(host.seeks.first, closeTo(10, 1));
    // Switch to 15 s WITHOUT pausing: the very next tick doubles the rate.
    host.seeks.clear();
    await tester.tap(find.text('15s'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byIcon(Icons.pause), findsOneWidget, reason: 'switching never pauses');
    final delta = host.seeks.last - host.seeks.first;
    expect(delta / (host.seeks.length - 1), closeTo(20, 2), reason: '15 s → 20 actions/tick');
    // The choice is persisted for future replays.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('replay.sweepSeconds_v1'), 15);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
  });

  testWidgets('a remembered duration is applied on open', (tester) async {
    SharedPreferences.setMockInitialValues({'replay.sweepSeconds_v1': 60});
    final host = FakeReplayHost(actions: 9000);
    await pumpReplay(tester, host);
    await tester.pump(); // let the async pref load land
    await tester.pump(const Duration(milliseconds: 40));
    // 60 s → 9000/(60·30) = 5 actions/tick.
    expect(host.seeks.last, lessThan(30), reason: 'sweep runs at the remembered slower rate');
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
  });

  testWidgets('canvas stretches to the available space, not the true pixel size', (tester) async {
    // Regression: RawImage sizes itself to the image's intrinsic pixels (4×4 from the fake
    // host) unless given explicit dimensions — the replay must fill the box like the
    // editor canvas does.
    final host = FakeReplayHost(actions: 100);
    // decodeImageFromPixels completes on the real engine — the whole flow needs real async.
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: ReplayPage(host: host, title: 't')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    final raw = tester.widgetList<RawImage>(find.byType(RawImage));
    expect(raw, isNotEmpty, reason: 'a frame should be showing');
    final img = raw.first;
    expect(img.width, greaterThan(100), reason: 'must span the layout box, not 4px');
    expect(img.fit, BoxFit.contain);
    expect(img.filterQuality, FilterQuality.none);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
  });
}
