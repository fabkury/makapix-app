import 'dart:ui' as ui;

// A cached frame thumbnail tagged with the frame content hash it was generated from.
class ThumbCache {
  final int hash;
  final ui.Image img;
  ThumbCache(this.hash, this.img);
}
