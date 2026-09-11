// The Frames page's "More" sheet (ADR 0031): every batch operation that is not on the action
// bar, grouped Structure · Timing · Transform · Layers, each row popping its [FramesOp]. Two
// fixed 20 px slots under Transform carry the unobtrusive notes (the undo-memory estimate, the
// non-square rotate note) so the sheet never reflows. `dslForOp` is the pure mapping from an op
// to the verb line, tested without widgets.

import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';

import 'frame_set.dart';

/// Above this retained payload, the Transform section shows the memory note (warn-only).
const int kRetainedWarnBytes = 64 << 20;

sealed class FramesOp {
  const FramesOp();
}

class RepeatAfterOp extends FramesOp {
  const RepeatAfterOp();
}

class InsertBlankOp extends FramesOp {
  const InsertBlankOp({required this.before});
  final bool before;
}

class ReverseOp extends FramesOp {
  const ReverseOp();
}

/// Opens the "Shift by N…" dialog on the page.
class ShiftByOp extends FramesOp {
  const ShiftByOp();
}

/// `permille == null` opens the free-factor dialog.
class ScaleOp extends FramesOp {
  const ScaleOp(this.permille);
  final int? permille;
}

class FlipOp extends FramesOp {
  const FlipOp({required this.horizontal});
  final bool horizontal;
}

class RotateOp extends FramesOp {
  const RotateOp(this.quarters);
  final int quarters;
}

class InvertOp extends FramesOp {
  const InvertOp();
}

class CopyLayerOp extends FramesOp {
  const CopyLayerOp();
}

class RemoveLayerNamedOp extends FramesOp {
  const RemoveLayerNamedOp();
}

class SetLayersVisibleOp extends FramesOp {
  const SetLayersVisibleOp({required this.visible});
  final bool visible;
}

class SetLayersLockedOp extends FramesOp {
  const SetLayersLockedOp({required this.locked});
  final bool locked;
}

/// The verb line for [op] over [indices]. Ops that need more input take it as named args: the
/// layer name for the by-name ops, the (already clamped) delta for ShiftBy, the per-mille for
/// Scale.
String dslForOp(FramesOp op, List<int> indices, {String? layerName, int? delta, int? permille}) {
  final name = sanitizeLayerName(layerName ?? '');
  return switch (op) {
    RepeatAfterOp() => frameSetDsl('RepeatFramesAfter', indices),
    InsertBlankOp(:final before) => frameSetDsl('InsertBlankFrames', indices, [before ? 'before' : 'after']),
    ReverseOp() => frameSetDsl('ReverseFrames', indices),
    ShiftByOp() => frameSetDsl('ShiftFrames', indices, ['${delta ?? 0}']),
    ScaleOp(permille: final p) => frameSetDsl('ScaleFrameDurations', indices, ['${permille ?? p ?? 1000}']),
    FlipOp(:final horizontal) => frameSetDsl(horizontal ? 'FlipFramesH' : 'FlipFramesV', indices),
    RotateOp(:final quarters) => frameSetDsl('RotateFrames', indices, ['$quarters']),
    InvertOp() => frameSetDsl('InvertFrames', indices),
    CopyLayerOp() => frameSetDsl('CopyLayerToFrames', indices),
    RemoveLayerNamedOp() => frameSetDsl('RemoveLayersNamed', indices, [name]),
    SetLayersVisibleOp(:final visible) => frameSetDsl('SetLayersVisibleNamed', indices, [visible ? '1' : '0', name]),
    SetLayersLockedOp(:final locked) => frameSetDsl('SetLayersLockedNamed', indices, [locked ? '1' : '0', name]),
  };
}

/// Whether [op] rewrites pixels (its thumbnails must regenerate afterwards).
bool opChangesContent(FramesOp op) => switch (op) {
      FlipOp() || RotateOp() || InvertOp() || CopyLayerOp() || RemoveLayerNamedOp() || SetLayersVisibleOp() => true,
      _ => false,
    };

/// Whether [op] needs a layer name from the picker.
bool opNeedsLayerName(FramesOp op) => switch (op) {
      RemoveLayerNamedOp() || SetLayersVisibleOp() || SetLayersLockedOp() => true,
      _ => false,
    };

String _mb(int bytes) => (bytes / (1024 * 1024)).round().toString();

