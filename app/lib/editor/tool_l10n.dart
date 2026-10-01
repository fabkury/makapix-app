// Translated names of the editor tools, keyed by the tool's `face` (its DSL name, plus
// 'Repeat' for the Redo tile's alternate face). The DSL name itself is an engine identifier
// and is never shown; everything the artist reads comes from here.
//
// Two names per tool (docs/i18n/DESIGN.md §5):
//   * short — the row-3 tile label. The tile is 54 px wide at 8.5 px type, so each language's
//     short label is held to that width by test/l10n/tool_label_fit_test.dart.
//   * name  — the full name, for lists, tooltips, and anywhere with room.
// l10n-ignore-file: the string keys below are engine DSL tool names, not display text.
import 'package:makapix_club/l10n/l10n.dart';

typedef _Msg = String Function(AppLocalizations l);

const Map<String, (_Msg short, _Msg name)> _names = {
  'Pencil': (_pencilShort, _pencil),
  'Brush': (_brushShort, _brush),
  'Airbrush': (_airbrushShort, _airbrush),
  'Eraser': (_eraserShort, _eraser),
  'Bucket': (_fillShort, _fill),
  'Outline': (_outlineShort, _outline),
  'Gradient': (_gradientShort, _gradient),
  'Line': (_lineShort, _line),
  'Shape': (_shapeShort, _shape),
  'Ruler': (_rulerShort, _ruler),
  'Dodge': (_dodgeShort, _dodge),
  'Burn': (_burnShort, _burn),
  'Eyedropper': (_pickShort, _pick),
  'Move': (_moveShort, _move),
  'CopyPaste': (_copyPasteShort, _copyPaste),
  'SelectShape': (_selectShort, _select),
  'SelectByColor': (_selectByColorShort, _selectByColor),
  'SelectLayer': (_selectLayerShort, _selectLayer),
  'HsvShift': (_hsvShort, _hsv),
  'BrightnessContrast': (_brightnessShort, _brightness),
  'Levels': (_levelsShort, _levels),
  'Flip': (_flipShort, _flip),
  'Rotate': (_rotateShort, _rotate),
  'Resize': (_resizeShort, _resize),
  'Invert': (_invertShort, _invert),
  'PlayPause': (_playShort, _play),
  'Onion': (_onionShort, _onion),
  'Undo': (_undoShort, _undo),
  'Redo': (_redoShort, _redo),
  'Repeat': (_repeatShort, _repeat),
};

// Succinct, teach-as-you-go help shown in the gesture-safe band at the bottom. Keep each to two
// short lines: brief, professional, the core of the tool (not its nuances), no em dashes. Assume
// fluency with the draft/commit model: tips never teach or remind the user to Commit.
const Map<String, _Msg> _tips = {
  'Pencil': _tipPencil,
  'Brush': _tipBrush,
  'Airbrush': _tipAirbrush,
  'Eraser': _tipEraser,
  'Bucket': _tipBucket,
  'Outline': _tipOutline,
  'Gradient': _tipGradient,
  'Line': _tipLine,
  'Shape': _tipShape,
  'Ruler': _tipRuler,
  'Dodge': _tipDodge,
  'Burn': _tipBurn,
  'Eyedropper': _tipEyedropper,
  'Move': _tipMove,
  'CopyPaste': _tipCopyPaste,
  'SelectShape': _tipSelectShape,
  'SelectCircle': _tipSelectCircle,
  'SelectPoly': _tipSelectPoly,
  'SelectByColor': _tipSelectByColor,
  'SelectLayer': _tipSelectLayer,
  'HsvShift': _tipHsv,
  'BrightnessContrast': _tipBrightness,
  'Levels': _tipLevels,
  'Flip': _tipFlip,
  'Rotate': _tipRotate,
  'Resize': _tipResize,
  'Invert': _tipInvert,
  'PlayPause': _tipPlay,
};

String _tipPencil(AppLocalizations l) => l.tipPencil;
String _tipBrush(AppLocalizations l) => l.tipBrush;
String _tipAirbrush(AppLocalizations l) => l.tipAirbrush;
String _tipEraser(AppLocalizations l) => l.tipEraser;
String _tipBucket(AppLocalizations l) => l.tipBucket;
String _tipOutline(AppLocalizations l) => l.tipOutline;
String _tipGradient(AppLocalizations l) => l.tipGradient;
String _tipLine(AppLocalizations l) => l.tipLine;
String _tipShape(AppLocalizations l) => l.tipShape;
String _tipRuler(AppLocalizations l) => l.tipRuler;
String _tipDodge(AppLocalizations l) => l.tipDodge;
String _tipBurn(AppLocalizations l) => l.tipBurn;
String _tipEyedropper(AppLocalizations l) => l.tipEyedropper;
String _tipMove(AppLocalizations l) => l.tipMove;
String _tipCopyPaste(AppLocalizations l) => l.tipCopyPaste;
String _tipSelectShape(AppLocalizations l) => l.tipSelectShape;
String _tipSelectCircle(AppLocalizations l) => l.tipSelectCircle;
String _tipSelectPoly(AppLocalizations l) => l.tipSelectPoly;
String _tipSelectByColor(AppLocalizations l) => l.tipSelectByColor;
String _tipSelectLayer(AppLocalizations l) => l.tipSelectLayer;
String _tipHsv(AppLocalizations l) => l.tipHsv;
String _tipBrightness(AppLocalizations l) => l.tipBrightness;
String _tipLevels(AppLocalizations l) => l.tipLevels;
String _tipFlip(AppLocalizations l) => l.tipFlip;
String _tipRotate(AppLocalizations l) => l.tipRotate;
String _tipResize(AppLocalizations l) => l.tipResize;
String _tipInvert(AppLocalizations l) => l.tipInvert;
String _tipPlay(AppLocalizations l) => l.tipPlay;

