// What a layer is called on screen.
//
// The engine names layers itself: a new layer is "Layer N", an image imported as a layer is
// "Import N", and a duplicate is its source's name plus " copy". Those names are stored in the document, in English, and the engine stays
// that way (documents are byte-deterministic; the batch verbs address layers by stored name).
// The shell translates them when it shows them, so an artist who never names a layer still
// reads "Capa 1" or "レイヤー 1". A name the artist typed is shown exactly as typed.
import 'package:makapix_club/l10n/l10n.dart';

final RegExp _engineDefault = RegExp(r'^(Layer|Import) (\d+)((?: copy)*)$');

/// The name to show for a layer whose stored name is [stored].
String shownLayerName(AppLocalizations l, String stored) {
  if (stored.isEmpty) return l.layerUnnamed;
  final m = _engineDefault.firstMatch(stored);
  if (m == null) return stored;
  final n = int.parse(m.group(2)!);
  var name = m.group(1) == 'Layer' ? l.layerDefaultName(n) : l.layerImportName(n);
  final copies = m.group(3)!.length ~/ ' copy'.length;
  for (var i = 0; i < copies; i++) {
    name = l.layerCopyName(name);
  }
  return name;
}
