// Shared creative-tool chrome: the compact row-1 control idiom (geared sliders with
// tap-to-type labels, toggle groups, mini buttons, swatch buttons) used by the Editor's
// three-row UI and the Animator's transport/option rows. Lifted verbatim from the editor's
// private `_EditorToolgrid` extension (2026-07-30) so both pillars share one visual grammar;
// zero behavior change. Everything here is stateless — helpers that open dialogs take the
// `BuildContext` explicitly.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:makapix_club/editor/widgets/painters.dart' show AlphaSwatch;

/// Tuning knob for the geared sliders: pixels of pointer travel per pixel of thumb travel.
/// 1.0 restores direct (ungeared) dragging; higher makes the sliders "heavier" and easier to
/// land on an exact number. Deliberately not user-configurable — adjust here on tester feedback.
const double kSliderGearRatio = 6.0;

/// Tuning knob for [labeledPowSlider]'s curve: 1.0 is linear, higher shifts ever more track
/// toward the low end (log-like). 2.0 (square-root positioning) is the middle-of-the-road choice.
const double kPowSliderGamma = 2.0;

Widget chromeSlider(double v, double min, double max, ValueChanged<double> onChanged) {
  return SizedBox(
    width: 120,
    child: GearedSlider(value: v, min: min, max: max, onChanged: onChanged),
  );
}

/// A row-1 slider with a tappable label: tapping the "Name value" label opens a numeric
/// text-entry dialog so the exact value can be typed instead of dragged. The text path and
/// the drag path share the same [onChanged], keeping behavior identical.
void labeledSlider(BuildContext context, List<Widget> children, String name, double value,
    double min, double max, ValueChanged<double> onChanged,
    {bool integer = true, int decimals = 1}) {
  final shown = integer ? value.round().toString() : value.toStringAsFixed(decimals);
  children.add(InkWell(
    onTap: () =>
        editSliderValue(context, name, value, min, max, onChanged, integer: integer, decimals: decimals),
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Text('$name $shown',
          style: const TextStyle(
              fontSize: 11,
              color: Colors.white60,
              decoration: TextDecoration.underline,
              decorationColor: Colors.white24)),
    ),
  ));
  children.add(chromeSlider(value, min, max, onChanged));
}

/// Like [labeledSlider], but the slider position is LOGARITHMIC across [min,max], so the geometric
/// midpoint (e.g. 1.0 for 0.2..5) sits at the center and each half spans the same ratio. The label
/// taps to type an exact value. `onChanged` receives the real value (not the slider position).
void labeledLogSlider(BuildContext context, List<Widget> children, String name, double value,
    double min, double max, ValueChanged<double> onChanged) {
  final v = value.clamp(min, max);
  final lmin = math.log(min), lmax = math.log(max);
  double posOf(double x) => (math.log(x) - lmin) / (lmax - lmin); // value → 0..1
  double valOf(double t) => math.exp(lmin + t * (lmax - lmin)); // 0..1 → value
  children.add(InkWell(
    onTap: () => editSliderValue(context, name, v, min, max, onChanged, integer: false),
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Text('$name ${v.toStringAsFixed(2)}',
          style: const TextStyle(
              fontSize: 11,
              color: Colors.white60,
              decoration: TextDecoration.underline,
              decorationColor: Colors.white24)),
    ),
  ));
  children.add(chromeSlider(posOf(v), 0, 1, (t) => onChanged(valOf(t))));
}

/// Like [labeledSlider], but the slider position follows a POWER curve across [min,max]
/// (value = min + (max−min)·t^γ with γ = [kPowSliderGamma]): the low end of the range gets more
/// track than linear without the full log treatment (for 1..400, the track center sits at ~100
/// vs linear's 200 and log's ~20). `onChanged` receives the real value (not the slider position).
void labeledPowSlider(BuildContext context, List<Widget> children, String name, double value,
    double min, double max, ValueChanged<double> onChanged,
    {bool integer = true}) {
  final v = value.clamp(min, max);
  double posOf(double x) => math.pow((x - min) / (max - min), 1 / kPowSliderGamma).toDouble();
  double valOf(double t) => min + (max - min) * math.pow(t, kPowSliderGamma);
  final shown = integer ? v.round().toString() : v.toStringAsFixed(1);
  children.add(InkWell(
    onTap: () => editSliderValue(context, name, v, min, max, onChanged, integer: integer),
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Text('$name $shown',
          style: const TextStyle(
              fontSize: 11,
              color: Colors.white60,
              decoration: TextDecoration.underline,
              decorationColor: Colors.white24)),
    ),
  ));
  children.add(chromeSlider(posOf(v), 0, 1, (t) => onChanged(valOf(t))));
}

