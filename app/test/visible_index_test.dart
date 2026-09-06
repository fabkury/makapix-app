import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/replay/journal_format.dart';
import 'package:makapix_club/editor/replay/visible_index.dart';

/// Build a FlatJournal from DSL lines. `bases[i]` opens a chapter right before action index i;
/// `deltas[i]` is the recorded `+ms` of line i (0 when omitted).
FlatJournal flatOf(List<String> lines, {Map<int, String> bases = const {}, List<int>? deltas}) {
  final sb = StringBuffer('$kJournalVersionHeader\n');
  var chapter = 0;
  for (var i = 0; i < lines.length; i++) {
    if (i == 0 || bases.containsKey(i)) {
      chapter++;
      final base = i == 0 ? null : bases[i];
      sb.writeln(chapterHeaderLine(chapter, DateTime.utc(2026), base, 'test'));
    }
    sb.writeln(actionLine(deltas == null ? 0 : deltas[i], lines[i]));
  }
  return FlatJournal.from(parseJournal(sb.toString())!);
}

void main() {
  group('visiblePositions (the visibility triage)', () {
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
        'SetAA(true)', // the ADR 0008 toggle is a setting, not a visible tick
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
  });

  group('FlatJournal deltas', () {
    test('per-line deltas ride along, chapter-relative as recorded', () {
      final flat = flatOf(['Tap(1,1)', 'Tap(2,2)', 'Tap(3,3)'],
          deltas: [1234, 16, 2000], bases: {2: 'chapter-0002.mkpx'});
      expect(flat.deltasMs, [1234, 16, 2000]);
      expect(flat.deltasMs.length, flat.actions.length);
    });

    test('a month-long pause saturates at the Int32 maximum instead of wrapping', () {
      final parsed = parseJournal('$kJournalVersionHeader\n'
          '${chapterHeaderLine(1, DateTime.utc(2026), null, 'fresh')}\n'
          '+99999999999 Tap(1,1)\n');
      final flat = FlatJournal.from(parsed!);
      expect(flat.deltasMs.single, 0x7FFFFFFF);
    });
  });

  group('buildTimeline — tick classes', () {
    test('contact steps are stream ticks; everything else visible is an event', () {
      final tl = buildTimeline(flatOf([
        'SelectTool(Pencil)', // 1
        'PointerDown(1,1)', // 2 stream (first dab)
        'PointerMove(2,2)', // 3 stream
        'PointerUp()', // 4 -
        'Tap(5,5)', // 5 stream (a pencil dot is one dab)
        'SelectTool(Bucket)', // 6
        'Tap(3,3)', // 7 EVENT (a fill is a whole region)
        'PointerDown(4,4)', // 8 EVENT (fills on contact)
        'SelectTool(Line)', // 9
        'PointerDown(0,0)', // 10 -
        'PointerUp()', // 11 EVENT (rasterizes)
        'Undo()', // 12 EVENT
        'ApplyLevels()', // 13 EVENT
      ]));
      expect(tl.positions, [2, 3, 5, 7, 8, 11, 12, 13]);
      expect(tl.isEvent, [0, 0, 0, 1, 1, 1, 1, 1]);
    });

    test('the precision pen and cursor plots/sprays are stream steps; FillCursor is an event', () {
      final tl = buildTimeline(flatOf([
        'CursorPenDown()', // 1 stream
        'MoveCursor(1,0)', // 2 stream
        'CursorPenUp()', // 3 -
        'PlotCursor()', // 4 stream
        'AirbrushCursor()', // 5 stream
        'FillCursor()', // 6 EVENT
      ]));
      expect(tl.positions, [1, 2, 4, 5, 6]);
      expect(tl.isEvent, [0, 0, 0, 0, 1]);
    });

    test('a line mixing a stroke step and an apply is an event', () {
      final tl = buildTimeline(flatOf(['PointerMove(1,1); ApplyLevels()']));
      expect(tl.isEvent, [1]);
    });

    test('a chapter-base pop is an event', () {
      final tl = buildTimeline(flatOf(
        ['Tap(1,1)', 'SetSeed(7)', 'SetBrushSize(2)'],
        bases: {1: 'chapter-0002.mkpx'},
      ));
      expect(tl.positions, [1, 2, 3]);
      expect(tl.isEvent, [0, 1, 0]);
    });

    test('the always-kept final position is a stream tick (nothing changes there)', () {
      final tl = buildTimeline(flatOf(['ApplyLevels()', 'SetBrushSize(2)'], deltas: [0, 700]));
      expect(tl.positions, [1, 2]);
      expect(tl.isEvent, [1, 0]);
      expect(tl.workMs, [0, 700], reason: 'the trailing churn\'s time extends the last state');
    });

    test('an empty journal yields an empty timeline', () {
      final tl = buildTimeline(flatOf([]));
      expect(tl.isEmpty, isTrue);
      expect(visiblePositions(flatOf([])), isEmpty);
    });
  });

  group('buildTimeline — working time', () {
    test('invisible lines flow into the next tick; each gap clamps at 2 s', () {
      final tl = buildTimeline(flatOf(
        [
          'SelectTool(Rectangle)', // +500  1 invisible
          'ShapeSet(1,1,5,5)', // +9000 2 invisible (a pause: clamped to 2000)
          'ShapeSet(1,1,6,6)', // +40   3 invisible
          'ShapeCommit()', // +60   4 EVENT: 500 + 2000 + 40 + 60
          'SetBrushSize(3)', // +100  5 invisible → final kept
        ],
        deltas: [500, 9000, 40, 60, 100],
      ));
      expect(tl.positions, [4, 5]);
      expect(tl.workMs, [2600, 100]);
    });

    test('a stroke keeps its own rhythm: each move accrues its delta', () {
      final tl = buildTimeline(flatOf(
        ['SelectTool(Pencil)', 'PointerDown(1,1)', 'PointerMove(2,2)', 'PointerMove(3,3)', 'PointerUp()'],
        deltas: [0, 1500, 11, 12, 9],
      ));
      expect(tl.positions, [2, 3, 4, 5]);
      expect(tl.workMs, [1500, 11, 12, 9], reason: 'the pre-stroke pause lands on the first dab');
    });

    test('the clamp is a parameter (tests and future tuning)', () {
      final tl = buildTimeline(flatOf(['Tap(1,1)'], deltas: [5000]), gapCapMs: 1000);
      expect(tl.workMs, [1000]);
    });

    test('a resume days later is one clamped beat, not a freeze', () {
      final tl = buildTimeline(flatOf(['Tap(1,1)', 'Tap(2,2)'], deltas: [10, 0x7FFFFFFF]));
      expect(tl.workMs, [10, kGapCapMs]);
    });
  });

  group('buildTimeline — the burst rule', () {
    test('repeats of one event verb inside 300 ms are paced as stream steps', () {
      final tl = buildTimeline(flatOf(
        [
          'SelectTool(Move)', // 1
          'NudgeMove(1,0)', // 2 EVENT (the run\'s first)
          'NudgeMove(1,0)', // 3 +50 → stream
          'NudgeMove(1,0)', // 4 +50 → stream
          'NudgeMove(1,0)', // 5 +50 → stream
          'NudgeMove(0,1)', // 6 +600 → EVENT again (outside the window)
          'Undo()', // 7 +50 → EVENT (a different verb never bursts)
          'Undo()', // 8 +50 → stream (an undo storm flows)
        ],
        deltas: [0, 400, 50, 50, 50, 600, 50, 50],
      ));
      expect(tl.positions, [2, 3, 4, 5, 6, 7, 8]);
      expect(tl.isEvent, [1, 0, 0, 0, 1, 1, 0]);
    });

    test('a stream tick between repeats resets the run', () {
      final tl = buildTimeline(flatOf(
        ['Undo()', 'PointerDown(1,1)', 'Undo()'],
        deltas: [0, 50, 50],
      ));
      expect(tl.isEvent, [1, 0, 1]);
    });

    test('frame hops scrubbed on the film roll flow; a deliberate hop is an event', () {
      final tl = buildTimeline(flatOf(
        ['SetActiveFrame(1)', 'SetActiveFrame(2)', 'SetActiveFrame(3)', 'SetActiveFrame(0)'],
        deltas: [0, 80, 80, 2500],
      ));
      expect(tl.isEvent, [1, 0, 0, 1]);
    });
  });
}
