// The Artwork colors page (inspect-before-commit behind "From artwork colors"): the spinner
// state, the three message states and their Close button, the swatch grid with Accept/Reject,
// and the per-color sheet (exact value + copy, add to the active palette with duplicate/cap
// rules, set as primary). Driven through the fake PaletteHost — no engine, no network.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/artwork_colors_page.dart';
import 'package:makapix_club/editor/palette_io.dart';
import 'package:makapix_club/editor/widgets/painters.dart' show AlphaSwatch;

import 'palette_page_test.dart' show FakePaletteHost;

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _blue = Color(0xFF0000FF);

/// Pushes the page over a base route so its pops are real; the returned closure yields what it
/// popped (and asserts that it did).
///
/// [settle] false pumps a couple of frames instead of pumpAndSettle — for the extracting state,
/// whose spinner animates forever. The MaterialApp gets a fresh key so a second _open in one test
/// rebuilds the tree instead of reusing a Navigator that still has the previous page pushed.
Future<Future<int?> Function()> _open(WidgetTester t, FakePaletteHost host, {bool settle = true}) async {
  int? popped;
  var done = false;
  await t.pumpWidget(MaterialApp(
    key: UniqueKey(),
    theme: ThemeData(brightness: Brightness.dark),
    home: Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () async {
            popped = await Navigator.of(ctx).push<int>(MaterialPageRoute(builder: (_) => ArtworkColorsPage(host: host)));
            done = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }
  return () async {
    expect(done, isTrue, reason: 'the page has popped');
    return popped;
  };
}

FilledButton _primaryButton(WidgetTester t) => t.widget<FilledButton>(find.byType(FilledButton));
OutlinedButton _rejectButton(WidgetTester t) => t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Reject'));

void main() {
  group('parseArtworkColors', () {
    test('shapes: ready / empty / over the limit / failed', () {
      final ready = parseArtworkColors('{"colors":["#FF0000FF","#00FF0080"]}');
      expect(ready.status, ArtworkColorsStatus.ready);
      expect(ready.colors, [_red, const Color(0x8000FF00)]);
      expect(parseArtworkColors('{"colors":[]}').status, ArtworkColorsStatus.empty);
      expect(parseArtworkColors('{"over_limit":true}').status, ArtworkColorsStatus.overLimit);
      expect(parseArtworkColors('{}').status, ArtworkColorsStatus.failed, reason: 'unloadable snapshot');
      expect(parseArtworkColors('not json').status, ArtworkColorsStatus.failed);
    });
  });

  group('artworkColorClipboardText', () {
    test('#RRGGBB when opaque, #RRGGBBAA otherwise', () {
      expect(artworkColorClipboardText(const Color(0xFF3A7BD5)), '#3A7BD5');
      expect(artworkColorClipboardText(const Color(0x803A7BD5)), '#3A7BD580');
      expect(artworkColorClipboardText(const Color(0x01000000)), '#00000001');
    });
    test('channels read the exact 8-bit values', () {
      expect(artworkColorChannels(const Color(0x803A7BD5)), 'R 58 · G 123 · B 213 · A 128');
    });
  });

  testWidgets('while extracting: spinner + message, Accept and Reject both inert', (t) async {
    final host = FakePaletteHost([const PaletteInfo('Mine', [_red])], extract: () => Completer<String>().future);
    await _open(t, host, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Extracting artwork colors...'), findsOneWidget);
    expect(_primaryButton(t).onPressed, isNull);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
    expect(_rejectButton(t).onPressed, isNull);
    expect(host.scripts, isEmpty);
  });

  testWidgets('over the limit: message, Close live, Reject inert; Close pops null', (t) async {
    final host = FakePaletteHost([const PaletteInfo('Mine', [_red])], usedColors: '{"over_limit":true}');
    final result = await _open(t, host);
    expect(find.textContaining('more than 256 colors'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_rejectButton(t).onPressed, isNull);
    expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Close'));
    await t.pumpAndSettle();
    expect(await result(), isNull);
    expect(host.scripts, isEmpty);
  });

  testWidgets('empty artwork and a failed read are messages with Close', (t) async {
    var host = FakePaletteHost([const PaletteInfo('Mine', [_red])], usedColors: '{"colors":[]}');
    await _open(t, host);
    expect(find.text('The artwork has no colors yet.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
    expect(_rejectButton(t).onPressed, isNull);

    host = FakePaletteHost([const PaletteInfo('Mine', [_red])], extract: () => Future.error(StateError('boom')));
    await _open(t, host);
    expect(find.text('Could not read the artwork.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
  });

  testWidgets('ready: one swatch per color in the given order, caption, Accept + Reject live', (t) async {
    final host = FakePaletteHost([const PaletteInfo('Mine', [_red])],
        usedColors: '{"colors":["#FF0000FF","#00FF00FF","#0000FFFF"]}');
    await _open(t, host);
    final swatches = t.widgetList<AlphaSwatch>(find.byType(AlphaSwatch)).map((s) => s.color).toList();
    expect(swatches, [_red, _green, _blue]);
    expect(find.textContaining('3 colors, in palette order'), findsOneWidget);
    expect(_primaryButton(t).onPressed, isNotNull);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
    expect(_rejectButton(t).onPressed, isNotNull);
  });

  testWidgets('the pending-Draft note shows only when the host reports a Draft', (t) async {
    await _open(t, FakePaletteHost([const PaletteInfo('Mine', [_red])], usedColors: '{"colors":["#FF0000FF"]}'));
    expect(find.textContaining('pending edit is not included'), findsNothing);
    await _open(
        t,
        FakePaletteHost([const PaletteInfo('Mine', [_red])],
            usedColors: '{"colors":["#FF0000FF"]}', pendingDraft: true));
    expect(find.textContaining('pending edit is not included'), findsOneWidget);
  });

  testWidgets('Accept creates the palette without SortPalette and pops the count', (t) async {
    final host = FakePaletteHost([const PaletteInfo('Mine', [_red])],
        usedColors: '{"colors":["#FF0000FF","#00FF00FF"]}');
    final result = await _open(t, host);
    await t.tap(find.widgetWithText(FilledButton, 'Accept'));
    await t.pumpAndSettle();
    expect(host.scripts, ['NewPalette(Artwork colors)\nAddPaletteColor(#FF0000FF)\nAddPaletteColor(#00FF00FF)']);
    expect(await result(), 2);
  });

  testWidgets('Reject sends nothing and pops null', (t) async {
    final host = FakePaletteHost([const PaletteInfo('Mine', [_red])], usedColors: '{"colors":["#FF0000FF"]}');
    final result = await _open(t, host);
    await t.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await t.pumpAndSettle();
    expect(host.scripts, isEmpty);
    expect(await result(), isNull);
  });

  group('color sheet', () {
    Future<FakePaletteHost> openSheet(WidgetTester t, {List<Color> active = const [_red], String colors = '["#00FF00FF"]'}) async {
      final host = FakePaletteHost([PaletteInfo('Mine', active)], usedColors: '{"colors":$colors}');
      await _open(t, host);
      await t.tap(find.byType(AlphaSwatch).first);
      await t.pumpAndSettle();
      return host;
    }

    testWidgets('tap opens the sheet with the exact value and channels', (t) async {
      await openSheet(t, colors: '["#3A7BD580"]');
      expect(find.text('#3A7BD580'), findsOneWidget);
      expect(find.text('R 58 · G 123 · B 213 · A 128'), findsOneWidget);
      expect(find.text('Copy #3A7BD580'), findsOneWidget);
      expect(find.text('Add to "Mine"'), findsOneWidget);
      expect(find.text('Set as primary color'), findsOneWidget);
    });

    testWidgets('long-press opens the same sheet', (t) async {
      final host = FakePaletteHost([const PaletteInfo('Mine', [_red])], usedColors: '{"colors":["#00FF00FF"]}');
      await _open(t, host);
      await t.longPress(find.byType(AlphaSwatch).first);
      await t.pumpAndSettle();
      expect(find.text('#00FF00FF'), findsOneWidget);
    });

    testWidgets('Copy puts the clipboard text (#RRGGBB when opaque) on the clipboard', (t) async {
      final calls = <MethodCall>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await openSheet(t, colors: '["#00FF00FF"]');
      await t.tap(find.text('Copy #00FF00'));
      await t.pumpAndSettle();
      final set = calls.where((c) => c.method == 'Clipboard.setData').toList();
      expect(set, hasLength(1));
      expect((set.single.arguments as Map)['text'], '#00FF00');
      expect(find.text('Copied #00FF00'), findsOneWidget);
    });

    testWidgets('Add to the active palette: journaled once; a duplicate is skipped with a note', (t) async {
      final host = await openSheet(t, active: const [_red], colors: '["#00FF00FF"]');
      await t.tap(find.text('Add to "Mine"'));
      await t.pumpAndSettle();
      expect(host.scripts, ['AddPaletteColor(#00FF00FF)']);
      expect(find.text('Added to "Mine"'), findsOneWidget);
      // The fake host does not mutate its palettes, so re-open with the color already present.
      final dup = await openSheet(t, active: const [_green], colors: '["#00FF00FF"]');
      await t.tap(find.text('Add to "Mine"'));
      await t.pumpAndSettle();
      expect(dup.scripts, isEmpty);
      expect(find.text('Already in "Mine"'), findsOneWidget);
    });

    testWidgets('a full active palette refuses', (t) async {
      final full = List<Color>.generate(256, (i) => Color(0xFF000000 | i));
      final host = await openSheet(t, active: full, colors: '["#00FF00FF"]');
      await t.tap(find.text('Add to "Mine"'));
      await t.pumpAndSettle();
      expect(host.scripts, isEmpty);
      expect(find.text('"Mine" is full (256 colors)'), findsOneWidget);
    });

    testWidgets('Set as primary color reaches the host and keeps the page open', (t) async {
      final host = await openSheet(t, colors: '["#00FF00FF"]');
      await t.tap(find.text('Set as primary color'));
      await t.pumpAndSettle();
      expect(host.primaries, [_green]);
      expect(find.text('Artwork colors'), findsOneWidget); // still on the page
      expect(host.scripts, isEmpty);
    });
  });
}
