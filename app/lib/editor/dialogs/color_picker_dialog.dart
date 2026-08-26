import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/layout.dart';
import '../widgets/painters.dart';

// Picker-area geometry. The square takes whatever width fits beside the fixed-width hue
// ramp, capped at the historical 246 (the 280-wide desktop content) and floored so a
// degenerate window still shows something grabbable. Sizing is MediaQuery-driven and
// computed in build(): AlertDialog wraps its content in IntrinsicWidth, so a
// LayoutBuilder there would throw, while a tight SizedBox answers intrinsics without
// consulting its child.
const double _kHueW = 26, _kGap = 8;
const double _kMaxSq = 246, _kMinSq = 96;
// Both painters deliberately draw their markers past the paint bounds (the SV ring is
// r=7 with a 3px stroke at a clamped center; the hue marker overhangs 1px per side).
// The scrollable clips its content once it overflows (landscape, or the keyboard up),
// so the picker area keeps this much slack on the clipped sides — never clip the
// markers away instead.
const double _kMarkerSlack = 9;
// Landscape: the picker area sits left, the fields and buttons in a fixed-width pane
// on the right, so a landscape phone (which has no height for the stacked layout)
// keeps every control on screen.
const double _kFieldsPaneW = 220, _kPaneGap = 12;
// Pinned on the AlertDialog so the width math and the dialog can never disagree, no
// matter what Material's defaults do.
const EdgeInsets _kInsetPadding = EdgeInsets.symmetric(horizontal: 40, vertical: 24);
const EdgeInsets _kContentPadPortrait = EdgeInsets.fromLTRB(24, 20, 24, 24);
const EdgeInsets _kContentPadLandscape = EdgeInsets.fromLTRB(16, 16, 16, 12);

// Which trio of numeric fields is shown; the choice is a lasting user preference.
const String kColorPickerModePref = 'editor.colorPickerMode_v1';

enum _ColorFieldMode { rgb, hsv }

