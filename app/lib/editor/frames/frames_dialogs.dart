// The Frames page's small dialogs (ADR 0031): Range entry, Every Nth, Shift by N, and the free
// scale factor. Each validates through the pure helpers in frame_set.dart and shows its error
// inline; Enter submits when valid.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'frame_set.dart';

/// "Select frames…": 1-based numbers and ranges. Resolves to 0-based indices, or `null`.
Future<List<int>?> showFrameRangeDialog(BuildContext context, {required int frameCount, String initialText = ''}) {
  return showDialog<List<int>>(
    context: context,
    builder: (ctx) {
      final ctrl = TextEditingController(text: initialText);
      return StatefulBuilder(builder: (ctx, setS) {
        final parsed = parseFrameRangeEntry(ctrl.text, frameCount: frameCount);
        void submit() {
          if (parsed.indices != null) Navigator.pop(ctx, parsed.indices);
        }
        return AlertDialog(
          title: const Text('Select frames'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '1-12, 20, 30-40',
                helperText: 'Frame numbers and ranges, 1 to $frameCount',
                errorText: ctrl.text.trim().isEmpty ? null : parsed.error,
                isDense: true,
              ),
              onChanged: (_) => setS(() {}),
              onSubmitted: (_) => submit(),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: parsed.indices == null ? null : submit, child: const Text('Select')),
          ],
        );
      });
    },
  );
}

/// "Every Nth…": N, a 1-based start offset, and whether to pick within the current selection.
Future<({int n, int offset, bool withinSelection})?> showEveryNthDialog(BuildContext context, {required bool hasSelection}) {
  return showDialog<({int n, int offset, bool withinSelection})>(
    context: context,
    builder: (ctx) {
      var n = 2;
      var offset = 1;
      var within = hasSelection;
      return StatefulBuilder(builder: (ctx, setS) {
        void submit() => Navigator.pop(ctx, (n: n, offset: offset - 1, withinSelection: within));
        return AlertDialog(
          title: const Text('Every Nth frame'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Every'),
              _IntField(value: n, min: 1, max: 1024, onChanged: (v) => setS(() => n = v)),
              const Text('frames, starting at frame'),
              _IntField(value: offset, min: 1, max: 1024, onChanged: (v) => setS(() => offset = v)),
            ]),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: const Text('Within selection'), enabled: hasSelection),
                  const ButtonSegment(value: false, label: Text('Whole roll')),
                ],
                selected: {within},
                onSelectionChanged: (s) => setS(() => within = s.first),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Select')),
          ],
        );
      });
    },
  );
}

/// "Shift by N…": an integer delta with a live line showing the clamped move. Resolves to the
/// CLAMPED delta (never zero), or `null`.
Future<int?> showShiftByDialog(BuildContext context, {required List<int> indices, required int frameCount}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      var delta = 1;
      return StatefulBuilder(builder: (ctx, setS) {
        final k = clampShift(indices, delta, frameCount);
        void submit() {
          if (k != 0) Navigator.pop(ctx, k);
        }
        return AlertDialog(
          title: const Text('Shift frames by'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _IntField(value: delta, min: -1024, max: 1024, onChanged: (v) => setS(() => delta = v), onSubmitted: submit),
              const SizedBox(width: 8),
              const Text('frames (negative = earlier)'),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 20,
              child: Text(
                k == 0 ? 'No room to move that way' : (k == delta ? 'Moves by $k' : 'Moves by $k (clamped from $delta)'),
                style: TextStyle(fontSize: 12, color: k == 0 ? Colors.amber : Colors.white70),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: k == 0 ? null : submit, child: const Text('Shift')),
          ],
        );
      });
    },
  );
}

/// "× …": a free timing factor 0.1–10. Resolves to per-mille, or `null`.
Future<int?> showScaleFactorDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      final ctrl = TextEditingController(text: '1.5');
      return StatefulBuilder(builder: (ctx, setS) {
        final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
        final ok = v != null && v >= 0.1 && v <= 10;
        void submit() {
          if (ok) Navigator.pop(ctx, (v * 1000).round());
        }
        return AlertDialog(
          title: const Text('Scale durations'),
          content: Row(children: [
            const Text('×'),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(isDense: true, errorText: ok || ctrl.text.isEmpty ? null : '0.1 to 10'),
                onChanged: (_) => setS(() {}),
                onSubmitted: (_) => submit(),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: ok ? submit : null, child: const Text('Scale')),
          ],
        );
      });
    },
  );
}

class _IntField extends StatefulWidget {
  const _IntField({required this.value, required this.min, required this.max, required this.onChanged, this.onSubmitted});
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final VoidCallback? onSubmitted;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _ctrl = TextEditingController(text: '${widget.value}');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: TextField(
        controller: _ctrl,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
        decoration: const InputDecoration(isDense: true),
        textAlign: TextAlign.center,
        onChanged: (t) {
          final v = int.tryParse(t);
          if (v != null) widget.onChanged(v.clamp(widget.min, widget.max));
        },
        onSubmitted: (_) => widget.onSubmitted?.call(),
      ),
    );
  }
}
