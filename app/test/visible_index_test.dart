import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/replay/journal_format.dart';
import 'package:makapix_club/editor/replay/visible_index.dart';

FlatJournal flatOf(List<String> lines, {Map<int, String> bases = const {}}) {
  final sb = StringBuffer('$kJournalVersionHeader\n');
  // Build chapters so that bases[i] opens a chapter right before action index i.
  var chapter = 0;
  for (var i = 0; i < lines.length; i++) {
    if (i == 0 || bases.containsKey(i)) {
      chapter++;
      final base = i == 0 ? null : bases[i];
      sb.writeln(chapterHeaderLine(chapter, DateTime.utc(2026), base, 'test'));
    }
    sb.writeln(actionLine(0, lines[i]));
  }
  return FlatJournal.from(parseJournal(sb.toString())!);
}

void main() {
  test('draft fiddling is invisible; the commit is the visible tick', () {
    final v = visiblePositions(flatOf([
      'SelectTool(Rectangle)', // 1 invisible
      'ShapeSet(1,1,10,10)', // 2 invisible
      'ShapeSet(1,1,11,10)', // 3 invisible (the fiddling the user noticed)
      'SetShapeRotation(200)', // 4 invisible
      'ShapeSet(2,2,11,11)', // 5 invisible
      'ShapeCommit()', // 6 VISIBLE
      'SetPrimaryColor(#FF0000FF)', // 7 invisible (but final position is always kept)
    ]));
    expect(v, [6, 7], reason: 'commit + the always-kept final position');
  });

  test('pointer strokes are visible for stamp tools, not for selection tools', () {
    final v = visiblePositions(flatOf([
      'SelectTool(Pencil)', // 1
      'PointerDown(3,3)', // 2 VISIBLE (stamps)
      'PointerMove(4,4)', // 3 VISIBLE
      'PointerUp()', // 4 invisible (stamp already landed)
      'SelectTool(SelectRect)', // 5
      'PointerDown(0,0)', // 6 invisible (mask only)
      'PointerMove(9,9)', // 7 invisible
      'PointerUp()', // 8 invisible → but final position kept
    ]));
    expect(v, [2, 3, 8]);
  });

  test('shape-tool gestures rasterize on PointerUp (the Stroke script path)', () {
    final v = visiblePositions(flatOf([
      'SelectTool(Line)', // 1
      'PointerDown(0,0)', // 2 invisible (draft)
      'PointerMove(9,9)', // 3 invisible
      'PointerUp()', // 4 VISIBLE (rasterizes)
    ]));
    expect(v, [4]);
  });

  test('multi-statement lines are visible when ANY statement is', () {
    final v = visiblePositions(flatOf([
      'SetHsvShift(-40, 0.2, 0.0); ApplyHsvShift()', // VISIBLE via the apply
      'SetBrushSize(3); SetBrushShape(Round)', // invisible → final kept
    ]));
    expect(v, [1, 2]);
  });

  test('tool tracking follows SelectTool across statements and NewDocument resets', () {
    final v = visiblePositions(flatOf([
      'SelectTool(Eyedropper)', // 1
      'Tap(3,3)', // 2 invisible (eyedrop)
      'NewDocument(32,32)', // 3 VISIBLE + resets tool to Pencil
      'Tap(4,4)', // 4 VISIBLE (pencil stamps)
    ]));
    expect(v, [3, 4]);
  });

  test('precision pen: MoveCursor paints only while held', () {
    final v = visiblePositions(flatOf([
      'SetCursor(5,5)', // 1 invisible
      'MoveCursor(1,0)', // 2 invisible (pen up)
      'CursorPenDown()', // 3 VISIBLE (stamps the first pixel)
      'MoveCursor(1,0)', // 4 VISIBLE (paints)
      'CursorPenUp()', // 5 invisible
      'MoveCursor(1,0)', // 6 invisible → final kept
    ]));
    expect(v, [3, 4, 6]);
  });

  test('playback-preview chatter and settings bursts are skipped', () {
    final lines = [
      'SelectTool(Pencil)',
      for (var i = 0; i < 30; i++) 'AdvanceClock(33)',
      'SetThreshold(32); SetContiguous(true); SetAlphaCutoff(8)',
      'Tap(2,2)', // the only real change
    ];
    final v = visiblePositions(flatOf(lines));
    expect(v, [lines.length]);
  });

  test('a chapter boundary (base load) is a visible tick', () {
    final v = visiblePositions(flatOf(
      [
        'SelectTool(Pencil)', // 1, chapter 1
        'Tap(2,2)', // 2 VISIBLE
        'SetSeed(7)', // 3, chapter 2 opens here (import base pops in) → position 3 VISIBLE
        'SetBrushSize(2)', // 4 invisible → final kept
      ],
      bases: {2: 'chapter-0002.mkpx'},
    ));
    expect(v, [2, 3, 4]);
  });

  test('unknown verbs default to visible (the safe direction)', () {
    final v = visiblePositions(flatOf(['FutureMagicVerb(1,2,3)', 'SetBrushSize(2)']));
    expect(v.first, 1);
  });

  test('selection-mask and palette work is invisible', () {
    final v = visiblePositions(flatOf([
      'SelectAll()',
      'InvertSelection()',
      'MoveSelection(2,0)',
      'NewPalette()',
      'EditPaletteColor(0, #112233FF)',
      'SelectNone()',
      'FillSelection()', // VISIBLE (paints pixels)
    ]));
    expect(v, [7]);
  });
}
