// The frame-duration editor — a millisecond field that is the source of truth while typing, a
// slider, and the fps presets — and the dialog around it. Shared by the frame sheet ("This
// frame" / "All frames") and the Frames page ("Apply to N frames", ADR 0031). Pure widgets:
// no engine, no DSL; the caller turns the result into a verb.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The engine's duration range in milliseconds (16.6 ms = 60 fps … 1 s).
const double kMinDurationMs = 16.6;
const double kMaxDurationMs = 1000;

/// The one-tap fps presets, in the order the chips show.
const List<int> kFpsPresets = [60, 30, 24, 12, 8];

/// The tapped action's index into `actions` and the chosen duration (already clamped).
typedef DurationChoice = ({int action, double ms});

/// Field + slider + fps chips. The text field is the source of truth while typing (never
/// rewritten mid-edit, so a partial entry like "5" on the way to "50" isn't clobbered); the
/// slider and the chips write back into it. [onChanged] receives every clamped value.
class DurationEditor extends StatefulWidget {
  const DurationEditor({super.key, required this.initialMs, required this.onChanged, this.autofocus = true});

  final double initialMs;
  final ValueChanged<double> onChanged;
  final bool autofocus;

  @override
  State<DurationEditor> createState() => _DurationEditorState();
}

class _DurationEditorState extends State<DurationEditor> {
  late double _ms = widget.initialMs.clamp(kMinDurationMs, kMaxDurationMs);
  late final TextEditingController _ctrl = TextEditingController(text: _ms.toStringAsFixed(1));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _set(double v, {bool writeField = true}) {
    setState(() {
      _ms = v.clamp(kMinDurationMs, kMaxDurationMs);
      if (writeField) _ctrl.text = _ms.toStringAsFixed(1);
    });
    widget.onChanged(_ms);
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        SizedBox(
          width: 110,
          child: TextField(
            controller: _ctrl,
            autofocus: widget.autofocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(suffixText: 'ms', isDense: true),
            onChanged: (t) {
              final v = double.tryParse(t.replaceAll(',', '.'));
              if (v != null) _set(v, writeField: false);
            },
          ),
        ),
        const Spacer(),
        Text('${(1000 / _ms).toStringAsFixed(1)} fps'),
      ]),
      Slider(value: _ms, min: kMinDurationMs, max: kMaxDurationMs, onChanged: _set),
      Wrap(spacing: 6, children: [
        for (final f in kFpsPresets) ActionChip(label: Text('${f}fps'), onPressed: () => _set(1000 / f)),
      ]),
    ]);
  }
}

/// The duration dialog: [title], a [DurationEditor] seeded with [initialMs], Cancel, and one
/// button per entry of [actions] (the last one filled). Resolves to the tapped action and the
/// duration, or `null` on Cancel.
Future<DurationChoice?> showDurationDialog(
  BuildContext context, {
  required String title,
  required double initialMs,
  required List<String> actions,
}) {
  var ms = initialMs.clamp(kMinDurationMs, kMaxDurationMs);
  return showDialog<DurationChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: DurationEditor(initialMs: initialMs, onChanged: (v) => ms = v),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        for (var i = 0; i < actions.length; i++)
          if (i == actions.length - 1)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (action: i, ms: ms)),
              child: Text(actions[i]),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(ctx, (action: i, ms: ms)),
              child: Text(actions[i]),
            ),
      ],
    ),
  );
}
