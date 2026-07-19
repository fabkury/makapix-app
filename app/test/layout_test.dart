import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/ui/layout.dart';

void main() {
  group('breakpoint predicates', () {
    test('isTabletSize keys off the shortest side', () {
      expect(isTabletSize(const Size(390, 844)), isFalse); // phone portrait
      expect(isTabletSize(const Size(844, 390)), isFalse); // phone landscape
      expect(isTabletSize(const Size(600, 900)), isTrue); // exactly at the breakpoint
      expect(isTabletSize(const Size(599.9, 2000)), isFalse); // just under, no matter how tall
      expect(isTabletSize(const Size(820, 1180)), isTrue); // iPad portrait
      expect(isTabletSize(const Size(1180, 820)), isTrue); // iPad landscape
    });

    test('editorUsesLandscape is strictly wider-than-tall', () {
      expect(editorUsesLandscape(const Size(390, 844)), isFalse);
      expect(editorUsesLandscape(const Size(844, 390)), isTrue);
      expect(editorUsesLandscape(const Size(500, 500)), isFalse); // square stays portrait
      expect(editorUsesLandscape(const Size(500.1, 500)), isTrue);
    });
  });

  group('CenteredContent', () {
    testWidgets('caps and centers its child in a wide viewport', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const childKey = Key('content');
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: CenteredContent(child: SizedBox.expand(key: childKey))),
      ));

      final rect = tester.getRect(find.byKey(childKey));
      expect(rect.width, kContentMaxWidth);
      expect(rect.center.dx, 600); // horizontally centered in the 1200-wide viewport
      expect(rect.top, 0); // top-aligned, not vertically centered
    });

    testWidgets('is pass-through at phone width', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const childKey = Key('content');
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: CenteredContent(child: SizedBox.expand(key: childKey))),
      ));

      expect(tester.getRect(find.byKey(childKey)).width, 390);
    });
  });

  group('showAppSheet', () {
    testWidgets('caps sheet width on a wide viewport', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const sheetKey = Key('sheet');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showAppSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(key: sheetKey, height: 200, width: double.infinity),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.byKey(sheetKey));
      expect(rect.width, kSheetMaxWidth);
      expect(rect.center.dx, 500); // centered in the 1000-wide viewport
    });
  });
}