Future<void> editSliderValue(BuildContext context, String name, double value, double min,
    double max, ValueChanged<double> onChanged,
    {required bool integer, int decimals = 1}) async {
  String fmt(double d) => integer ? d.round().toString() : d.toStringAsFixed(decimals);
  final ctrl =
      TextEditingController(text: integer ? value.round().toString() : value.toStringAsFixed(2));
  ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
  final entered = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(name),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: !integer, signed: min < 0),
        decoration: InputDecoration(labelText: 'Value (${fmt(min)} – ${fmt(max)})'),
        onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s.trim())),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
            child: const Text('OK')),
      ],
    ),
  );
  if (entered != null && entered.isFinite) {
    onChanged(entered.clamp(min, max).toDouble());
  }
}

Widget chromeToggle(List<String> opts, int sel, ValueChanged<int> onTap) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ToggleButtons(
      isSelected: List.generate(opts.length, (i) => i == sel),
      onPressed: onTap,
      constraints: const BoxConstraints(minHeight: 30, minWidth: 44),
      borderRadius: BorderRadius.circular(6),
      children: opts
          .map((o) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(o, style: const TextStyle(fontSize: 11))))
          .toList(),
    ),
  );
}

/// Icon variant of [chromeToggle] for options that read better as glyphs than words (e.g. the
/// brush Shape toggle's circle/square). Slimmer segments than the text toggle (36 vs 44
/// min-width); [tooltips] keeps the old wording reachable via long-press.
Widget chromeIconToggle(
    List<IconData> icons, List<String> tooltips, int sel, ValueChanged<int> onTap) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ToggleButtons(
      isSelected: List.generate(icons.length, (i) => i == sel),
      onPressed: onTap,
      constraints: const BoxConstraints(minHeight: 30, minWidth: 36),
      borderRadius: BorderRadius.circular(6),
      children: [
        for (var i = 0; i < icons.length; i++)
          Tooltip(message: tooltips[i], child: Icon(icons[i], size: 16)),
      ],
    ),
  );
}

/// [chromeIconToggle] for glyphs that aren't IconData — e.g. the Shape tool's custom-painted
/// kind glyphs, which redraw filled vs hollow to track the Fill/Outline mode.
Widget chromeGlyphToggle(List<Widget> glyphs, List<String> tooltips, int sel, ValueChanged<int> onTap) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ToggleButtons(
      isSelected: List.generate(glyphs.length, (i) => i == sel),
      onPressed: onTap,
      constraints: const BoxConstraints(minHeight: 30, minWidth: 36),
      borderRadius: BorderRadius.circular(6),
      children: [
        for (var i = 0; i < glyphs.length; i++) Tooltip(message: tooltips[i], child: glyphs[i]),
      ],
    ),
  );
}

Widget miniBtn(String s, VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        backgroundColor: const Color(0xFF2E3237),
      ),
      onPressed: onTap,
      child: Text(s, style: const TextStyle(fontSize: 11)),
    ),
  );
}

Widget swatchButton(Color c, VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: GestureDetector(
      onTap: onTap,
      child: AlphaSwatch(
          color: c, width: 30, height: 30, diagonal: true, borderRadius: 4, borderColor: Colors.white54),
    ),
  );
}

/// A Slider whose drag is geared down by [kSliderGearRatio]: pointer travel is divided by the
/// ratio before moving the thumb, so exact values are easy to hit. Pressing the track never jumps
/// the thumb — only dragging moves it (the tappable "Name value" label covers typed exact values).
class GearedSlider extends StatefulWidget {
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const GearedSlider(
      {super.key, required this.value, required this.min, required this.max, required this.onChanged});

  @override
  State<GearedSlider> createState() => _GearedSliderState();
}

class _GearedSliderState extends State<GearedSlider> {
  // Unrounded value accumulated across the current drag. Integer sliders round what we report and
  // hand the rounded value back on rebuild, so sub-unit progress must be kept here or slow drags
  // would never cross a unit boundary. Null when not dragging (then the parent's value is shown).
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final v = (_dragValue ?? widget.value).clamp(widget.min, widget.max);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => setState(() => _dragValue = v),
      onHorizontalDragUpdate: (d) {
        // Material insets the track by the 24px thumb-overlay radius on each side.
        final trackWidth = math.max(1.0, (context.size?.width ?? 120) - 48);
        final dv = d.delta.dx / kSliderGearRatio / trackWidth * (widget.max - widget.min);
        // Clamp the accumulator itself so reversing at an end responds immediately.
        setState(() => _dragValue = ((_dragValue ?? v) + dv).clamp(widget.min, widget.max));
        widget.onChanged(_dragValue!);
      },
      onHorizontalDragEnd: (_) => setState(() => _dragValue = null),
      onHorizontalDragCancel: () => setState(() => _dragValue = null),
      // The Slider is display-only (the GestureDetector owns all input); the no-op onChanged
      // keeps it in the enabled visual state.
      child: AbsorbPointer(
        child: Slider(value: v, min: widget.min, max: widget.max, onChanged: (_) {}),
      ),
    );
  }
}
