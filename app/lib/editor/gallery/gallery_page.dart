import 'package:flutter/material.dart';

import '../persistence/drawing_store.dart';
import 'drawing_library_grid.dart';

enum GalleryAction { open, newDrawing }

/// What the editor should do after the gallery closes.
class GalleryResult {
  final GalleryAction action;
  final String? id; // set for [GalleryAction.open]
  const GalleryResult.open(this.id) : action = GalleryAction.open;
  const GalleryResult.newDrawing()
      : id = null,
        action = GalleryAction.newDrawing;
}

/// "My Drawings" — the local working library, reached from the editor's ☰ menu. A thin `Scaffold`
/// around the shared [DrawingLibraryGrid]; opening or starting a new drawing pops a [GalleryResult]
/// for the editor to act on (Rename/Delete happen in-place inside the grid). The same grid also
/// powers the profile's Private tab.
class GalleryPage extends StatelessWidget {
  final DrawingStore store;
  final String? currentId;
  const GalleryPage({super.key, required this.store, this.currentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Drawings'),
        actions: [
          IconButton(
            tooltip: 'New drawing',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).pop(const GalleryResult.newDrawing()),
          ),
        ],
      ),
      body: DrawingLibraryGrid(
        store: store,
        currentId: currentId,
        onOpen: (id) => Navigator.of(context).pop(GalleryResult.open(id)),
        onNew: () => Navigator.of(context).pop(const GalleryResult.newDrawing()),
      ),
    );
  }
}
