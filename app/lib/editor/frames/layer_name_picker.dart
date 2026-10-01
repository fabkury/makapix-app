// The layer-name picker for the by-name batch ops (ADR 0031): every layer name present in the
// selected frames with its hit count ("14 of 20 selected frames have a layer named Shading"),
// so the artist sees exactly what the verb will touch before the tap.

import 'package:flutter/material.dart';

import 'package:makapix_club/l10n/l10n.dart';
import 'package:makapix_club/ui/layout.dart';

import '../layers/layer_names.dart';

Future<String?> showLayerNamePicker(
  BuildContext context, {
  required String title,
  required List<({String name, int hits})> names,
  required int selectedCount,
}) {
  return showAppSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1C1F),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(dense: true, title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
          const Divider(height: 1),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final n in names)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.layers, size: 20),
                  // The engine's own names ("Layer 3") are shown translated; the verb still
                  // gets the stored name ([n.name], popped below).
                  title: Text(shownLayerName(ctx.l10n, n.name)),
                  subtitle: Text(
                    ctx.l10n.framesLayerNameHits(n.hits, selectedCount),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () => Navigator.pop(ctx, n.name),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}
