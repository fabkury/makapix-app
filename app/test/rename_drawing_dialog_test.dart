// The shared drawing-title rules (rename dialog; the New-document dialog's title field applies
// the same cap): trimmed on save, capped at kDrawingTitleMaxLength characters at input time.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/dialogs/rename_drawing_dialog.dart';

void main() {
  Future<Future<String?>> open(WidgetTester tester, String initial) async {
    late Future<String?> result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => result = showRenameDrawingDialog(ctx, initialTitle: initial),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('Save returns the trimmed title', (tester) async {
    final result = await open(tester, 'Old');
    await tester.enterText(find.byType(TextField), '  Sunset run  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await result, 'Sunset run');
  });

  testWidgets('input is capped at kDrawingTitleMaxLength characters', (tester) async {
    final result = await open(tester, '');
    await tester.enterText(find.byType(TextField), 'x' * (kDrawingTitleMaxLength + 40));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await result)!.length, kDrawingTitleMaxLength);
    expect(kDrawingTitleMaxLength, 128);
  });

  testWidgets('Cancel returns null', (tester) async {
    final result = await open(tester, 'Keep');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
