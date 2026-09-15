// The Layers page's "Select" sheet (ADR 0033): the by-property selectors as chips (Empty,
// Hidden / Visible, Locked / Unlocked, Non-Normal blend, Translucent) with the match counts,
// and the one persistent "Add to selection" switch that turns every selector into an add
// instead of a replace.

import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';

import 'layer_model.dart';

/// Resolves to the chosen selector, or `null`. [addToSelection] is read and written through
/// the callbacks so the page keeps the switch's state across openings.
Future<LayerPick?> showLayersSelectSheet(
  BuildContext context, {
  required List<LayerRow> rows,
  required bool addToSelection,
  required ValueChanged<bool> onAddToSelectionChanged,
}) {
  return showAppSheet<LayerPick>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1C1F),
    builder: (ctx) {
      var add = addToSelection;
      return StatefulBuilder(builder: (ctx, setS) {
        Widget chip(LayerPick p) {
          final n = pickLayers(rows, p).length;
          return ActionChip(
            label: Text('${layerPickLabel(p)} · $n'),
            onPressed: n == 0 ? null : () => Navigator.pop(ctx, p),
          );
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ListTile(dense: true, title: Text('Select layers by', style: TextStyle(fontWeight: FontWeight.bold))),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                chip(LayerPick.empty),
                chip(LayerPick.hidden),
                chip(LayerPick.visible),
                chip(LayerPick.locked),
                chip(LayerPick.unlocked),
                chip(LayerPick.nonNormal),
                chip(LayerPick.translucent),
              ]),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Add to selection'),
              subtitle: Text(add ? 'A selector adds its layers to what is selected' : 'A selector replaces the selection', style: const TextStyle(fontSize: 11)),
              value: add,
              onChanged: (v) {
                setS(() => add = v);
                onAddToSelectionChanged(v);
              },
            ),
            const SizedBox(height: 8),
          ]),
            ),
          ),
        );
      });
    },
  );
}
