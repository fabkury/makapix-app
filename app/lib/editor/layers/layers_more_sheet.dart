// The Layers page's "More" sheet (ADR 0033): every batch operation that is not on the action
// bar, grouped Stack · State · Name · Content · Across frames · Move group, each row popping
// its [LayersOp]. Three fixed 20 px slots under Content carry the unobtrusive notes (locked
// members, the undo-memory estimate, the non-square rotate note) so the sheet never reflows.
// `dslForLayerOp` is the pure mapping from an op to the verb line, tested without widgets.

import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';

import 'layer_model.dart';

/// Above this retained payload, the Content section shows the memory note (warn-only).
const int kLayersRetainedWarnBytes = 64 << 20;

sealed class LayersOp {
  const LayersOp();
}

class DuplicateLayersOp extends LayersOp {
  const DuplicateLayersOp();
}

/// Shift by the maximum room toward the top (`top`) or the bottom.
class ToEdgeOp extends LayersOp {
  const ToEdgeOp({required this.top});
  final bool top;
}

class ReverseLayersOp extends LayersOp {
  const ReverseLayersOp();
}

class InsertBlankLayersOp extends LayersOp {
  const InsertBlankLayersOp({required this.above});
  final bool above;
}

class SetVisibleOp extends LayersOp {
  const SetVisibleOp({required this.visible});
  final bool visible;
}

class SetLockedOp extends LayersOp {
  const SetLockedOp({required this.locked});
  final bool locked;
}

/// Opens the opacity dialog on the page.
class OpacityOp extends LayersOp {
  const OpacityOp();
}

/// Opens the blend picker on the page.
class BlendOp extends LayersOp {
  const BlendOp();
}

class ResetLayersOp extends LayersOp {
  const ResetLayersOp();
}

/// Opens the rename dialog on the page.
class RenameLayersOp extends LayersOp {
  const RenameLayersOp();
}

class FlipLayersOp extends LayersOp {
  const FlipLayersOp({required this.horizontal});
  final bool horizontal;
}

class RotateLayersOp extends LayersOp {
  const RotateLayersOp(this.quarters);
  final int quarters;
}

class InvertLayersOp extends LayersOp {
  const InvertLayersOp();
}

class ClearLayersOp extends LayersOp {
  const ClearLayersOp();
}

/// Opens the frame-range dialog on the page.
class CopyToFramesOp extends LayersOp {
  const CopyToFramesOp();
}

/// Not a verb: the page pops and the editor sets the Move group to the selection.
class UseAsMoveGroupOp extends LayersOp {
  const UseAsMoveGroupOp();
}

/// The verb line for [op] over [indices] (engine order). Ops that need more input take it as
/// named args: the clamped [delta] for a To-edge shift, [opacity], the [blend] token, the
/// sanitized [name] pattern, the target [frames] for Copy to frames.
String dslForLayerOp(LayersOp op, List<int> indices, {int? delta, int? opacity, String? blend, String? name, List<int>? frames}) {
  return switch (op) {
    DuplicateLayersOp() => layerSetDsl('DuplicateLayers', indices),
    ToEdgeOp() => layerSetDsl('ShiftLayers', indices, ['${delta ?? 0}']),
    ReverseLayersOp() => layerSetDsl('ReverseLayers', indices),
    InsertBlankLayersOp(:final above) => layerSetDsl('InsertBlankLayers', indices, [above ? 'above' : 'below']),
    SetVisibleOp(:final visible) => layerSetDsl('SetLayersVisible', indices, [visible ? '1' : '0']),
    SetLockedOp(:final locked) => layerSetDsl('SetLayersLocked', indices, [locked ? '1' : '0']),
    OpacityOp() => layerSetDsl('SetLayersOpacity', indices, ['${(opacity ?? 255).clamp(0, 255)}']),
    BlendOp() => layerSetDsl('SetLayersBlend', indices, [blend ?? 'Normal']),
    ResetLayersOp() => layerSetDsl('ResetLayers', indices),
    RenameLayersOp() => layerSetDsl('RenameLayers', indices, [sanitizeName(name ?? '')]),
    FlipLayersOp(:final horizontal) => layerSetDsl(horizontal ? 'FlipLayersH' : 'FlipLayersV', indices),
    RotateLayersOp(:final quarters) => layerSetDsl('RotateLayers', indices, ['$quarters']),
    InvertLayersOp() => layerSetDsl('InvertLayers', indices),
    ClearLayersOp() => layerSetDsl('ClearLayers', indices),
    CopyToFramesOp() => layerSetDsl('CopyLayersToFrames', indices, [formatLayerSet(frames ?? const [0])]),
    UseAsMoveGroupOp() => layerSetDsl('SetActiveLayers', indices),
  };
}

/// Whether [op] rewrites pixels (the members' thumbnails must regenerate afterwards).
bool layerOpChangesContent(LayersOp op) => switch (op) {
      FlipLayersOp() || RotateLayersOp() || InvertLayersOp() || ClearLayersOp() => true,
      _ => false,
    };

