import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/replay/replay_host.dart';
import 'package:makapix_club/editor/replay/replay_page.dart';

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
}
