// The New-scene dialog: size (free-form 1–256 + square presets, the editor's New-document
// idiom), frame rate from the curated GIF-safe list, and duration in frames. Sizes the Club
// won't accept get the advisory red alert but stay creatable (the creative tools are not
// limited to publishable sizes). Pops a [NewSceneSpec] on Create.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:makapix_club/animator/model/scene_rules.dart';
import 'package:makapix_club/club/publish/conformance.dart';
import 'package:makapix_club/club/publish/size_alert.dart';

class NewSceneSpec {
  final int width, height, fpsMilli, frames;
  const NewSceneSpec(this.width, this.height, this.fpsMilli, this.frames);
}

class NewSceneDialog extends StatefulWidget {
  /// Prefill (the "Animate this drawing" path passes the drawing's size).
  final int initialWidth, initialHeight;
  const NewSceneDialog({super.key, this.initialWidth = 64, this.initialHeight = 64});

  @override
  State<NewSceneDialog> createState() => _NewSceneDialogState();
}

class _NewSceneDialogState extends State<NewSceneDialog> {
  late final _w = TextEditingController(text: '${widget.initialWidth}');
  late final _h = TextEditingController(text: '${widget.initialHeight}');
  int _fpsMilli = 12500;
  late final _frames = TextEditingController(text: '${defaultFrameCount(12500)}');
  bool _framesTouched = false;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _frames.dispose();
    super.dispose();
  }

  int? _dim(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    return (v != null && v >= kSceneMinDim && v <= kSceneMaxDim) ? v : null;
  }

  int? get _frameCount {
    final v = int.tryParse(_frames.text.trim());
    return (v != null && v >= 1 && v <= kMaxSceneFrames) ? v : null;
  }

  Widget _field(TextEditingController c, String label, {int maxLength = 3}) {
    return Expanded(
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: maxLength,
        decoration: InputDecoration(labelText: label, counterText: '', isDense: true),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = _dim(_w), h = _dim(_h), frames = _frameCount;
    final valid = w != null && h != null && frames != null;
    final clubOk = !valid || ClubSizeRules.accepted(w, h);
    return AlertDialog(
      title: const Text('New scene'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child:
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _field(_w, 'Width'),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('×')),
              _field(_h, 'Height'),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final p in [16, 32, 64, 128, 256])
                ActionChip(
                  label: Text('$p²'),
                  onPressed: () => setState(() {
                    _w.text = '$p';
                    _h.text = '$p';
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            const Text('Frame rate', style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              for (final f in kSceneFpsMilli)
                ChoiceChip(
                  label: Text(fpsLabel(f), style: const TextStyle(fontSize: 12)),
                  selected: _fpsMilli == f,
                  onSelected: (_) => setState(() {
                    _fpsMilli = f;
                    // Keep the default two-second duration in step until hand-edited.
                    if (!_framesTouched) {
                      _frames.text = '${defaultFrameCount(f)}';
                    }
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _frames,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 4,
                  decoration:
                      const InputDecoration(labelText: 'Frames', counterText: '', isDense: true),
                  onChanged: (_) => setState(() => _framesTouched = true),
                ),
              ),
              const SizedBox(width: 10),
              if (frames != null)
                Text(
                  '${(frames * 1000 / _fpsMilli).toStringAsFixed(1)} s',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
            ]),
            if (!valid) ...[
              const SizedBox(height: 8),
              const Text('Each side must be 1–256 pixels; 1–1024 frames.',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
            if (valid && !clubOk) ...[
              const SizedBox(height: 8),
              ClubSizeAlert(w, h),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed:
              valid ? () => Navigator.pop(context, NewSceneSpec(w, h, _fpsMilli, frames)) : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
