import 'dart:typed_data' show Uint32List;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/replay/journal_format.dart' show kJournalEpoch;
import 'package:makapix_club/editor/replay/replay_host.dart';
import 'package:makapix_club/editor/replay/replay_page.dart';
import 'package:makapix_club/editor/replay/timelapse_plan.dart' show kEventFloorDivisor, progressDurationUs;
import 'package:makapix_club/editor/replay/visible_index.dart';
import 'package:makapix_club/editor/widgets/painters.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Engine-free host: 4×4 frames whose top-left pixel encodes the position, seeks recorded.
/// The timeline defaults to uniform stream ticks at every position (the legacy pacing).
class FakeReplayHost implements ReplayHost {
  FakeReplayHost({this.actions = 9000, this.failWith, this.epoch = kJournalEpoch, ReplayTimeline? timeline})
      : timeline = timeline ?? ReplayTimeline.uniform(actions);

  final int actions;
  final String? failWith;
  final int epoch;
  @override
  final ReplayTimeline timeline;
  final List<int> seeks = [];
  int _pos = 0;
  bool _ready = false;
  bool disposed = false;
  final ValueNotifier<double> _progress = ValueNotifier(0);

  @override
  int get actionCount => actions;
  @override
  bool get ready => _ready;
  @override
  String? get initError => failWith;
  @override
  ValueListenable<double> get initProgress => _progress;
  @override
  int get position => _pos;
  @override
  int get journalEpoch => epoch;
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

  // ADR 0015: a replay recorded under an older epoch is badged, because today's engine
  // semantics may render it differently than the session that produced it.
  testWidgets('a pre-epoch journal is badged', (tester) async {
    await pumpReplay(tester, FakeReplayHost(actions: 9000, epoch: 1));
    expect(find.text('Older recording'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause)); // stop the sweep timer
    await tester.pump();
  });
  testWidgets('a current-epoch journal is not badged', (tester) async {
    await pumpReplay(tester, FakeReplayHost(actions: 9000, epoch: kJournalEpoch));
    expect(find.text('Older recording'), findsNothing);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
  });
  // The share action is a LABELED button with the platform share icon at the very bottom
  // of the page, under the slider (2026-09-18): an icon-only film clapper with a long-press
  // tooltip in the AppBar hid the export from lay users.
  testWidgets('share action is a labeled footer button under the slider and invokes the handler',
      (tester) async {
    var shared = 0;
    final host = FakeReplayHost(actions: 100);
    await pumpReplay(tester, host, onShare: () => shared++);
    expect(find.byIcon(Icons.adaptive.share), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsNothing);
    final label = find.text('Share timelapse'); // flutter_test's platform is android
    expect(tester.getTopLeft(label).dy, greaterThan(tester.getBottomLeft(find.byType(Slider)).dy),
        reason: 'the button sits below the slider, not in the AppBar');
    expect(find.descendant(of: find.byType(AppBar), matching: label), findsNothing);
    await tester.tap(label);
    expect(shared, 1);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
  });

