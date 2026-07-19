// The editor's portrait/landscape chrome arrangement, tested via a lightweight harness.
//
// The real EditorPage cannot be pumped in a pure-Dart test (it loads the engine DLL), so this
// harness replicates the arrangement contract of _buildPortraitBody/_buildLandscapeBody in
// editor_page.dart with placeholder regions, switching on the same editorUsesLandscape() rule.
// It guards the switching rule and the approved region ORDER — the real builders are validated
// visually on Windows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/ui/layout.dart';

const _film = Key('film');
const _canvas = Key('canvas');
const _layers = Key('layers');
const _options = Key('options');
const _palette = Key('palette');
const _tools = Key('tools');

class _Region extends StatelessWidget {
  const _Region(Key key, {this.width, this.height}) : super(key: key);
  final double? width;
  final double? height;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width ?? double.infinity, height: height ?? double.infinity);
}

/// Mirrors the editor's body arrangement: portrait stacks horizontal bands; landscape is
/// frames · palette · [canvas / options] · layers · tools.
class _EditorChromeHarness extends StatelessWidget {
  const _EditorChromeHarness();
  @override
  Widget build(BuildContext context) {
    final landscape = editorUsesLandscape(MediaQuery.sizeOf(context));
    if (landscape) {
      return Row(children: const [
        _Region(_film, width: 70),
        _Region(_palette, width: 72),
        Expanded(
          child: Column(children: [
            Expanded(child: _Region(_canvas)),
            _Region(_options, height: 48),
          ]),
        ),
        _Region(_layers, width: 56),
        _Region(_tools, width: 120),
      ]);
    }
    return Column(children: const [
      _Region(_film, height: 70),
      Expanded(child: _Region(_canvas)),
      _Region(_layers, height: 56),
      _Region(_options, height: 48),
      _Region(_palette, height: 72),
      _Region(_tools, height: 100),
    ]);
  }
}

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _EditorChromeHarness())));
  }

  testWidgets('portrait stacks bands top-to-bottom: film, canvas, layers, options, palette, tools',
      (tester) async {
    await pumpAt(tester, const Size(400, 800));
    double top(Key k) => tester.getRect(find.byKey(k)).top;
    expect(top(_film), lessThan(top(_canvas)));
    expect(top(_canvas), lessThan(top(_layers)));
    expect(top(_layers), lessThan(top(_options)));
    expect(top(_options), lessThan(top(_palette)));
    expect(top(_palette), lessThan(top(_tools)));
    // Bands span the full width.
    expect(tester.getRect(find.byKey(_film)).width, 400);
    expect(tester.getRect(find.byKey(_tools)).width, 400);
  });

  testWidgets('landscape flanks the canvas: film | palette | canvas+options | layers | tools',
      (tester) async {
    await pumpAt(tester, const Size(1200, 600));
    double left(Key k) => tester.getRect(find.byKey(k)).left;
    expect(left(_film), 0);
    expect(left(_film), lessThan(left(_palette)));
    expect(left(_palette), lessThan(left(_canvas)));
    expect(left(_canvas), lessThan(left(_layers)));
    expect(left(_layers), lessThan(left(_tools)));
    expect(tester.getRect(find.byKey(_tools)).right, 1200);
    // The options band sits UNDER the canvas, matching its horizontal extent (center column).
    final canvas = tester.getRect(find.byKey(_canvas));
    final options = tester.getRect(find.byKey(_options));
    expect(options.top, greaterThanOrEqualTo(canvas.bottom));
    expect(options.left, canvas.left);
    expect(options.right, canvas.right);
    // Side strips span the full height.
    expect(tester.getRect(find.byKey(_palette)).height, 600);
  });

  testWidgets('the switch happens exactly at wider-than-tall', (tester) async {
    await pumpAt(tester, const Size(700, 700)); // square → portrait arrangement
    expect(tester.getRect(find.byKey(_film)).width, 700); // full-width band = portrait
    await pumpAt(tester, const Size(701, 700)); // one logical px wider → landscape
    expect(tester.getRect(find.byKey(_film)).width, 70); // vertical strip = landscape
  });
}
