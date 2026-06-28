import 'package:flutter/material.dart';

/// The traditional square+hue colour picker: a Saturation×Value square with a hue ramp beside it,
/// an alpha slider, and a hex field. Dragging on the square or ramp updates the colour live.
class ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const ColorPickerDialog({super.key, required this.initial});
  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  double h = 0, s = 0, v = 0, a = 255;
  late final TextEditingController _hexCtrl, _rCtrl, _gCtrl, _bCtrl, _hCtrl, _sCtrl, _vCtrl;

  @override
  void initState() {
    super.initState();
    final c = HSVColor.fromColor(widget.initial);
    h = c.hue;
    s = c.saturation;
    v = c.value;
    a = widget.initial.alpha.toDouble();
    _hexCtrl = TextEditingController();
    _rCtrl = TextEditingController();
    _gCtrl = TextEditingController();
    _bCtrl = TextEditingController();
    _hCtrl = TextEditingController();
    _sCtrl = TextEditingController();
    _vCtrl = TextEditingController();
    _syncFromColor();
  }

  @override
  void dispose() {
    for (final c in [_hexCtrl, _rCtrl, _gCtrl, _bCtrl, _hCtrl, _sCtrl, _vCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Color get _color => HSVColor.fromAHSV(a / 255, h, s, v).toColor();

  String get _hex {
    final c = _color;
    String two(int x) => x.toRadixString(16).padLeft(2, '0');
    final base = '${two(c.red)}${two(c.green)}${two(c.blue)}';
    return (a.round() < 255 ? '$base${two(a.round())}' : base).toUpperCase();
  }

  // Push the current colour into every text field. `skipRgb`/`skipHsv` leave the group the user is
  // actively typing in untouched, so the caret doesn't jump while editing it.
  void _syncFromColor({bool skipRgb = false, bool skipHsv = false}) {
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
  }

  // Apply the R/G/B fields (0–255 each) as the colour. A blank/invalid field keeps its channel.
  void _applyRgb() {
    final cur = _color;
    int chan(TextEditingController ctrl, double curChannel) =>
        (int.tryParse(ctrl.text.trim()) ?? (curChannel * 255).round()).clamp(0, 255).toInt();
    final hsv = HSVColor.fromColor(
        Color.fromARGB(255, chan(_rCtrl, cur.r), chan(_gCtrl, cur.g), chan(_bCtrl, cur.b)));
    setState(() {
      h = hsv.hue;
      s = hsv.saturation;
      v = hsv.value;
    });
    _syncFromColor(skipRgb: true);
  }

  // Apply the H (0–360) / S (0–100) / V (0–100) fields as the colour.
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

  // A compact integer field for the RGB / HSV rows.
  Widget _numField(String label, TextEditingController ctrl, void Function() apply) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => apply(),
          ),
        ),
      );

  // Live update from a drag/tap on the saturation×value square.
  void _onSv(Offset local, Size size) {
    setState(() {
      s = (local.dx / size.width).clamp(0.0, 1.0);
      v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    });
    _syncFromColor();
  }

  // Live update from a drag/tap on the hue ramp.
  void _onHue(Offset local, double height) {
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

  @override
  Widget build(BuildContext context) {
    const double sq = 200, hueW = 26;
    return AlertDialog(
      title: Row(children: [
        const Text('Pick color'),
        const Spacer(),
        Container(
          width: 40,
          height: 24,
          decoration: BoxDecoration(color: _color, border: Border.all(color: Colors.white24)),
        ),
      ]),
      content: SizedBox(
        width: 280,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            SizedBox(
              width: sq,
              height: sq,
              child: GestureDetector(
                onPanDown: (d) => _onSv(d.localPosition, const Size(sq, sq)),
                onPanUpdate: (d) => _onSv(d.localPosition, const Size(sq, sq)),
                child: CustomPaint(painter: _SvPainter(h, s, v), size: const Size(sq, sq)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: hueW,
              height: sq,
              child: GestureDetector(
                onPanDown: (d) => _onHue(d.localPosition, sq),
                onPanUpdate: (d) => _onHue(d.localPosition, sq),
                child: CustomPaint(painter: _HuePainter(h), size: const Size(hueW, sq)),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
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
            SizedBox(width: 32, child: Text(a.round().toString(), textAlign: TextAlign.right)),
          ]),
          Row(children: [
            const Text('#'),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _hexCtrl,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                textCapitalization: TextCapitalization.characters,
                onSubmitted: _applyHex,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Type RGB (0–255) or HSV (H 0–360, S/V 0–100) directly; updates the colour live.
          Row(children: [
            const SizedBox(width: 30, child: Text('RGB', style: TextStyle(fontSize: 12, color: Colors.white60))),
            _numField('R', _rCtrl, _applyRgb),
            _numField('G', _gCtrl, _applyRgb),
            _numField('B', _bCtrl, _applyRgb),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 30, child: Text('HSV', style: TextStyle(fontSize: 12, color: Colors.white60))),
            _numField('H', _hCtrl, _applyHsv),
            _numField('S', _sCtrl, _applyHsv),
            _numField('V', _vCtrl, _applyHsv),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('OK')),
      ],
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
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [Colors.white, hue]).createShader(rect));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final c = Offset((s * size.width).clamp(0, size.width).toDouble(), ((1 - v) * size.height).clamp(0, size.height).toDouble());
    canvas.drawCircle(c, 7, Paint()..style = PaintingStyle.stroke..color = Colors.black..strokeWidth = 3);
    canvas.drawCircle(c, 7, Paint()..style = PaintingStyle.stroke..color = Colors.white..strokeWidth = 1.5);
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
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _hues).createShader(rect),
    );
    final y = (h / 360 * size.height).clamp(0, size.height).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(-1, y - 2, size.width + 2, 4),
      Paint()..style = PaintingStyle.stroke..color = Colors.white..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HuePainter o) => o.h != h;
}
