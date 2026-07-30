// Shared bottom-sheet building blocks: the "grouped zones" sheet idiom (identity header with
// thumbnail, state-chip zone, sectioned action rows, isolated destructive action) used by the
// Editor's layer/frame sheets and the Animator's cast/actor/key sheets. Lifted verbatim from
// the editor's private `_EditorSheets` extension (2026-07-30); zero behavior change. The
// thumbnail helpers take a plain `ui.Image?` so this module stays free of editor types.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:makapix_club/editor/widgets/painters.dart' show CheckerPainter;

/// Identity thumbnail on the transparent checkerboard, matching the strip tiles.
Widget sheetThumb(ui.Image? img) => Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF101214),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black26),
      ),
      padding: const EdgeInsets.all(2),
      child: CustomPaint(
        painter: const CheckerPainter(),
        child: img != null
            ? RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.none)
            : const SizedBox.shrink(),
      ),
    );

/// Header: thumbnail + bold title (+ optional rename affordance) + muted subtitle.
Widget sheetHeader({
  required ui.Image? thumb,
  required String title,
  required String subtitle,
  VoidCallback? onRename,
}) =>
    Row(children: [
      sheetThumb(thumb),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: onRename,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis),
              ),
              if (onRename != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.edit, size: 14, color: Colors.white54),
              ],
            ]),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ]),
      ),
    ]);

Widget sheetSection(String label) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(label.toUpperCase(),
          style: const TextStyle(
              fontSize: 11, letterSpacing: 1.2, color: Colors.white38, fontWeight: FontWeight.w600)),
    );

/// One action button; every non-destructive action in the sheets uses this idiom.
Widget sheetBtn(IconData icon, String label, VoidCallback? onTap) => FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis, maxLines: 1),
    );

/// A row of equal-width action buttons.
Widget sheetBtnRow(List<Widget> buttons) => Row(children: [
      for (var k = 0; k < buttons.length; k++) ...[
        if (k > 0) const SizedBox(width: 8),
        Expanded(child: buttons[k]),
      ],
    ]);

/// The lone destructive action at the bottom of a sheet.
Widget sheetDelete(String label, VoidCallback? onTap) => SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
        onPressed: onTap,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: Text(label),
      ),
    );

/// An icon toggle chip for a sheet's state zone (visible / locked / move-group / playing).
Widget stateChip({
  required IconData icon,
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
  Color? accent,
  String? tooltip,
}) {
  final chip = FilterChip(
    showCheckmark: false,
    avatar: Icon(icon, size: 16),
    label: Text(label, style: const TextStyle(fontSize: 12)),
    selected: value,
    selectedColor: accent,
    visualDensity: VisualDensity.compact,
    onSelected: onChanged,
  );
  return tooltip != null ? Tooltip(message: tooltip, child: chip) : chip;
}

Widget sheetScaffold(List<Widget> children) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children),
        ),
      ),
    );
