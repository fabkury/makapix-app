// Animator widget tests (engine-free — previews are injected, no Engine/SceneEngine is ever
// constructed): the EasingChip cycle, the New-scene dialog (fps chips, Club-size advisory,
// the popped spec), and the Whole/Parts import card built from probe JSON.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/animator/dialogs/new_scene_dialog.dart';
import 'package:makapix_club/animator/import/import_prop_dialog.dart';
import 'package:makapix_club/animator/widgets/easing_chip.dart';
import 'package:makapix_club/club/publish/size_alert.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('EasingChip cycles the curated set on tap', (tester) async {
    final seen = <String>[];
    var value = 'linear';
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (_, setState) => EasingChip(
        value: value,
        onChanged: (v) {
          seen.add(v);
          setState(() => value = v);
        },
      ),
    )));
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byType(EasingChip));
      await tester.pump();
    }
    expect(seen, ['ease', 'easein', 'easeout', 'hold', 'linear'],
        reason: 'the chip cycles linear → ease → ease-in → ease-out → hold → linear');
  });

  group('NewSceneDialog', () {
    Future<NewSceneSpec?> open(WidgetTester tester,
        {int w = 64, int h = 64, Future<void> Function()? interact}) async {
      NewSceneSpec? result;
      await tester.pumpWidget(_host(Builder(
        builder: (ctx) => FilledButton(
          onPressed: () async {
            result = await showDialog<NewSceneSpec>(
              context: ctx,
              builder: (_) => NewSceneDialog(initialWidth: w, initialHeight: h),
            );
          },
          child: const Text('go'),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      if (interact != null) await interact();
      return result;
    }

    testWidgets('pops the chosen spec; fps chip retunes the default duration', (tester) async {
      final spec = await open(tester, interact: () async {
        await tester.tap(find.text('50 fps'));
        await tester.pump();
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
      });
      expect(spec, isNotNull);
      expect(spec!.fpsMilli, 50000);
      expect(spec.frames, 100, reason: 'two seconds at 50 fps until hand-edited');
      expect((spec.width, spec.height), (64, 64));
    });

    testWidgets('non-publishable sizes get the advisory alert but stay creatable',
        (tester) async {
      final spec = await open(tester, w: 100, h: 100, interact: () async {
        expect(find.byType(ClubSizeAlert), findsOneWidget,
            reason: '100×100 is not a Club-accepted size');
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
      });
      expect(spec, isNotNull, reason: 'the alert never blocks creation');
    });

    testWidgets('accepted sizes show no alert', (tester) async {
      await open(tester, w: 64, h: 64, interact: () async {
        expect(find.byType(ClubSizeAlert), findsNothing);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
    });
  });

  group('ImportPropDialog', () {
    const probeJson = '{"kind":"mkpx","w":24,"h":16,"frames":2,'
        '"layers":[{"name":"body"},{"name":"arm"},{"name":"head"}]}';

    testWidgets('offers Whole vs Parts from probe JSON and pops the choice', (tester) async {
      final probe = ImportProbe.parse(probeJson);
      expect(probe.offersSplit, isTrue);
      expect(probe.layerNames, ['body', 'arm', 'head']);

      bool? choice;
      await tester.pumpWidget(_host(Builder(
        builder: (ctx) => FilledButton(
          onPressed: () async {
            choice = await showDialog<bool>(
              context: ctx,
              builder: (_) => ImportPropDialog(probe: probe),
            );
          },
          child: const Text('go'),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Whole drawing'), findsOneWidget);
      expect(find.text('Separate parts'), findsOneWidget);
      expect(find.textContaining('3 layers'), findsOneWidget);
      await tester.tap(find.text('Separate parts'));
      await tester.pumpAndSettle();
      expect(choice, isTrue, reason: 'Parts pops true (split)');
    });

    test('probe parsing tolerates errors and rasters', () {
      expect(ImportProbe.parse('{"error":"too_large"}').isError, isTrue);
      final raster = ImportProbe.parse('{"kind":"raster","w":8,"h":8,"frames":12}');
      expect(raster.offersSplit, isFalse);
      expect(raster.frames, 12);
      expect(ImportProbe.parse('junk').isError, isTrue);
    });
  });
}
