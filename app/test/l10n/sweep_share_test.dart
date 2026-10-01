// T4 sweeps: the size dialog shared by Export (editor) and Share (Club and editor), with its
// very-large warning showing (batch C9).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/share/image_share.dart';

import 'sweep.dart';

/// Picks the largest scale and presses the action once: on a size this large the first press
/// only raises the red warning and relabels the button "… anyway".
Future<void> _raiseWarning(WidgetTester tester) async {
  await tapOpener(tester);
  await settleOpen(tester);
  await tester.tap(find.byType(ChoiceChip).last);
  await tester.pump();
  await tester.tap(find.byType(FilledButton).last);
}

void main() {
  sweepScreen(
    'Export size dialog, large-export warning',
    build: () => Opener((context, ref) =>
        showExportScaleDialog(context: context, width: 512, height: 512, frames: 200)),
    act: _raiseWarning,
  );

  sweepScreen(
    'Share size dialog, large-export warning',
    build: () => Opener((context, ref) => showExportScaleDialog(
          context: context,
          width: 512,
          height: 512,
          frames: 200,
          share: true,
          formats: const ['GIF', 'WebP'],
          initialFormat: 'GIF',
        )),
    act: _raiseWarning,
  );

  sweepScreen(
    'Export size dialog, still image',
    build: () => Opener((context, ref) =>
        showExportScaleDialog(context: context, width: 64, height: 64, frames: 1)),
    act: tapOpener,
  );
}
