import 'package:flutter/material.dart';

class ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const ColorPickerDialog({super.key, required this.initial});
  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late double r, g, b, a;
  bool hsvMode = false;
  late double h, s, v;

  @override
  void initState() {
    super.initState();
    r = widget.initial.red.toDouble();
    g = widget.initial.green.toDouble();
    b = widget.initial.blue.toDouble();
    a = widget.initial.alpha.toDouble();
    final hsvC = HSVColor.fromColor(widget.initial);
    h = hsvC.hue;
    s = hsvC.saturation;
    v = hsvC.value;
  }

  Color get _color => hsvMode
      ? HSVColor.fromAHSV(a / 255, h, s, v).toColor()
      : Color.fromARGB(a.round(), r.round(), g.round(), b.round());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Text('Pick color'),
        const Spacer(),
        ToggleButtons(
          isSelected: [!hsvMode, hsvMode],
          onPressed: (i) => setState(() => hsvMode = i == 1),
          constraints: const BoxConstraints(minHeight: 28, minWidth: 44),
          children: const [Text('RGB'), Text('HSV')],
        ),
      ]),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: 40, decoration: BoxDecoration(color: _color, border: Border.all(color: Colors.white24))),
          const SizedBox(height: 10),
          if (!hsvMode) ...[
            _chan('R', r, 255, Colors.red, (x) => setState(() => r = x)),
            _chan('G', g, 255, Colors.green, (x) => setState(() => g = x)),
            _chan('B', b, 255, Colors.blue, (x) => setState(() => b = x)),
          ] else ...[
            _chan('H', h, 360, Colors.purple, (x) => setState(() => h = x)),
            _chan('S', s * 100, 100, Colors.teal, (x) => setState(() => s = x / 100)),
            _chan('V', v * 100, 100, Colors.amber, (x) => setState(() => v = x / 100)),
          ],
          _chan('A', a, 255, Colors.grey, (x) => setState(() => a = x)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('OK')),
      ],
    );
  }

  Widget _chan(String name, double val, double max, Color color, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 18, child: Text(name)),
      Expanded(child: Slider(value: val.clamp(0, max), max: max, activeColor: color, onChanged: onChanged)),
      SizedBox(width: 36, child: Text(val.round().toString(), textAlign: TextAlign.right)),
    ]);
  }
}