  testWidgets('share label: Share on mobile (share sheet), Export on desktop (a file)',
      (tester) async {
    expect(ReplayPage.shareLabel(TargetPlatform.android), 'Share timelapse');
    expect(ReplayPage.shareLabel(TargetPlatform.iOS), 'Share timelapse');
    expect(ReplayPage.shareLabel(TargetPlatform.windows), 'Export timelapse');
    expect(ReplayPage.shareLabel(TargetPlatform.macOS), 'Export timelapse');
    expect(ReplayPage.shareLabel(TargetPlatform.linux), 'Export timelapse');
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpReplay(tester, FakeReplayHost(actions: 100), onShare: () {});
      expect(find.text('Export timelapse'), findsOneWidget);
      expect(find.text('Share timelapse'), findsNothing);
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('share action is absent while the host is not ready', (tester) async {
    final host = FakeReplayHost(failWith: 'Part of this replay is missing.');
    await pumpReplay(tester, host, onShare: () {});
    expect(find.text('Share timelapse'), findsNothing);
    expect(find.byIcon(Icons.adaptive.share), findsNothing);
  });

  // The AppBar title wraps to a second line before the ellipsis (2026-09-18) — the share
  // action's move to the footer freed the room.
  testWidgets('the title wraps to two lines before truncating', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<double> titleHeight(String title) async {
      // Keyed per title: a same-type, unkeyed page would be UPDATED, not recreated, and the
      // reused State would never init the new host.
      await tester.pumpWidget(MaterialApp(
        home: ReplayPage(
            key: ValueKey(title), host: FakeReplayHost(actions: 100), title: title, onShareTimelapse: () {}),
      ));
      await tester.pump();
      final text = find.textContaining('Replay — ');
      expect(tester.widget<Text>(text).maxLines, 2);
      final h = tester.getSize(text).height;
      await tester.tap(find.byIcon(Icons.pause)); // stop the sweep timer
      await tester.pump();
      return h;
    }

    final short = await titleHeight('Sunset');
    final long = await titleHeight('A very long drawing title that no phone bar fits on one line');
    expect(long, greaterThan(short * 1.8), reason: 'the long title takes a second line');
    expect(long, lessThan(short * 2.5), reason: 'and no third');
  });

  testWidgets('share action hidden without a handler', (tester) async {
    final host = FakeReplayHost(actions: 100);
    await pumpReplay(tester, host);
    expect(find.byIcon(Icons.adaptive.share), findsNothing);
    expect(find.textContaining('timelapse'), findsNothing);
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

  testWidgets('the sweep ends ON the final position after exactly the preset', (tester) async {
    final host = FakeReplayHost(actions: 300);
    await pumpReplay(tester, host);
    await tester.pump(const Duration(seconds: 29));
    expect(find.byIcon(Icons.pause), findsOneWidget, reason: 'still sweeping at 29 s');
    expect(host.seeks.last, lessThan(300));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget, reason: 'paused at the end');
    expect(host.seeks.last, 300, reason: 'the final state is on screen');
  });

  testWidgets('paced axis: an event holds for its floor while stream ticks flow', (tester) async {
    // 60 stream ticks of 0.5 s each, then an apply 10 ms later. At 30 s the apply gets the
    // floor (T/100 = 9 frames); each stream tick shares the rest (about 14.85 frames).
    const n = 61;
    final timeline = ReplayTimeline(
      Int32List.fromList([for (var i = 1; i <= n; i++) i]),
      Uint8List.fromList([for (var i = 0; i < 60; i++) 0, 1]),
      Uint32List.fromList([for (var i = 0; i < 60; i++) 500, 10]),
    );
    final host = FakeReplayHost(actions: n, timeline: timeline);
    await pumpReplay(tester, host);
    await tester.pump(const Duration(seconds: 31));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    final floorFrames = progressDurationUs(30) ~/ kEventFloorDivisor ~/ 33333;
    expect(host.seeks.where((p) => p == 61).length, closeTo(floorFrames, 1),
        reason: 'the apply is on screen for its floor, not one frame');
    expect(host.seeks.where((p) => p == 1).length, closeTo(15, 1),
        reason: 'a stream tick gets its proportional share');
  });

  testWidgets('switching the preset keeps the tick on screen', (tester) async {
    final host = FakeReplayHost(actions: 9000);
    await pumpReplay(tester, host);
    await tester.pump(const Duration(milliseconds: 500)); // ~15 ticks: ~position 150 at 30 s
    final before = host.seeks.last;
    await tester.tap(find.text('60s'));
    await tester.pump(const Duration(milliseconds: 40));
    expect(host.seeks.last, closeTo(before + 5, 6), reason: '60 s halves the rate from where it was');
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

  testWidgets('canvas fills the box via CanvasPainter (checker under transparency)',
      (tester) async {
    // Two regressions in one: the replay must fill the layout box like the editor canvas
    // (never the 4×4 intrinsic pixels), and it must paint through CanvasPainter — the
    // painter that draws the transparency checker under the artwork (a plain RawImage
    // would let transparent pixels fall through to the dark page background).
    final host = FakeReplayHost(actions: 100);
    // decodeImageFromPixels completes on the real engine — the whole flow needs real async.
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: ReplayPage(host: host, title: 't')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    final paints = tester.widgetList<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is CanvasPainter));
    expect(paints, isNotEmpty, reason: 'a frame should be showing');
    final painter = paints.first.painter! as CanvasPainter;
    expect(painter.image, isNotNull);
    expect(painter.scale * painter.image!.width, greaterThan(100),
        reason: 'must span the layout box, not 4px');
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
  });
}
