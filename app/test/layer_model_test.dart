// The Layers page's pure model (layers/layer_model.dart, layers/layers_more_sheet.dart): the
// read model, the wire forms, the range entry (bottom = 1), the shift clamp, the selectors, the
// rename pattern, and the op → verb mapping. No widgets, no engine.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/layers/layer_model.dart';
import 'package:makapix_club/editor/layers/layers_more_sheet.dart';

void main() {
  group('parseLayerDetail', () {
    test('reads the active frame\'s layers with ids, state, blend, and tiles', () {
      final detail = [
        {'i': 0, 'id': 7, 'layers': []},
        {
          'i': 1,
          'id': 8,
          'layers': [
            {'id': 3, 'name': 'Sky', 'visible': true, 'locked': false, 'opacity': 255, 'present_tiles': 4},
            {'id': 9, 'name': 'Ink', 'visible': false, 'locked': true, 'opacity': 128, 'blend': 'Multiply', 'present_tiles': 0},
          ],
        },
      ];
      final rows = parseLayerDetail(detail, 1);
      expect(rows.map((r) => r.id), [3, 9]);
      expect(rows[0].blend, 'Normal');
      expect(rows[0].payloadBytes, 4 * 4096);
      expect(rows[0].isDefaultState, isTrue);
      expect(rows[1].blend, 'Multiply');
      expect(rows[1].isEmpty, isTrue);
      expect(rows[1].isDefaultState, isFalse);
      expect(parseLayerDetail(detail, 5), isEmpty);
      expect(parseLayerDetail(null, 0), isEmpty);
    });

    test('an entry without an id takes its index', () {
      final rows = parseLayerDetail([
        {
          'layers': [
            {'name': 'a'},
            {'name': 'b'}
          ]
        }
      ], 0);
      expect(rows.map((r) => r.id), [0, 1]);
    });
  });

  group('wire forms', () {
    test('formatLayerSet and layerSetDsl', () {
      expect(formatLayerSet([3, 1, 2, 5]), '1-3 5');
      expect(layerSetDsl('MergeLayers', [0, 1, 2]), 'MergeLayers(0-2)');
      expect(layerSetDsl('ShiftLayers', [4, 0], ['-1']), 'ShiftLayers(0 4, -1)');
      expect(formatLayerSetHuman([0, 1, 2, 7]), '1–3, 8');
    });

    test('range entry counts the bottom layer as 1', () {
      final r = parseLayerRangeEntry('1-2, 5', layerCount: 5);
      expect(r.indices, [0, 1, 4]);
      expect(parseLayerRangeEntry('3-1', layerCount: 5).indices, [0, 1, 2]);
      expect(parseLayerRangeEntry('6', layerCount: 5).error, contains('beyond the top layer'));
      expect(parseLayerRangeEntry('0', layerCount: 5).error, contains('start at 1'));
      expect(parseLayerRangeEntry('', layerCount: 5).error, isNotNull);
      expect(parseLayerRangeEntry('x', layerCount: 5).error, isNotNull);
    });
  });

  group('helpers', () {
    test('clampLayerShift, isContiguous, duplicate result indices', () {
      expect(clampLayerShift([1, 4], 10, 6), 1);
      expect(clampLayerShift([1, 4], -10, 6), -1);
      expect(clampLayerShift([0, 5], 1, 6), 0);
      expect(clampLayerShift([], 1, 6), 0);
      expect(isContiguous([2, 3, 4]), isTrue);
      expect(isContiguous([2, 4]), isFalse);
      expect(isContiguous([]), isFalse);
      expect(duplicateLayerResultIndices([0, 2]), [1, 4]);
    });

    test('lockedCount, retained bytes, cap', () {
      final rows = [
        const LayerRow(id: 1, name: 'a', locked: true, presentTiles: 2),
        const LayerRow(id: 2, name: 'b', presentTiles: 3),
      ];
      expect(lockedCount(rows, [0, 1]), 1);
      expect(retainedLayerPayloadBytes(rows, [0, 1]), 5 * 4096);
      expect(underLayerCap(kMaxLayers - 1, 1), isTrue);
      expect(underLayerCap(kMaxLayers - 1, 2), isFalse);
    });

    test('selectors', () {
      final rows = [
        const LayerRow(id: 1, name: 'a', presentTiles: 0),
        const LayerRow(id: 2, name: 'b', visible: false, presentTiles: 1),
        const LayerRow(id: 3, name: 'c', locked: true, opacity: 100, presentTiles: 1),
        const LayerRow(id: 4, name: 'd', blend: 'Screen', presentTiles: 1),
      ];
      expect(pickLayers(rows, LayerPick.empty), [0]);
      expect(pickLayers(rows, LayerPick.hidden), [1]);
      expect(pickLayers(rows, LayerPick.visible), [0, 2, 3]);
      expect(pickLayers(rows, LayerPick.locked), [2]);
      expect(pickLayers(rows, LayerPick.unlocked), [0, 1, 3]);
      expect(pickLayers(rows, LayerPick.nonNormal), [3]);
      expect(pickLayers(rows, LayerPick.translucent), [2]);
    });

    test('rename pattern numbers from the top', () {
      expect(renamePreview('Sketch {n}', 3), ['Sketch 1', 'Sketch 2', 'Sketch 3']);
      expect(renamePreview('Ink', 2), ['Ink', 'Ink']);
      expect(expandRenamePattern('{n}-{n}', 4), '4-4');
    });
  });

  group('dslForLayerOp', () {
    const idx = [0, 1, 2, 5];
    test('renders every op', () {
      expect(dslForLayerOp(const DuplicateLayersOp(), idx), 'DuplicateLayers(0-2 5)');
      expect(dslForLayerOp(const ToEdgeOp(top: true), idx, delta: 3), 'ShiftLayers(0-2 5, 3)');
      expect(dslForLayerOp(const ReverseLayersOp(), idx), 'ReverseLayers(0-2 5)');
      expect(dslForLayerOp(const InsertBlankLayersOp(above: true), idx), 'InsertBlankLayers(0-2 5, above)');
      expect(dslForLayerOp(const InsertBlankLayersOp(above: false), idx), 'InsertBlankLayers(0-2 5, below)');
      expect(dslForLayerOp(const SetVisibleOp(visible: false), idx), 'SetLayersVisible(0-2 5, 0)');
      expect(dslForLayerOp(const SetLockedOp(locked: true), idx), 'SetLayersLocked(0-2 5, 1)');
      expect(dslForLayerOp(const OpacityOp(), idx, opacity: 300), 'SetLayersOpacity(0-2 5, 255)');
      expect(dslForLayerOp(const BlendOp(), idx, blend: 'Screen'), 'SetLayersBlend(0-2 5, Screen)');
      expect(dslForLayerOp(const ResetLayersOp(), idx), 'ResetLayers(0-2 5)');
      expect(dslForLayerOp(const RenameLayersOp(), idx, name: 'Cel {n};\nx'), 'RenameLayers(0-2 5, Cel {n}  x)');
      expect(dslForLayerOp(const FlipLayersOp(horizontal: true), idx), 'FlipLayersH(0-2 5)');
      expect(dslForLayerOp(const FlipLayersOp(horizontal: false), idx), 'FlipLayersV(0-2 5)');
      expect(dslForLayerOp(const RotateLayersOp(2), idx), 'RotateLayers(0-2 5, 2)');
      expect(dslForLayerOp(const InvertLayersOp(), idx), 'InvertLayers(0-2 5)');
      expect(dslForLayerOp(const ClearLayersOp(), idx), 'ClearLayers(0-2 5)');
      expect(dslForLayerOp(const CopyToFramesOp(), idx, frames: [0, 1, 2, 4]), 'CopyLayersToFrames(0-2 5, 0-2 4)');
      expect(dslForLayerOp(const UseAsMoveGroupOp(), idx), 'SetActiveLayers(0-2 5)');
    });
    test('content classification', () {
      expect(layerOpChangesContent(const RotateLayersOp(1)), isTrue);
      expect(layerOpChangesContent(const ClearLayersOp()), isTrue);
      expect(layerOpChangesContent(const SetVisibleOp(visible: true)), isFalse);
      expect(layerOpRespectsLock(const FlipLayersOp(horizontal: true)), isTrue);
      expect(layerOpRespectsLock(const RenameLayersOp()), isFalse);
    });
  });
}
