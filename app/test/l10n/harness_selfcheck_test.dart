// The i18n harness checks itself: a detector that never fires proves nothing. These tests feed
// l10n_test_support.dart text that is known to overflow, and known not to, and confirm the
// font metrics are the real ones rather than the test font's 1-em squares.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'l10n_test_support.dart';

double _width(WidgetTester tester, String text) =>
    tester.renderObject<RenderBox>(find.text(text)).size.width;

void main() {
  testWidgets('Latin and Cyrillic are measured in Roboto, CJK as full-width squares', (tester) async {
    await pumpLocalized(
      tester,
      const Locale('en'),
      const Scaffold(
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Gradient', style: TextStyle(fontSize: 10, letterSpacing: 0)),
          Text('Градиент', style: TextStyle(fontSize: 10, letterSpacing: 0)),
          Text('グラデ', style: TextStyle(fontSize: 10, letterSpacing: 0)),
          Text('iiii', style: TextStyle(fontSize: 10, letterSpacing: 0)),
          Text('MMMM', style: TextStyle(fontSize: 10, letterSpacing: 0)),
        ]),
      ),
    );
    // The test font would make every 8-letter word exactly 80 px wide. Roboto is proportional:
    // 'iiii' is far narrower than 'MMMM', and an 8-letter word is well under 80 px.
    expect(_width(tester, 'iiii'), lessThan(_width(tester, 'MMMM') / 2));
    expect(_width(tester, 'Gradient'), inInclusiveRange(30, 50));
    expect(_width(tester, 'Градиент'), inInclusiveRange(35, 60));
    // Three full-width kana at 10 px: 30 px.
    expect(_width(tester, 'グラデ'), closeTo(30, 0.5));
  });

  testWidgets('truncatedTexts catches a clipped single-line label and an ellipsized one', (tester) async {
    await pumpLocalized(
      tester,
      const Locale('en'),
      const Scaffold(
        body: Column(children: [
          SizedBox(width: 40, child: Text('This label is far too long', maxLines: 1, overflow: TextOverflow.clip)),
          SizedBox(width: 40, child: Text('Another long label here', maxLines: 1, overflow: TextOverflow.ellipsis)),
          SizedBox(width: 40, child: Text('Wraps over and over again', maxLines: 2)),
          SizedBox(width: 40, child: Text('No wrap at all here', softWrap: false)),
          SizedBox(width: 200, child: Text('Fits', maxLines: 1)),
          SizedBox(width: 60, child: Text('Wraps freely and that is fine')),
        ]),
      ),
    );
    final cut = truncatedTexts(tester).map((t) => t.text).toSet();
    expect(cut, {
      'This label is far too long',
      'Another long label here',
      'Wraps over and over again',
      'No wrap at all here',
    });
  });

  testWidgets('leftoverLatin flags English on a Japanese screen, not brand names or fixtures', (tester) async {
    await pumpLocalized(
      tester,
      const Locale('ja'),
      const Scaffold(
        body: Column(children: [
          Text('設定'),
          Text('Makapix Club'),
          Text('512 × 512 px'),
          Text('PNG / GIF / WebP'),
          Text('@pixel_artist'),
          Text('Delete frame'),
          Tooltip(message: 'Nudge left', child: Text('←')),
        ]),
      ),
    );
    expect(leftoverLatin(tester, allow: ['@pixel_artist']), unorderedEquals(['Delete frame', 'Nudge left']));
  });

  testWidgets('leftoverEnglish flags an untranslated message on a German screen', (tester) async {
    await pumpLocalized(
      tester,
      const Locale('de'),
      const Scaffold(
        body: Column(children: [
          Text('Einstellungen'),
          Text('Settings'), // English wording whose German differs
          Text('OK'), // identical in German: not a leftover
        ]),
      ),
    );
    expect(leftoverEnglish(tester, 'de'), ['Settings']);
  });
}
