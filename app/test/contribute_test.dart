// Widget test for the Contribute page (lib/club/ui/contribute_page.dart): it offers the two
// contribute paths — the Makapix Editor and a direct file upload — and tapping the editor card
// bumps the `openEditorProvider` signal the shell listens on to switch to the editor pillar.
//
// The file-upload path drives the OS file picker + `dart:ui` codec, which isn't available under
// `flutter test`, so we assert on the card's presence rather than exercising the picker.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/state/edit_bridge.dart';
import 'package:makapix_club/club/ui/contribute_page.dart';

Widget _harness() => const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ContributePage())),
    );

void main() {
  testWidgets('shows both contribute options', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.text('Makapix Editor'), findsOneWidget);
    expect(find.text('Upload a file'), findsOneWidget);
    // The editor card carries its catchy one-liner.
    expect(find.textContaining('Create animated pixel art'), findsOneWidget);
  });

  testWidgets('tapping the editor card asks the shell to open the editor', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final container = ProviderScope.containerOf(tester.element(find.byType(ContributePage)));
    final before = container.read(openEditorProvider);

    await tester.tap(find.text('Makapix Editor'));
    await tester.pump();

    expect(container.read(openEditorProvider), before + 1,
        reason: 'the editor card bumps openEditorProvider so AppShell switches to the editor pillar');
  });
}
