// The Layers page's "More" sheet (ADR 0033): every batch operation that is not on the action
// bar, grouped Stack · State · Name · Content · Across frames · Move group, each row popping
// its [LayersOp]. Three fixed 20 px slots under Content carry the unobtrusive notes (locked
// members, the undo-memory estimate, the non-square rotate note) so the sheet never reflows.
// `dslForLayerOp` is the pure mapping from an op to the verb line, tested without widgets.

import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

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
    BlendOp() => layerSetDsl('SetLayersBlend', indices, [blend ?? 'Normal']), // l10n-ignore: engine blend mode
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
  return showAppSheet<LayersOp>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF1A1C1F),
    builder: (ctx) {
      void pick(LayersOp op) => Navigator.pop(ctx, op);
      final maxH = MediaQuery.sizeOf(ctx).height * 0.85;
      final l = ctx.l10n;
      final lockNote = lockedSelected > 0;
      final capNote = underCap ? null : l.layersAtCap(kMaxLayers);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(dense: true, title: Text(l.layersSelectedCount(n), style: const TextStyle(fontWeight: FontWeight.bold))),
              const Divider(height: 1),
              _section(l.sectionStack),
              _row(Icons.control_point_duplicate, l.commonDuplicate, capNote ?? l.layersDuplicateSub, underCap ? () => pick(const DuplicateLayersOp()) : null),
              _row(Icons.vertical_align_top, l.layersToTop, null, canShiftUp ? () => pick(const ToEdgeOp(top: true)) : null),
              _row(Icons.vertical_align_bottom, l.layersToBottom, null, canShiftDown ? () => pick(const ToEdgeOp(top: false)) : null),
              _row(Icons.swap_vert, l.batchReverse, n < 2 ? l.layersNeedTwo : null, n < 2 ? null : () => pick(const ReverseLayersOp())),
              _row(Icons.add_box_outlined, l.layersInsertAbove, capNote, underCap ? () => pick(const InsertBlankLayersOp(above: true)) : null),
              _row(Icons.add_box_outlined, l.layersInsertBelow, capNote, underCap ? () => pick(const InsertBlankLayersOp(above: false)) : null),
              _section(l.sectionState),
              _chips([
                (l.layersShow, () => pick(const SetVisibleOp(visible: true))),
                (l.layersHide, () => pick(const SetVisibleOp(visible: false))),
                (l.layersLock, () => pick(const SetLockedOp(locked: true))),
                (l.layersUnlock, () => pick(const SetLockedOp(locked: false))),
              ]),
              _row(Icons.opacity, l.layersOpacityMenu, l.layersOpacitySub, () => pick(const OpacityOp())),
              _row(Icons.gradient, l.layersBlendMenu, l.layersBlendSub, () => pick(const BlendOp())),
              _row(Icons.restart_alt, l.layersReset, l.layersResetSub, () => pick(const ResetLayersOp())),
              _section(l.commonNameLabel),
              _row(Icons.drive_file_rename_outline, l.layersRenameMenu, l.layersRenameSub('{n}'), () => pick(const RenameLayersOp())),
              _section(l.sectionContent),
              _slot(lockNote ? (Icons.lock, l.layersLockedNote(lockedSelected), Colors.amber) : null),
              _slot(retainedBytes > kLayersRetainedWarnBytes ? (Icons.warning_amber_rounded, l.batchUndoHolds(_mb(retainedBytes)), Colors.amber) : null),
              _slot(canvasSquare ? null : (Icons.info_outline, l.batchNotSquare, Colors.white54)),
              _chips([
                (l.opFlipH, lockNote ? null : () => pick(const FlipLayersOp(horizontal: true))),
                (l.opFlipV, lockNote ? null : () => pick(const FlipLayersOp(horizontal: false))),
                (l.opRotate90, lockNote ? null : () => pick(const RotateLayersOp(1))),
                ('180°', lockNote ? null : () => pick(const RotateLayersOp(2))),
                ('270°', lockNote ? null : () => pick(const RotateLayersOp(3))),
                (l.toolInvert, lockNote ? null : () => pick(const InvertLayersOp())),
                (l.layersClear, lockNote ? null : () => pick(const ClearLayersOp())),
              ]),
              _section(l.sectionAcrossFrames),
              _row(Icons.dynamic_feed, l.layersCopyToFrames, frameCount > 1 ? l.layersCopyToFramesSub : l.layersCopyOneFrame, () => pick(const CopyToFramesOp())),
              _section(l.layerMoveGroup),
              _row(Icons.open_with, l.layersUseAsMoveGroup, l.layersUseAsMoveGroupSub, () => pick(const UseAsMoveGroupOp())),
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

/// A fixed two-line note slot: text and color change, the height never does (no reflow). Two
/// lines because one cut the "not square" note off on a phone, in English too.
Widget _slot((IconData, String, Color)? note) => SizedBox(
      height: 30,
      child: note == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(note.$1, size: 14, color: note.$3),
                const SizedBox(width: 6),
                Expanded(child: Text(note.$2, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.25, color: note.$3))),
              ]),
            ),
    );
