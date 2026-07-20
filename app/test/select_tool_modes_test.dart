// The Select tool's three modes (Rect / Oval / Lasso): the mode → engine ToolKind mapping, and the
// catalogue after Lasso's demotion from a standalone row-3 tool to a Select-tool mode.
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/tools.dart';

void main() {
  group('selectShapeEngineTool', () {
    test('maps each Select mode to its engine ToolKind', () {
      expect(selectShapeEngineTool('Rectangle'), 'SelectRect');
      expect(selectShapeEngineTool('Ellipse'), 'SelectEllipse');
      expect(selectShapeEngineTool('Lasso'), 'SelectFree');
    });
  });

  group('tool catalogue', () {
    test('SelectFree is no longer a standalone tool; SelectShape hosts all three modes', () {
      expect(tools.any((t) => t.dsl == 'SelectFree'), isFalse);
      expect(tools.any((t) => t.dsl == 'SelectShape'), isTrue);
    });

    test('the SelectFree tooltip moved into the SelectShape tip', () {
      expect(toolTips.containsKey('SelectFree'), isFalse);
      expect(toolTips['SelectShape'], contains('Lasso'));
    });
  });
}