Future<FramesOp?> showFramesMoreSheet(
  BuildContext context, {
  required int selectedCount,
  required bool canvasSquare,
  required int retainedBytes,
  required bool anyTargetAtLayerCap,
  required bool hasLayerNames,
}) {
  final n = selectedCount;
  return showAppSheet<FramesOp>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF1A1C1F),
    builder: (ctx) {
      void pick(FramesOp op) => Navigator.pop(ctx, op);
      final maxH = MediaQuery.sizeOf(ctx).height * 0.85;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(dense: true, title: Text('$n selected ${n == 1 ? 'frame' : 'frames'}', style: const TextStyle(fontWeight: FontWeight.bold))),
              const Divider(height: 1),
              _section('Structure'),
              _row(Icons.repeat, 'Repeat after', 'The selection copied as one block after its last frame', () => pick(const RepeatAfterOp())),
              _row(Icons.add_box_outlined, 'Insert blank before each', null, () => pick(const InsertBlankOp(before: true))),
              _row(Icons.add_box_outlined, 'Insert blank after each', null, () => pick(const InsertBlankOp(before: false))),
              _row(Icons.swap_horiz, 'Reverse order', n < 2 ? 'Select two or more frames' : null, n < 2 ? null : () => pick(const ReverseOp())),
              _row(Icons.moving, 'Shift by N…', null, () => pick(const ShiftByOp())),
              _section('Timing'),
              _chips([
                ('× 0.5', () => pick(const ScaleOp(500))),
                ('× 2', () => pick(const ScaleOp(2000))),
                ('× …', () => pick(const ScaleOp(null))),
              ]),
              _section('Transform'),
              _slot(
                retainedBytes > kRetainedWarnBytes
                    ? (Icons.warning_amber_rounded, 'Undo will hold about ${_mb(retainedBytes)} MB', Colors.amber)
                    : null,
              ),
              _slot(canvasSquare ? null : (Icons.info_outline, 'Not square: a rotated overhang parks in the gutter (Move recovers it)', Colors.white54)),
              _chips([
                ('Flip H', () => pick(const FlipOp(horizontal: true))),
                ('Flip V', () => pick(const FlipOp(horizontal: false))),
                ('Rotate 90°', () => pick(const RotateOp(1))),
                ('180°', () => pick(const RotateOp(2))),
                ('270°', () => pick(const RotateOp(3))),
                ('Invert', () => pick(const InvertOp())),
              ]),
              _section('Layers'),
              _row(Icons.layers, 'Copy active layer to frames', anyTargetAtLayerCap ? 'A selected frame is at the 64-layer cap' : null,
                  anyTargetAtLayerCap ? null : () => pick(const CopyLayerOp())),
              _row(Icons.layers_clear, 'Remove layer named…', hasLayerNames ? null : 'No layers in the selection', hasLayerNames ? () => pick(const RemoveLayerNamedOp()) : null),
              _row(Icons.visibility, 'Show layer named…', null, hasLayerNames ? () => pick(const SetLayersVisibleOp(visible: true)) : null),
              _row(Icons.visibility_off, 'Hide layer named…', null, hasLayerNames ? () => pick(const SetLayersVisibleOp(visible: false)) : null),
              _row(Icons.lock, 'Lock layer named…', null, hasLayerNames ? () => pick(const SetLayersLockedOp(locked: true)) : null),
              _row(Icons.lock_open, 'Unlock layer named…', null, hasLayerNames ? () => pick(const SetLayersLockedOp(locked: false)) : null),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      );
    },
  );
}

Widget _section(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white54)),
    );

Widget _row(IconData icon, String label, String? subtitle, VoidCallback? onTap) => ListTile(
      dense: true,
      enabled: onTap != null,
      leading: Icon(icon, size: 20),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 11)),
      onTap: onTap,
    );

Widget _chips(List<(String, VoidCallback)> items) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(spacing: 6, runSpacing: 4, children: [
        for (final (label, onTap) in items) ActionChip(label: Text(label), onPressed: onTap),
      ]),
    );

/// A fixed 20 px note line: text and color change, the height never does (no reflow).
Widget _slot((IconData, String, Color)? note) => SizedBox(
      height: 20,
      child: note == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(note.$1, size: 14, color: note.$3),
                const SizedBox(width: 6),
                Expanded(child: Text(note.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: note.$3))),
              ]),
            ),
    );
