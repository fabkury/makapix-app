import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/ui/artwork_detail_page.dart';
import 'package:makapix_club/club/ui/widgets/common.dart';

/// Pumps a page whose button opens [showUseAsProfilePhotoDialog] and records
/// the popped value. `artUrl` stays empty so HandleAvatar renders its
/// initial-letter fallback — no image network/IO in tests (repo convention).
Future<void> _pumpOpener(WidgetTester tester, void Function(bool?) onResult) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              onResult(await showUseAsProfilePhotoDialog(context,
                  artUrl: '', handle: 'pixelfan'));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the avatar-size preview next to the handle', (tester) async {
    await _pumpOpener(tester, (_) {});
    expect(find.text('Use as profile photo?'), findsOneWidget);
    expect(find.byType(HandleAvatar), findsOneWidget);
    expect(find.text('pixelfan'), findsOneWidget);
    // Empty artUrl → initial-letter fallback inside the avatar.
    expect(find.text('P'), findsOneWidget);
  });

  testWidgets('confirm pops true', (tester) async {
    bool? result;
    await _pumpOpener(tester, (r) => result = r);
    await tester.tap(find.text('Use photo'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('Use as profile photo?'), findsNothing);
  });

  testWidgets('cancel pops false', (tester) async {
    bool? result;
    await _pumpOpener(tester, (r) => result = r);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('barrier dismiss yields null (treated as not-confirmed)', (tester) async {
    bool? result = true;
    await _pumpOpener(tester, (r) => result = r);
    await tester.tapAt(const Offset(5, 5)); // outside the dialog
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