/// The tools that have a help tip.
Iterable<String> get toolsWithTips => _tips.keys;

/// The help-band tip for the tool whose DSL name is [dsl]; empty for a tool without one.
String toolTip(AppLocalizations l, String dsl) => _tips[dsl]?.call(l) ?? '';

/// Every face that has a name — the tool catalog plus Undo / Redo / Repeat.
Iterable<String> get toolFaces => _names.keys;

/// The row-3 tile label for [face]. An unknown face (a tool added to the catalog without
/// names) shows its DSL name rather than crashing; tool_l10n_test.dart fails on it.
String toolShortLabel(AppLocalizations l, String face) => _names[face]?.$1(l) ?? face;

/// The full name for [face].
String toolName(AppLocalizations l, String face) => _names[face]?.$2(l) ?? face;

// Const maps cannot hold closures, so each message gets a top-level tear-off.
String _pencil(AppLocalizations l) => l.toolPencil;
String _pencilShort(AppLocalizations l) => l.toolPencilShort;
String _brush(AppLocalizations l) => l.toolBrush;
String _brushShort(AppLocalizations l) => l.toolBrushShort;
String _airbrush(AppLocalizations l) => l.toolAirbrush;
String _airbrushShort(AppLocalizations l) => l.toolAirbrushShort;
String _eraser(AppLocalizations l) => l.toolEraser;
String _eraserShort(AppLocalizations l) => l.toolEraserShort;
String _fill(AppLocalizations l) => l.toolFill;
String _fillShort(AppLocalizations l) => l.toolFillShort;
String _outline(AppLocalizations l) => l.toolOutline;
String _outlineShort(AppLocalizations l) => l.toolOutlineShort;
String _gradient(AppLocalizations l) => l.toolGradient;
String _gradientShort(AppLocalizations l) => l.toolGradientShort;
String _line(AppLocalizations l) => l.toolLine;
String _lineShort(AppLocalizations l) => l.toolLineShort;
String _shape(AppLocalizations l) => l.toolShape;
String _shapeShort(AppLocalizations l) => l.toolShapeShort;
String _ruler(AppLocalizations l) => l.toolRuler;
String _rulerShort(AppLocalizations l) => l.toolRulerShort;
String _dodge(AppLocalizations l) => l.toolDodge;
String _dodgeShort(AppLocalizations l) => l.toolDodgeShort;
String _burn(AppLocalizations l) => l.toolBurn;
String _burnShort(AppLocalizations l) => l.toolBurnShort;
String _pick(AppLocalizations l) => l.toolPick;
String _pickShort(AppLocalizations l) => l.toolPickShort;
String _move(AppLocalizations l) => l.toolMove;
String _moveShort(AppLocalizations l) => l.toolMoveShort;
String _copyPaste(AppLocalizations l) => l.toolCopyPaste;
String _copyPasteShort(AppLocalizations l) => l.toolCopyPasteShort;
String _select(AppLocalizations l) => l.toolSelect;
String _selectShort(AppLocalizations l) => l.toolSelectShort;
String _selectByColor(AppLocalizations l) => l.toolSelectByColor;
String _selectByColorShort(AppLocalizations l) => l.toolSelectByColorShort;
String _selectLayer(AppLocalizations l) => l.toolSelectLayer;
String _selectLayerShort(AppLocalizations l) => l.toolSelectLayerShort;
String _hsv(AppLocalizations l) => l.toolHsv;
String _hsvShort(AppLocalizations l) => l.toolHsvShort;
String _brightness(AppLocalizations l) => l.toolBrightness;
String _brightnessShort(AppLocalizations l) => l.toolBrightnessShort;
String _levels(AppLocalizations l) => l.toolLevels;
String _levelsShort(AppLocalizations l) => l.toolLevelsShort;
String _flip(AppLocalizations l) => l.toolFlip;
String _flipShort(AppLocalizations l) => l.toolFlipShort;
String _rotate(AppLocalizations l) => l.toolRotate;
String _rotateShort(AppLocalizations l) => l.toolRotateShort;
String _resize(AppLocalizations l) => l.toolResize;
String _resizeShort(AppLocalizations l) => l.toolResizeShort;
String _invert(AppLocalizations l) => l.toolInvert;
String _invertShort(AppLocalizations l) => l.toolInvertShort;
String _play(AppLocalizations l) => l.toolPlay;
String _playShort(AppLocalizations l) => l.toolPlayShort;
String _onion(AppLocalizations l) => l.toolOnion;
String _onionShort(AppLocalizations l) => l.toolOnionShort;
String _undo(AppLocalizations l) => l.toolUndo;
String _undoShort(AppLocalizations l) => l.toolUndoShort;
String _redo(AppLocalizations l) => l.toolRedo;
String _redoShort(AppLocalizations l) => l.toolRedoShort;
String _repeat(AppLocalizations l) => l.toolRepeat;
String _repeatShort(AppLocalizations l) => l.toolRepeatShort;
