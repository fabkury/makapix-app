// "My Scenes" — the Animator's library page (GalleryPage's twin): a thin Scaffold over
// SceneLibraryGrid whose result is a Navigator.pop value the AnimatorPage awaits.
import 'package:flutter/material.dart';

import 'package:makapix_club/animator/persistence/scene_store.dart';

import 'scene_library_grid.dart';

enum SceneGalleryAction { open, newScene }

class SceneGalleryResult {
  final SceneGalleryAction action;
  final String? id;
  const SceneGalleryResult.open(this.id) : action = SceneGalleryAction.open;
  const SceneGalleryResult.newScene()
      : action = SceneGalleryAction.newScene,
        id = null;
}

class SceneGalleryPage extends StatelessWidget {
  final SceneStore store;
  final String? currentId;
  const SceneGalleryPage({super.key, required this.store, this.currentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Scenes'),
        actions: [
          IconButton(
            tooltip: 'New scene',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.pop(context, const SceneGalleryResult.newScene()),
          ),
        ],
      ),
      body: SceneLibraryGrid(
        store: store,
        currentId: currentId,
        onOpen: (id) => Navigator.pop(context, SceneGalleryResult.open(id)),
        onNew: () => Navigator.pop(context, const SceneGalleryResult.newScene()),
      ),
    );
  }
}