/// Whether [op] is refused over a locked member (the lock guards pixels).
bool layerOpRespectsLock(LayersOp op) => layerOpChangesContent(op);

String _mb(int bytes) => (bytes / (1024 * 1024)).round().toString();

Future<LayersOp?> showLayersMoreSheet(
  BuildContext context, {
  required int selectedCount,
  required int lockedSelected,
  required bool canvasSquare,
  required int retainedBytes,
  required bool underCap,
  required bool canShiftUp,
  required bool canShiftDown,
  required int frameCount,
}) {
  final n = selectedCount;
  final plural = n == 1 ? 'layer' : 'layers';
  return showAppSheet<LayersOp>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF1A1C1F),
    builder: (ctx) {
      void pick(LayersOp op) => Navigator.pop(ctx, op);
      final maxH = MediaQuery.sizeOf(ctx).height * 0.85;
      final lockNote = lockedSelected > 0;
      final capNote = underCap ? null : 'The stack is at the $kMaxLayers-layer cap';
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(dense: true, title: Text('$n selected $plural', style: const TextStyle(fontWeight: FontWeight.bold))),
              const Divider(height: 1),
              _section('Stack'),
              _row(Icons.control_point_duplicate, 'Duplicate', capNote ?? 'A copy right above each selected layer', underCap ? () => pick(const DuplicateLayersOp()) : null),
              _row(Icons.vertical_align_top, 'Move to top', null, canShiftUp ? () => pick(const ToEdgeOp(top: true)) : null),
              _row(Icons.vertical_align_bottom, 'Move to bottom', null, canShiftDown ? () => pick(const ToEdgeOp(top: false)) : null),
              _row(Icons.swap_vert, 'Reverse order', n < 2 ? 'Select two or more layers' : null, n < 2 ? null : () => pick(const ReverseLayersOp())),
              _row(Icons.add_box_outlined, 'Insert blank above each', capNote, underCap ? () => pick(const InsertBlankLayersOp(above: true)) : null),
              _row(Icons.add_box_outlined, 'Insert blank below each', capNote, underCap ? () => pick(const InsertBlankLayersOp(above: false)) : null),
              _section('State'),
              _chips([
                ('Show', () => pick(const SetVisibleOp(visible: true))),
                ('Hide', () => pick(const SetVisibleOp(visible: false))),
                ('Lock', () => pick(const SetLockedOp(locked: true))),
                ('Unlock', () => pick(const SetLockedOp(locked: false))),
              ]),
              _row(Icons.opacity, 'Opacity…', 'One opacity for every selected layer', () => pick(const OpacityOp())),
              _row(Icons.gradient, 'Blend…', 'One blend mode for every selected layer', () => pick(const BlendOp())),
              _row(Icons.restart_alt, 'Reset', 'Visible, unlocked, opacity 255, Normal', () => pick(const ResetLayersOp())),
              _section('Name'),
              _row(Icons.drive_file_rename_outline, 'Rename…', 'One name; {n} numbers them from the top', () => pick(const RenameLayersOp())),
              _section('Content'),
              _slot(lockNote ? (Icons.lock, '$lockedSelected selected ${lockedSelected == 1 ? 'layer is' : 'layers are'} locked — these refuse', Colors.amber) : null),
              _slot(retainedBytes > kLayersRetainedWarnBytes ? (Icons.warning_amber_rounded, 'Undo will hold about ${_mb(retainedBytes)} MB', Colors.amber) : null),
              _slot(canvasSquare ? null : (Icons.info_outline, 'Not square: a rotated overhang parks in the gutter (Move recovers it)', Colors.white54)),
              _chips([
                ('Flip H', lockNote ? null : () => pick(const FlipLayersOp(horizontal: true))),
                ('Flip V', lockNote ? null : () => pick(const FlipLayersOp(horizontal: false))),
                ('Rotate 90°', lockNote ? null : () => pick(const RotateLayersOp(1))),
                ('180°', lockNote ? null : () => pick(const RotateLayersOp(2))),
                ('270°', lockNote ? null : () => pick(const RotateLayersOp(3))),
                ('Invert', lockNote ? null : () => pick(const InvertLayersOp())),
                ('Clear', lockNote ? null : () => pick(const ClearLayersOp())),
              ]),
              _section('Across frames'),
              _row(Icons.dynamic_feed, 'Copy to frames…', frameCount > 1 ? 'On top of each chosen frame\'s stack' : 'The animation has one frame; copies land on top of it', () => pick(const CopyToFramesOp())),
              _section('Move group'),
              _row(Icons.open_with, 'Use as Move group', 'Move these layers together with the Move tool', () => pick(const UseAsMoveGroupOp())),
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

Widget _chips(List<(String, VoidCallback?)> items) => Padding(
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
