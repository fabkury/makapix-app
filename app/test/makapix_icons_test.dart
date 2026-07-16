// Sanity tests for the generated custom icon set (makapix_icons.g.dart) and
// its ToolDef wiring. Pure widget/data tests — no engine or network.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/makapix_icon.dart';
import 'package:makapix_club/editor/tools.dart';

void main() {
  test('generated icon op streams are well-formed', () {
    expect(MpxIcons.all.length, 12);
    const opLen = [3, 3, 7, 1]; // moveTo, lineTo, cubicTo, close
    for (final icon in MpxIcons.all) {
      expect(icon.segs, isNotEmpty);
      for (final seg in icon.segs) {
        final o = seg.ops;
        expect(o.first.toInt(), 0, reason: 'segment must start with moveTo');
        var i = 0;
        while (i < o.length) {
          final op = o[i].toInt();
          expect(op, inInclusiveRange(0, 3));
          i += opLen[op];
        }
        expect(i, o.length, reason: 'op stream must terminate exactly');
        for (final v in o) {
          expect(v.isFinite, isTrue);
        }
      }
    }
  });

  test('every tool has exactly one icon source (Material xor custom)', () {
    for (final t in [...tools, undoToolDef, redoToolDef]) {
      expect((t.icon == null) ^ (t.custom == null), isTrue, reason: t.dsl);
    }
  });

  testWidgets('all custom icons build and paint at row-3 size', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Wrap(children: [
          for (final icon in MpxIcons.all) MakapixIcon(icon, size: 18),
        ]),
      ),
    ));
    expect(find.byType(MakapixIcon), findsNWidgets(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('iconWidget renders both custom and Material tools', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Wrap(children: [
          for (final t in tools) t.iconWidget(size: 18, color: Colors.white),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
