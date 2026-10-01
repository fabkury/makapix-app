// T4 sweeps: the Palettes page, the Artwork colors page, the color dialog, and the Patterns
// and Dither pages — batch E5. All of them run on fakes: no engine.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/artwork_colors_page.dart';
import 'package:makapix_club/editor/dialogs/color_picker_dialog.dart';
import 'package:makapix_club/editor/palette_io.dart';
import 'package:makapix_club/editor/palette_page.dart';
import 'package:makapix_club/editor/patterns/gradient_dither.dart';
import 'package:makapix_club/editor/patterns/pattern_tile.dart';
import 'package:makapix_club/editor/patterns/patterns_catalog.dart';
import 'package:makapix_club/editor/patterns/patterns_page.dart';
import 'package:makapix_club/editor/tool_l10n.dart';
import 'package:makapix_club/l10n/l10n.dart';

import '../palette_page_test.dart' show FakePaletteHost;
import 'sweep.dart';

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _blue = Color(0x800000FF);

/// Names an artist (or a palette file) carries: shown as they are in every language.
const _fixture = ['Skin tones', 'PICO', 'Endesga'];

/// The engine's own palette (translated on screen), one the artist named, and an empty one.
FakePaletteHost _host({String used = '{"colors":["#FF0000FF","#00FF00FF","#0000FF80"]}', bool pending = false}) =>
    FakePaletteHost(
      [
        const PaletteInfo('Default', [_red, _green, _blue]),
        PaletteInfo('Skin tones', [for (var i = 0; i < 40; i++) Color(0xFF000000 | (i * 0x060504))]),
        const PaletteInfo('Blank', []),
      ],
      usedColors: used,
      pendingDraft: pending,
    );

Widget _palettes() => PalettePage(
      host: _host(),
      presetLoader: () async => const [
        PaletteInfo('PICO-8', [_red, _green]),
        PaletteInfo('Endesga 32', [_blue, _red, _green]),
      ],
    );

Future<void> _paletteMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert).first);
  await settleOpen(tester);
}

/// Opens the actions sheet of the first palette and taps the row with [icon].
Future<void> _paletteAction(WidgetTester tester, IconData icon) async {
  await _paletteMenu(tester);
  final f = find.byIcon(icon).last;
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(f);
}

void main() {
  // "Blank" is fixture text too, but it is also a plain English word the sweeps would flag.
  const names = [..._fixture, 'Blank'];

  // ---- Palettes page ----
  sweepScreen('Palettes page', build: _palettes, allowLatin: names);
  sweepScreen('Palettes page, palette actions', build: _palettes, allowLatin: names, act: _paletteMenu);
  sweepScreen('Palettes page, add menu', build: _palettes, allowLatin: names, act: (tester) async {
    await tester.tap(find.byIcon(Icons.add));
  });
  sweepScreen('Palettes page, rename dialog', build: _palettes, allowLatin: names,
      act: (tester) => _paletteAction(tester, Icons.edit));
  sweepScreen('Palettes page, sort dialog', build: _palettes, allowLatin: names,
      act: (tester) => _paletteAction(tester, Icons.sort));
  sweepScreen('Palettes page, clear dialog', build: _palettes, allowLatin: names,
      act: (tester) => _paletteAction(tester, Icons.format_color_reset));
  sweepScreen('Palettes page, palette limit toast', allowLatin: names, build: () {
    final host = FakePaletteHost([for (var i = 0; i < kMaxPalettes; i++) const PaletteInfo('Default', [_red])]);
    return PalettePage(host: host, presetLoader: () async => const []);
  }, act: (tester) async {
    await tester.tap(find.byIcon(Icons.add));
    await settleOpen(tester);
    await tester.tap(find.byIcon(Icons.add_box_outlined));
  }, drain: const Duration(seconds: 3));

  // ---- Artwork colors page ----
  sweepScreen('Artwork colors, extracting',
      build: () => ArtworkColorsPage(host: FakePaletteHost(const [], extract: () => Completer<String>().future)));
  sweepScreen('Artwork colors, ready, with a pending edit', build: () => ArtworkColorsPage(host: _host(pending: true)));
  sweepScreen('Artwork colors, color sheet', build: () => ArtworkColorsPage(host: _host()), act: (tester) async {
    await tester.tap(find.byType(GestureDetector).first);
  });
  sweepScreen('Artwork colors, too many colors',
      build: () => ArtworkColorsPage(host: _host(used: '{"colors":[],"over_limit":true}')));
  sweepScreen('Artwork colors, blank artwork', build: () => ArtworkColorsPage(host: _host(used: '{"colors":[]}')));
  sweepScreen('Artwork colors, failed',
      build: () => ArtworkColorsPage(host: FakePaletteHost(const [], extract: () => Future.error('x'))));
  sweepScreen('Artwork colors, full palette toast', build: () {
    final host = FakePaletteHost(
      [PaletteInfo('Default', [for (var i = 0; i < kMaxPaletteColors; i++) Color(0xFF000000 | (i + 1))])],
      usedColors: '{"colors":["#FF0000FF"]}',
    );
    return ArtworkColorsPage(host: host);
  }, act: (tester) async {
    await tester.tap(find.byType(GestureDetector).first);
    await settleOpen(tester);
    await tester.tap(find.byIcon(Icons.add));
  }, drain: const Duration(seconds: 3));

  // ---- color dialog ----
  sweepScreen(
    'Color dialog, with sources',
    build: () => Opener((context, ref) => showDialog<Color>(
          context: context,
          builder: (_) => const ColorPickerDialog(
            initial: _red,
            primary: _green,
            previous: _blue,
            palette: [_red, _green, _blue],
          ),
        )),
    act: tapOpener,
    drain: const Duration(seconds: 1),
  );

  // ---- Patterns and Dither pages ----
  for (final tool in const ['Pencil', 'Bucket']) {
    sweepScreen(
      'Patterns page, $tool',
      build: () => Builder(
        builder: (context) => PatternsPage(
          // As the editor does: the tool's name in the current language.
          toolName: toolName(context.l10n, tool),
          current: bayerTile(4, 8),
          on: true,
          recents: [bayerTile(4, 8), PatternTile.parse('7,3,1')!],
        ),
      ),
    );
  }
  sweepScreen('Patterns page, end', build: () => const PatternsPage(toolName: ''), act: (tester) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
  });
  sweepScreen('Dither page', build: () => const PatternsPage.gradient(dither: DitherKind.bayer4));
  sweepScreen('Dither page, end', build: () => const PatternsPage.gradient(dither: DitherKind.ign),
      act: (tester) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
  });
}
