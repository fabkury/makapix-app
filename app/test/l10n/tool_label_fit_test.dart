// T5 (docs/i18n/TESTING.md): every row-3 tool label fits its tile, in every language.
//
// The tile is 54 px wide and its label is one line of 8.5 px type — the tightest text box in
// the app. A label too long for it shrinks to fit, so at the default font size every label is
// held to a budget that never needs shrinking. This pumps the real [ToolTile] with real font
// metrics. With a large system font the labels grow and then shrink to fit; the last test
// checks that none spills out of its tile.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/tool_l10n.dart';
import 'package:makapix_club/editor/tools.dart';
import 'package:makapix_club/editor/widgets/tool_tile.dart';

import 'l10n_test_support.dart';

/// Every tile the toolbar can show: the catalog plus the pinned Undo / Redo / Repeat faces.
const List<ToolDef> _allTiles = [...tools, undoToolDef, redoToolDef, repeatToolDef];

void main() {
  test('every tile face has names', () {
    expect({for (final t in _allTiles) t.face}.difference(toolFaces.toSet()), isEmpty);
    expect(toolFaces.toSet().difference({for (final t in _allTiles) t.face}), isEmpty,
        reason: 'names for a tool that is no longer in the catalog');
  });

  for (final locale in allLocales) {
    testWidgets('tool labels fit the tile — $locale', (tester) async {
      await pumpLocalized(
        tester,
        locale,
        Scaffold(
          body: SingleChildScrollView(
            child: Wrap(children: [
              for (final t in _allTiles) ToolTile(t, selected: false),
            ]),
          ),
        ),
        size: const Size(412, 915),
      );
      expect(find.byType(ToolTile), findsNWidgets(_allTiles.length));
      expect(truncatedTexts(tester), isEmpty, reason: 'clipped tile labels in $locale');
      // Fitting in Roboto is not enough: other platform fonts set wider. Hold each label to
      // the budget, which leaves that reserve.
      final overBudget = [
        for (final ro in paragraphs(tester))
          if (ro.getMaxIntrinsicWidth(double.infinity) > ToolTile.labelBudget)
            '"${ro.text.toPlainText()}" is ${ro.getMaxIntrinsicWidth(double.infinity).toStringAsFixed(1)} px',
      ];
      expect(overBudget, isEmpty,
          reason: 'tile labels over the ${ToolTile.labelBudget} px budget in $locale');
    });

    test('short labels are distinct, and no longer than the full name — $locale', () {
      final l = l10nFor(locale);
      final shorts = <String, String>{};
      final problems = <String>[];
      for (final face in toolFaces) {
        final short = toolShortLabel(l, face);
        final full = toolName(l, face);
        if (short.runes.length > full.runes.length) problems.add('$face: "$short" longer than "$full"');
        final clash = shorts[short];
        if (clash != null) problems.add('"$short" names both $clash and $face');
        shorts[short] = face;
      }
      expect(problems, isEmpty);
    });
  }

  for (final locale in allLocales) {
    for (final scale in const [1.3, 2.0]) {
      testWidgets('tool labels stay inside the tile at text scale $scale — $locale', (tester) async {
        await pumpLocalized(
          tester,
          locale,
          Scaffold(
            body: SingleChildScrollView(
              child: Wrap(children: [
                for (final t in _allTiles) ToolTile(t, selected: false),
              ]),
            ),
          ),
          size: const Size(412, 915),
          textScale: scale,
        );
        final l = l10nFor(locale);
        final spills = <String>[];
        for (final t in _allTiles) {
          final tile = find.byWidgetPredicate((w) => w is ToolTile && w.tool == t);
          final box = tester.getRect(find.descendant(of: tile, matching: find.byType(Container)).first);
          final text = tester.getRect(find.descendant(of: tile, matching: find.text(t.shortLabel(l))));
          if (text.left < box.left - 0.5 || text.right > box.right + 0.5 || text.bottom > box.bottom + 0.5) {
            spills.add('"${t.shortLabel(l)}" ${text.width.toStringAsFixed(1)} px');
          }
        }
        expect(spills, isEmpty, reason: 'tile labels outside their tile at text scale $scale');
      });
    }
  }
}
