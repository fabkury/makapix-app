// The Layers page's small dialogs (ADR 0033): Range entry (1-based, bottom = 1), Opacity for
// the set, Rename with `{n}` and a live preview, Copy to frames (a 1-based frame range with an
// "All frames" chip), and the Blend picker for the set. Each validates through the pure
// helpers in layer_model.dart and shows its error inline; Enter submits when valid.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:makapix_club/ui/layout.dart';

import '../blend_modes.dart';
import '../frames/frame_set.dart' show parseFrameRangeEntry, formatFrameSetHuman;
import 'layer_model.dart';

/// "Select layers…": 1-based numbers and ranges, bottom first. Resolves to 0-based indices, or `null`.
Future<List<int>?> showLayerRangeDialog(BuildContext context, {required int layerCount, String initialText = ''}) {
  return showDialog<List<int>>(
    context: context,
    builder: (ctx) {
      final ctrl = TextEditingController(text: initialText);
      return StatefulBuilder(builder: (ctx, setS) {
        final parsed = parseLayerRangeEntry(ctrl.text, layerCount: layerCount);
        void submit() {
          if (parsed.indices != null) Navigator.pop(ctx, parsed.indices);
        }
        return AlertDialog(
          title: const Text('Select layers'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '1-4, 9, 20-25',
                helperText: 'Layer numbers and ranges, 1 (bottom) to $layerCount (top)',
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

/// "Opacity…": a 0–255 slider with a typed field. Resolves to the value, or `null`.
Future<int?> showLayersOpacityDialog(BuildContext context, {required int selectedCount, required int initial}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      var value = initial.clamp(0, 255);
      final ctrl = TextEditingController(text: '$value');
      return StatefulBuilder(builder: (ctx, setS) {
        void submit() => Navigator.pop(ctx, value);
        return AlertDialog(
          title: Text('Opacity of $selectedCount ${selectedCount == 1 ? 'layer' : 'layers'}'),
          content: Row(children: [
            Expanded(
              child: Slider(
                value: value.toDouble(),
                max: 255,
                onChanged: (v) => setS(() {
                  value = v.round();
                  ctrl.text = '$value';
                }),
              ),
            ),
            SizedBox(
              width: 56,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(isDense: true, helperText: '0–255'),
                textAlign: TextAlign.center,
                onChanged: (t) {
                  final v = int.tryParse(t);
                  if (v != null) setS(() => value = v.clamp(0, 255));
                },
                onSubmitted: (_) => submit(),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Apply')),
          ],
        );
      });
    },
  );
}

/// "Rename…": one name for the set; `{n}` numbers the members from the top. Resolves to the
/// raw pattern (sanitized by the caller), or `null`.
Future<String?> showLayersRenameDialog(BuildContext context, {required int selectedCount, String initialText = ''}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final ctrl = TextEditingController(text: initialText);
      return StatefulBuilder(builder: (ctx, setS) {
        final text = ctrl.text;
        final ok = text.trim().isNotEmpty && text.length <= kLayerNameMaxLength;
        final preview = renamePreview(text.trim(), selectedCount);
        final previewText = selectedCount <= 1
            ? preview.join()
            : (selectedCount == 2 ? '${preview.first}, ${preview.last}' : '${preview.first}, … ${preview.last}');
        void submit() {
          if (ok) Navigator.pop(ctx, text.trim());
        }
        return AlertDialog(
          title: Text('Rename $selectedCount ${selectedCount == 1 ? 'layer' : 'layers'}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: kLayerNameMaxLength,
              decoration: const InputDecoration(hintText: 'Sketch {n}', helperText: '{n} = 1, 2, 3… counting from the top', isDense: true),
              onChanged: (_) => setS(() {}),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 20,
              child: Text(ok ? previewText : ' ', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: ok ? submit : null, child: const Text('Rename')),
          ],
        );
      });
    },
  );
}

/// "Copy to frames…": a 1-based frame range with an "All frames" chip. Resolves to 0-based
/// frame indices, or `null`.
Future<List<int>?> showCopyToFramesDialog(BuildContext context, {required int frameCount, required int activeFrameIndex, required int selectedCount}) {
  return showDialog<List<int>>(
    context: context,
    builder: (ctx) {
      final ctrl = TextEditingController(text: frameCount == 1 ? '1' : '');
      return StatefulBuilder(builder: (ctx, setS) {
        final parsed = parseFrameRangeEntry(ctrl.text, frameCount: frameCount);
        void submit() {
          if (parsed.indices != null) Navigator.pop(ctx, parsed.indices);
        }
        return AlertDialog(
          title: Text('Copy $selectedCount ${selectedCount == 1 ? 'layer' : 'layers'} to frames'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '1-12, 20',
                helperText: 'Frame numbers and ranges, 1 to $frameCount; the copies land on top of each stack',
                errorText: ctrl.text.trim().isEmpty ? null : parsed.error,
                isDense: true,
              ),
              onChanged: (_) => setS(() {}),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              ActionChip(label: const Text('All frames'), onPressed: () => setS(() => ctrl.text = frameCount == 1 ? '1' : '1-$frameCount')),
              ActionChip(
                label: const Text('Other frames'),
                onPressed: frameCount < 2
                    ? null
                    : () => setS(() => ctrl.text = formatFrameSetHuman([for (var i = 0; i < frameCount; i++) if (i != activeFrameIndex) i])),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: parsed.indices == null ? null : submit, child: const Text('Copy')),
          ],
        );
      });
    },
  );
}

/// "Blend…": the grouped picker (the layer sheet's grouping), one tap picks. Resolves to the
/// engine token, or `null`.
Future<String?> showLayersBlendPicker(BuildContext context, {required int selectedCount, String? current}) {
  return showAppSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1C1F),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(dense: true, title: Text('Blend of $selectedCount ${selectedCount == 1 ? 'layer' : 'layers'}', style: const TextStyle(fontWeight: FontWeight.bold))),
            const Divider(height: 1),
            for (final (label, modes) in kBlendGroups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white54)),
              ),
              for (final m in modes)
                ListTile(
                  dense: true,
                  selected: m == current,
                  selectedTileColor: const Color(0x224080C0),
                  title: Text(blendDisplayName(m)),
                  trailing: m == current ? const Icon(Icons.check, color: Color(0xFF4080C0)) : null,
                  onTap: () => Navigator.pop(ctx, m),
                ),
            ],
            const SizedBox(height: 8),
          ]),
        ),
      ),
    ),
  );
}