/// The traditional square+hue color picker: a Saturation×Value square with a hue ramp beside it,
/// an alpha slider, and a hex field. Dragging on the square or ramp updates the color live.
class ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const ColorPickerDialog({super.key, required this.initial});
  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  double h = 0, s = 0, v = 0, a = 255;
  _ColorFieldMode _mode = _ColorFieldMode.rgb;
  late final TextEditingController _hexCtrl,
      _rCtrl,
      _gCtrl,
      _bCtrl,
      _hCtrl,
      _sCtrl,
      _vCtrl,
      _aCtrl;

  @override
  void initState() {
    super.initState();
    final c = HSVColor.fromColor(widget.initial);
    h = c.hue;
    s = c.saturation;
    v = c.value;
    a = (widget.initial.a * 255).round().toDouble();
    _hexCtrl = TextEditingController();
    _rCtrl = TextEditingController();
    _gCtrl = TextEditingController();
    _bCtrl = TextEditingController();
    _hCtrl = TextEditingController();
    _sCtrl = TextEditingController();
    _vCtrl = TextEditingController();
    _aCtrl = TextEditingController();
    _syncFromColor();
    _loadModePref();
  }

  // The RGB/HSV choice is a lasting preference, not per-dialog state. Worst case for
  // the async load is one frame of the RGB default before a stored HSV arrives.
  Future<void> _loadModePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(kColorPickerModePref) == _ColorFieldMode.hsv.name &&
          mounted) {
        setState(() => _mode = _ColorFieldMode.hsv);
      }
    } catch (_) {
      // No prefs (or a bad value): keep the RGB default.
    }
  }

  void _setMode(_ColorFieldMode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    unawaited(
      SharedPreferences.getInstance()
          .then((p) => p.setString(kColorPickerModePref, m.name))
          .catchError((_) => true),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _hexCtrl,
      _rCtrl,
      _gCtrl,
      _bCtrl,
      _hCtrl,
      _sCtrl,
      _vCtrl,
      _aCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Color get _color => HSVColor.fromAHSV(a / 255, h, s, v).toColor();

  String get _hex {
    final c = _color;
    String two(int x) => x.toRadixString(16).padLeft(2, '0');
    final base = '${two((c.r * 255).round())}${two((c.g * 255).round())}${two((c.b * 255).round())}';
    return (a.round() < 255 ? '$base${two(a.round())}' : base).toUpperCase();
  }

  // Push the current color into every text field. `skip*` leaves the group the user is actively
  // typing in untouched, so the caret doesn't jump while editing it.
  void _syncFromColor({bool skipRgb = false, bool skipHsv = false, bool skipAlpha = false}) {
    _hexCtrl.text = _hex;
    if (!skipRgb) {
      final c = _color;
      _rCtrl.text = (c.r * 255).round().toString();
      _gCtrl.text = (c.g * 255).round().toString();
      _bCtrl.text = (c.b * 255).round().toString();
    }
    if (!skipHsv) {
      _hCtrl.text = h.round().toString();
      _sCtrl.text = (s * 100).round().toString();
      _vCtrl.text = (v * 100).round().toString();
    }
    if (!skipAlpha) _aCtrl.text = a.round().toString();
  }

  // Apply the alpha field (0–255). A blank/invalid value is ignored.
  void _applyAlpha() {
    final v = int.tryParse(_aCtrl.text.trim());
    if (v == null) return;
    setState(() => a = v.clamp(0, 255).toDouble());
    _syncFromColor(skipAlpha: true);
  }

  // Apply the R/G/B fields (0–255 each) as the color. A blank/invalid field keeps its channel.
  void _applyRgb() {
    final cur = _color;
    int chan(TextEditingController ctrl, double curChannel) =>
        (int.tryParse(ctrl.text.trim()) ?? (curChannel * 255).round())
            .clamp(0, 255)
            .toInt();
    final hsv = HSVColor.fromColor(
      Color.fromARGB(
        255,
        chan(_rCtrl, cur.r),
        chan(_gCtrl, cur.g),
        chan(_bCtrl, cur.b),
      ),
    );
    setState(() {
      h = hsv.hue;
      s = hsv.saturation;
      v = hsv.value;
    });
    _syncFromColor(skipRgb: true);
  }

  // Apply the H (0–360) / S (0–100) / V (0–100) fields as the color.
  void _applyHsv() {
    final hh = double.tryParse(_hCtrl.text.trim());
    final ss = double.tryParse(_sCtrl.text.trim());
    final vv = double.tryParse(_vCtrl.text.trim());
    setState(() {
      if (hh != null) h = hh.clamp(0.0, 360.0).toDouble();
      if (ss != null) s = (ss / 100).clamp(0.0, 1.0).toDouble();
      if (vv != null) v = (vv / 100).clamp(0.0, 1.0).toDouble();
    });
    _syncFromColor(skipHsv: true);
  }

  // iOS's plain number pad has no return key AT ALL, so the on-screen keyboard could
  // only be dismissed by closing the whole dialog. signed:true selects the
  // numbers-and-punctuation keyboard, which has one (labeled Done via
  // textInputAction). Android's number pad already has an enter key — keep it bare.
  TextInputType get _numKeyboard =>
      Theme.of(context).platform == TargetPlatform.iOS
          ? const TextInputType.numberWithOptions(signed: true)
          : TextInputType.number;

  void _unfocus() => FocusManager.instance.primaryFocus?.unfocus();

  // A compact integer field for the RGB / HSV rows.
  Widget _numField(
    String label,
    TextEditingController ctrl,
    void Function() apply,
  ) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextField(
        controller: ctrl,
        keyboardType: _numKeyboard,
        textInputAction: TextInputAction.done,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 8,
          ),
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => apply(),
      ),
    ),
  );

  // Live update from a drag/tap on the saturation×value square.
  void _onSv(Offset local, Size size) {
    _unfocus(); // touching the picker area means the user is done typing
    setState(() {
      s = (local.dx / size.width).clamp(0.0, 1.0);
      v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    });
    _syncFromColor();
  }

  // Live update from a drag/tap on the hue ramp.
  void _onHue(Offset local, double height) {
    _unfocus(); // touching the picker area means the user is done typing
    setState(() => h = (local.dy / height * 360).clamp(0.0, 359.999));
    _syncFromColor();
  }

  void _applyHex(String text) {
    final t = text.trim().replaceAll('#', '');
    if (t.length == 6 || t.length == 8) {
      int? p(int i) => int.tryParse(t.substring(i, i + 2), radix: 16);
      final r = p(0), g = p(2), b = p(4);
      if (r != null && g != null && b != null) {
        final al = t.length == 8 ? (p(6) ?? 255) : 255;
        final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
        setState(() {
          h = hsv.hue;
          s = hsv.saturation;
          v = hsv.value;
          a = al.toDouble();
        });
      }
    }
    _syncFromColor();
  }

  // The saturation×value square.
  //
  // Per-AXIS drag recognizers, NOT pan: inside the SingleChildScrollView,
  // a pan recognizer loses vertical drags to the scrollable's own
  // vertical-drag recognizer — and iOS's bouncing physics accepts drags
  // even when the content fits (rubber-band), which made the picker
  // nearly ungrabbable on iPhones while Android's clamping physics
  // (refusing drags at zero extent) masked the bug. An innermost
  // same-axis recognizer wins the arena (the nested-scrollable rule).
  // Every update handler reads the full 2-D localPosition, so whichever
  // axis claims the gesture, the color still tracks both axes.
  Widget _buildSvSquare(double sq) => SizedBox(
    width: sq,
    height: sq,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragDown: (d) => _onSv(d.localPosition, Size(sq, sq)),
      onVerticalDragUpdate: (d) => _onSv(d.localPosition, Size(sq, sq)),
      onHorizontalDragUpdate: (d) => _onSv(d.localPosition, Size(sq, sq)),
      child: CustomPaint(
        key: const Key('pickerSvSquare'),
        painter: _SvPainter(h, s, v),
        size: Size(sq, sq),
      ),
    ),
  );

  // The hue ramp. Same recognizer set as the square: the horizontal recognizer never
  // competes with the (vertical) scrollable, and it keeps a sideways-starting drag
  // tracking the hue instead of going to nobody.
  Widget _buildHueRamp(double sq) => SizedBox(
    width: _kHueW,
    height: sq,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragDown: (d) => _onHue(d.localPosition, sq),
      onVerticalDragUpdate: (d) => _onHue(d.localPosition, sq),
      onHorizontalDragUpdate: (d) => _onHue(d.localPosition, sq),
      child: CustomPaint(
        key: const Key('pickerHueRamp'),
        painter: _HuePainter(h),
        size: Size(_kHueW, sq),
      ),
    ),
  );

  Widget _buildPickerArea(double sq) => Row(
    children: [
      _buildSvSquare(sq),
      const SizedBox(width: _kGap),
      _buildHueRamp(sq),
    ],
  );

  Widget _buildAlphaRow() => Row(
    children: [
      const SizedBox(width: 16, child: Text('A')),
      Expanded(
        child: Slider(
          value: a.clamp(0, 255),
          max: 255,
          onChanged: (x) {
            setState(() => a = x);
            _syncFromColor();
          },
        ),
      ),
      SizedBox(
        width: 48,
        child: TextField(
          controller: _aCtrl,
          keyboardType: _numKeyboard,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          ),
          onChanged: (_) => _applyAlpha(),
        ),
      ),
    ],
  );

  Widget _buildHexRow() => Row(
    children: [
      const Text('#'),
      const SizedBox(width: 6),
      Expanded(
        child: TextField(
          controller: _hexCtrl,
          // [G-46] Losing focus applies too, so tapping OK straight from the field keeps the
          // typed value instead of silently discarding it. Unparseable text is still ignored.
          onTapOutside: (_) => _applyHex(_hexCtrl.text),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
          onSubmitted: _applyHex,
        ),
      ),
    ],
  );

  List<Widget> _dialogActions() => [
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Cancel'),
    ),
    FilledButton(
      // [G-46] Apply whatever is typed in the hex field before returning: pressing OK without
      // Enter used to discard it silently. Unparseable text leaves _color as it is.
      onPressed: () {
        _applyHex(_hexCtrl.text);
        Navigator.pop(context, _color);
      },
      child: const Text('OK'),
    ),
  ];

  // The dialog header: the name plus the live result swatch.
  Widget _buildHeader() => Row(
    children: [
      // Flexible, not Spacer-separated: on narrow phones the dialog can be tighter
      // than the title's natural width, and the text must yield rather than overflow.
      const Expanded(child: Text('Pick color', overflow: TextOverflow.ellipsis)),
      // Same dual indicator as the row-2 swatches: a translucent pick splits along the
      // anti-diagonal (opaque top-left / real alpha over the transparency checker
      // bottom-right), showing both its hue and how it will actually composite.
      AlphaSwatch(color: _color, width: 72, height: 24, diagonal: true),
    ],
  );

  Widget _buildModeChips() => Wrap(
    spacing: 6,
    children: [
      for (final m in _ColorFieldMode.values)
        ChoiceChip(
          label: Text(m.name.toUpperCase()),
          selected: _mode == m,
          selectedColor: const Color(0xFF30A050),
          visualDensity: VisualDensity.compact,
          onSelected: (_) => _setMode(m),
        ),
    ],
  );

  // One trio at a time; every controller stays alive and synced, so switching modes
  // shows the current color's values immediately.
  Widget _buildFieldsRow() => _mode == _ColorFieldMode.rgb
      ? Row(
          children: [
            _numField('R', _rCtrl, _applyRgb),
            _numField('G', _gCtrl, _applyRgb),
            _numField('B', _bCtrl, _applyRgb),
          ],
        )
      : Row(
          children: [
            _numField('H', _hCtrl, _applyHsv),
            _numField('S', _sCtrl, _applyHsv),
            _numField('V', _vCtrl, _applyHsv),
          ],
        );

  // The rows below the picker area, shared verbatim by both orientations.
  List<Widget> _buildFieldSection() => [
    _buildAlphaRow(),
    _buildHexRow(),
    const SizedBox(height: 8),
    _buildModeChips(),
    const SizedBox(height: 8),
    // Type RGB (0–255) or HSV (H 0–360, S/V 0–100) directly; updates the color live.
    _buildFieldsRow(),
  ];

  Widget _buildPortrait(Size size) {
    // Size the square to what actually fits: on narrow phones (iPhone 12: 390 logical
    // px wide) the dialog insets + content padding leave less than the historical 280,
    // and a fixed-width row overflows — overflow still paints but is NOT hit-testable,
    // which left the hue ramp's right side tap-dead on iOS.
    final availW =
        size.width - _kInsetPadding.horizontal - _kContentPadPortrait.horizontal;
    final sq = (availW - 2 * _kMarkerSlack - _kGap - _kHueW)
        .clamp(_kMinSq, _kMaxSq)
        .toDouble();
    return AlertDialog(
      insetPadding: _kInsetPadding,
      contentPadding: _kContentPadPortrait,
      title: _buildHeader(),
      content: SizedBox(
        width: sq + _kGap + _kHueW + 2 * _kMarkerSlack,
        // Scrollable so the dialog still works when the on-screen keyboard shrinks the space.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // No bottom slack: the spacer below is part of the scroll content, so the
              // markers can never be clipped on that side.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  _kMarkerSlack,
                  _kMarkerSlack,
                  _kMarkerSlack,
                  0,
                ),
                child: _buildPickerArea(sq),
              ),
              const SizedBox(height: 10),
              ..._buildFieldSection(),
            ],
          ),
        ),
      ),
      actions: _dialogActions(),
    );
  }

  Widget _buildLandscape(Size size, double availH) {
    final availW =
        size.width - _kInsetPadding.horizontal - _kContentPadLandscape.horizontal;
    final sq = math
        .min(availH, availW - _kHueW - _kGap - _kPaneGap - _kFieldsPaneW)
        .clamp(_kMinSq, _kMaxSq)
        .toDouble();
    // The right pane may be taller than the square, but never taller than the screen
    // allows — and there is no point growing past what the fields need.
    final contentH = math.max(sq, availH.clamp(150.0, 320.0)).toDouble();
    return AlertDialog(
      insetPadding: _kInsetPadding,
      contentPadding: _kContentPadLandscape,
      content: SizedBox(
        width: sq + _kGap + _kHueW + _kPaneGap + _kFieldsPaneW,
        height: contentH,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No scrollable ancestor on this side, so nothing can clip the marker
            // overhang — no slack padding needed.
            _buildPickerArea(sq),
            const SizedBox(width: _kPaneGap),
            Expanded(
              child: Column(
                children: [
                  DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.titleMedium,
                    child: _buildHeader(),
                  ),
                  const SizedBox(height: 8),
                  // Scrolls only when the keyboard shrinks the dialog. It holds nothing
                  // with custom drag recognizers, so the gesture arena stays clean.
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _buildFieldSection(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: _dialogActions(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // The height the landscape panes can really use: MediaQuery.size does not shrink
    // for the on-screen keyboard — the view insets carry it.
    final availH = size.height -
        MediaQuery.viewInsetsOf(context).bottom -
        _kInsetPadding.vertical -
        _kContentPadLandscape.vertical;
    // editorUsesLandscape is the app's single orientation rule. The height guard is not
    // a second one: a landscape phone with the keyboard up can leave too little height
    // for side-by-side panes, and the stacked scrollable layout is the one that still
    // works there.
    // Translucent, so it only receives taps nothing else claims: a tap on any
    // non-interactive part of the dialog dismisses the keyboard — which, on the iOS
    // number pad, has no key of its own to do that.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _unfocus,
      child: (editorUsesLandscape(size) && availH >= 150)
          ? _buildLandscape(size, availH)
          : _buildPortrait(size),
    );
  }
}

/// The saturation (x) × value (y) square for the current hue, with a ring at the current S,V.
class _SvPainter extends CustomPainter {
  final double h, s, v;
  _SvPainter(this.h, this.s, this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, h, 1, 1).toColor();
    // white → full-saturation hue (left→right), then transparent → black (top→bottom)
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hue],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final c = Offset(
      (s * size.width).clamp(0, size.width).toDouble(),
      ((1 - v) * size.height).clamp(0, size.height).toDouble(),
    );
    canvas.drawCircle(
      c,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      c,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SvPainter o) => o.h != h || o.s != s || o.v != v;
}

/// The vertical hue ramp (0–360°) with a marker at the current hue.
class _HuePainter extends CustomPainter {
  final double h;
  _HuePainter(this.h);

  static const _hues = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _hues,
        ).createShader(rect),
    );
    final y = (h / 360 * size.height).clamp(0, size.height).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(-1, y - 2, size.width + 2, 4),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HuePainter o) => o.h != h;
}
