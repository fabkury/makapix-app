import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'drawing_store.dart';

/// Exposes the on-disk drawing library to any pillar (the editor builds its own [DrawingStore]
/// directly; the Club's profile Private tab uses this). [DrawingStore] is a stateless directory
/// wrapper, so a second instance pointing at the same `<appSupport>/drawings` is equivalent — no
/// shared-instance coupling is needed.
final drawingStoreProvider = FutureProvider<DrawingStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return DrawingStore(dir);
});
