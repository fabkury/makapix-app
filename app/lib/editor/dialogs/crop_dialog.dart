import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../widgets/painters.dart' show CanvasPainter;
import 'raster_preview.dart';

/// Fit `(rw, rh)` inside `(cw, ch)` preserving aspect ratio, **never upscaling** — the engine's
/// integer cross-multiply (`fit_no_upscale` in `crates/engine/src/import.rs`), so previews and
/// placement math agree with the import byte for byte.
(int, int) fitNoUpscale(int rw, int rh, int cw, int ch) {
  if (rw <= cw && rh <= ch) return (rw, rh);
  if (rw * ch >= rh * cw) return (cw, (rh * cw ~/ rw).clamp(1, ch));
  return ((rw * ch ~/ rh).clamp(1, cw), ch);
}

/// Which corner reticle is being dragged.
enum CropCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Pure, Flutter-free crop-rectangle geometry — all values are **integer source pixels**, so the
/// rect never accumulates fractional drift that `importImage`'s `.toInt()` would silently truncate.
/// The engine places this region 1:1 centered on the canvas (downscaled to fit only when larger),
/// so the math here mirrors `fit_no_upscale` in `crates/engine/src/import.rs`.
class CropGeometry {
  final int srcW, srcH, canvasW, canvasH;
  int x = 0, y = 0, w = 1, h = 1;
  bool aspectLocked = false;

  CropGeometry({required this.srcW, required this.srcH, required this.canvasW, required this.canvasH}) {
    // Default: canvas-size rect centered on the source, clamped to the source bounds (so a source
    // smaller than the canvas defaults to the whole source; the engine then centers it 1:1).
    w = canvasW.clamp(1, srcW);
    h = canvasH.clamp(1, srcH);
    x = ((srcW - w) / 2).round();
    y = ((srcH - h) / 2).round();
    _clamp();
  }

  double get _aspect => canvasW / canvasH; // canvas W:H

  void _clamp() {
    w = w.clamp(1, srcW);
    h = h.clamp(1, srcH);
    x = x.clamp(0, srcW - w);
    y = y.clamp(0, srcH - h);
  }

  Rect toRect() => Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());

  /// Move the whole rectangle to a new origin (clamped so it stays fully within the source).
  void setOrigin(int nx, int ny) {
    x = nx;
    y = ny;
    x = x.clamp(0, srcW - w);
    y = y.clamp(0, srcH - h);
  }

  /// Shift the whole rectangle by `(dx, dy)` source px — the nudge arrows and the keyboard
  /// arrows (2026-09-15); clamped like [setOrigin], so a nudge against an edge is a no-op.
  void nudge(int dx, int dy) => setOrigin(x + dx, y + dy);

  /// Larger than the canvas in some dimension — the case where the 1:1 / fit choice exists.
  bool get exceedsCanvas => w > canvasW || h > canvasH;

  /// Drag one corner to source-pixel `(sx, sy)`, keeping the opposite corner fixed.
  void dragCorner(CropCorner c, int sx, int sy) {
    sx = sx.clamp(0, srcW);
    sy = sy.clamp(0, srcH);
    final l = x, t = y, r = x + w, b = y + h;
    final fixedRight = c == CropCorner.topLeft || c == CropCorner.bottomLeft; // the LEFT edge is moving
    final fixedBottom = c == CropCorner.topLeft || c == CropCorner.topRight; // the TOP edge is moving
    var nw = fixedRight ? r - sx : sx - l;
    var nh = fixedBottom ? b - sy : sy - t;
    // Space available from the fixed corner toward the moving corner.
    final maxW = fixedRight ? r : srcW - l;
    final maxH = fixedBottom ? b : srcH - t;
    nw = nw.clamp(1, maxW);
    nh = nh.clamp(1, maxH);
    if (aspectLocked) {
      nh = (nw / _aspect).round().clamp(1, maxH);
      if ((nh / maxH) >= 1 || nh < (nw / _aspect).round()) {
        nw = (nh * _aspect).round().clamp(1, maxW);
      }
    }
    // Re-anchor the fixed corner.
    x = fixedRight ? r - nw : l;
    y = fixedBottom ? b - nh : t;
    w = nw;
    h = nh;
    _clamp();
  }

  /// Set one of the four fields from direct numeric entry (anchored at the top-left for W/H).
  void setField(String field, int value) {
    switch (field) {
      case 'x':
        x = value.clamp(0, srcW - w);
      case 'y':
        y = value.clamp(0, srcH - h);
      case 'w':
        w = value.clamp(1, srcW - x);
        if (aspectLocked) h = (w / _aspect).round().clamp(1, srcH - y);
      case 'h':
        h = value.clamp(1, srcH - y);
        if (aspectLocked) w = (h * _aspect).round().clamp(1, srcW - x);
    }
    _clamp();
  }

  void toggleAspectLock() {
    aspectLocked = !aspectLocked;
    if (aspectLocked) {
      final nh = (w / _aspect).round();
      h = nh.clamp(1, srcH - y);
      if (h != nh) w = (h * _aspect).round().clamp(1, srcW - x);
      _clamp();
    }
  }

  /// The on-canvas size this crop will produce: [fitNoUpscale], or the region's own size when
  /// [native] (the 1:1 choice, ADR 0034 — the overhang is parked off-canvas, never scaled).
  (int, int) resultDims({bool native = false}) => native ? (w, h) : fitNoUpscale(w, h, canvasW, canvasH);

  /// Whether the rect is the entire source — nothing to crop.
  bool get isWhole => x == 0 && y == 0 && w == srcW && h == srcH;

  /// Adopt a rectangle in source px, clipped to the source (a selection reaching into the gutter
  /// arrives with negative / past-edge values). Returns false — rect unchanged — when the clip is
  /// empty.
  bool setRect(int nx, int ny, int nw, int nh) {
    final l = nx.clamp(0, srcW), t = ny.clamp(0, srcH);
    final r = (nx + nw).clamp(0, srcW), b = (ny + nh).clamp(0, srcH);
    if (r <= l || b <= t) return false;
    x = l;
    y = t;
    w = r - l;
    h = b - t;
    _clamp();
    return true;
  }

  /// A size preset: `nw`×`nh` anchored at the current top-left, shifted (never shrunk) to stay
  /// inside the source. A locked aspect the preset does not satisfy is released rather than
  /// silently reshaping the preset.
  void setSize(int nw, int nh) {
    w = nw.clamp(1, srcW);
    h = nh.clamp(1, srcH);
    if (aspectLocked && (w * canvasH != h * canvasW)) aspectLocked = false;
    _clamp();
  }
}

/// Pure view transform for the crop editor (2026-09-01): the source is drawn at
/// `fitScale × zoom` screen px per source px, centered in the viewport, then shifted by [pan].
/// `zoom` runs from 1 (fit to screen — never below when there is nothing to see out there) up to
/// [maxZoom], the zoom that puts [maxPxPerSource] screen px on one source pixel (the editor
/// canvas's own ceiling). Pan is clamped so at least [keep] px of the image stay inside the
/// viewport on each axis, and is pinned to zero at fit. With an [overscanX]/[overscanY] band
/// (the Place page's off-canvas gutter, ADR 0030) fit still frames the image alone, but the view
/// may pan onto the band and zoom out to [minZoom], where the whole extended area fits.
/// Unit-tested; the page only feeds it gestures and reads [scale] / [origin].
class CropView {
  CropView({required this.srcW, required this.srcH, double margin = 16, this.overscanX = 0, this.overscanY = 0})
      : marginX = margin,
        marginY = margin;
  final int srcW, srcH;
  /// Source px of pannable content beyond each edge of the `srcW`×`srcH` image (0 = none).
  final int overscanX, overscanY;
  bool get hasOverscan => overscanX > 0 || overscanY > 0;
  /// Screen px kept free around the image at fit. The horizontal one grows on phones with
  /// gesture navigation (see [setMargins]): a corner reticle sitting inside the OS back-swipe
  /// zone can never be grabbed — the system takes the touch before Flutter sees it.
  double marginX, marginY;
  static const double maxPxPerSource = 32;
  static const double keep = 48;

  Size view = Size.zero;
  double zoom = 1;
  Offset pan = Offset.zero;

  double get fitScale {
    final aw = math.max(1.0, view.width - marginX * 2);
    final ah = math.max(1.0, view.height - marginY * 2);
    return math.min(aw / srcW, ah / srcH);
  }

  double get scale => fitScale * zoom;
  double get maxZoom => math.max(1.0, maxPxPerSource / fitScale);
  /// The zoom floor: 1 (fit) without overscan; with it, the zoom at which the whole extended
  /// area fits the viewport.
  double get minZoom {
    if (!hasOverscan) return 1;
    final aw = math.max(1.0, view.width - marginX * 2);
    final ah = math.max(1.0, view.height - marginY * 2);
    final ext = math.min(aw / (srcW + 2 * overscanX), ah / (srcH + 2 * overscanY));
    return math.min(1.0, ext / fitScale);
  }
  bool get isFit => (zoom - 1).abs() <= 0.0001;
  bool get canZoomOut => zoom > minZoom + 0.0001;
  /// At fit with no pan — the state the Fit button restores (with overscan, fit alone still
  /// allows a pan onto the band).
  bool get isHome => isFit && pan == Offset.zero;

  /// The image's top-left on screen at the current zoom and pan.
  Offset get origin => _centeredOrigin + pan;
  Offset get _centeredOrigin => Offset((view.width - srcW * scale) / 2, (view.height - srcH * scale) / 2);

  /// Adopt the viewport size (re-clamping the pan; a rotation must not strand the image).
  void setView(Size s) {
    if (s == view) return;
    view = s;
    _clampPan();
  }

  /// Adopt new fit margins (re-clamping the pan when they change).
  void setMargins({required double x, required double y}) {
    if (x == marginX && y == marginY) return;
    marginX = x;
    marginY = y;
    _clampPan();
  }

  /// Zoom to [newZoom] (clamped) keeping the source point under screen point [p] fixed.
  void zoomAt(Offset p, double newZoom) {
    final oldScale = scale;
    final oldOrigin = origin;
    zoom = newZoom.clamp(minZoom, maxZoom);
    final k = scale / oldScale;
    final desiredOrigin = p - (p - oldOrigin) * k;
    pan = desiredOrigin - _centeredOrigin;
    _clampPan();
  }

  void panBy(Offset d) {
    pan += d;
    _clampPan();
  }

  void fit() {
    zoom = 1;
    pan = Offset.zero;
  }

  /// One tap of the zoom-in / zoom-out buttons (2026-09-06): a [stepFactor] step about the
  /// viewport center, clamped like every other zoom. The buttons exist because pinch, double-tap
  /// and the wheel were the only ways in, and nothing on screen said so.
  static const double stepFactor = 1.5;
  bool get canZoomIn => zoom < maxZoom - 0.0001;
  void zoomStep({required bool inward}) =>
      zoomAt(Offset(view.width / 2, view.height / 2), inward ? zoom * stepFactor : zoom / stepFactor);

  /// The status readout. "View", not "Zoom: fit": the import dialog's scaling chooser already
  /// has a "Fit" option, and a user who picked Crop read "Zoom: fit" as the mode having changed.
  String get label => isFit ? 'View: fit to screen' : 'View: ${(zoom * 100).round()}%';

  /// Double-tap: back to fit when zoomed, else 4× fit about the tapped point.
  void toggleDoubleTap(Offset p) {
    if (isFit) {
      zoomAt(p, 4);
    } else {
      fit();
    }
  }

  /// Screen → source pixel (rounded), for corner drags.
  int srcX(double localX) => ((localX - origin.dx) / scale).round();
  int srcY(double localY) => ((localY - origin.dy) / scale).round();

  void _clampPan() {
    if (isFit && !hasOverscan) {
      pan = Offset.zero;
      return;
    }
    // Clamp against the extended area (image + overscan band): its origin sits `overscan × scale`
    // up-left of the image's.
    final base = _centeredOrigin - Offset(overscanX * scale, overscanY * scale);
    double axis(double p, double b, double disp, double extent) {
      // origin allowed in [keep − disp, extent − keep]; too small a viewport stays centered
      final lo = keep - disp - b, hi = extent - keep - b;
      return lo > hi ? 0 : p.clamp(lo, hi);
    }
    pan = Offset(axis(pan.dx, base.dx, (srcW + 2 * overscanX) * scale, view.width),
        axis(pan.dy, base.dy, (srcH + 2 * overscanY) * scale, view.height));
  }
}

/// The four ±1 px arrows both the Crop and the Place pages put at the end of their X/Y row
/// (2026-09-15; the Place page had them first). A tap nudges once; holding an arrow repeats it
/// after the long-press delay at [repeatInterval]. Keyboard arrows do the same through
/// [nudgeKeyHandler]; the two share the owner's `onNudge`.
class NudgeArrows extends StatefulWidget {
  final void Function(int dx, int dy) onNudge;
  const NudgeArrows({super.key, required this.onNudge});
  static const Duration repeatInterval = Duration(milliseconds: 66);
  @override
  State<NudgeArrows> createState() => _NudgeArrowsState();
}

class _NudgeArrowsState extends State<NudgeArrows> {
  Timer? _repeat;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Widget _btn(IconData icon, int dx, int dy, String tip) => GestureDetector(
        // The long-press recognizer here beats the IconButton's tap once the finger has stayed
        // down past the long-press timeout, so a held arrow never also fires the tap on release.
        onLongPressStart: (_) {
          _stop();
          widget.onNudge(dx, dy);
          _repeat = Timer.periodic(NudgeArrows.repeatInterval, (_) => widget.onNudge(dx, dy));
        },
        onLongPressEnd: (_) => _stop(),
        onLongPressCancel: _stop,
        child: IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20),
          onPressed: () => widget.onNudge(dx, dy),
        ),
      );

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        _btn(Icons.keyboard_arrow_left, -1, 0, 'Left 1 px (hold to repeat)'),
        _btn(Icons.keyboard_arrow_up, 0, -1, 'Up 1 px (hold to repeat)'),
        _btn(Icons.keyboard_arrow_down, 0, 1, 'Down 1 px (hold to repeat)'),
        _btn(Icons.keyboard_arrow_right, 1, 0, 'Right 1 px (hold to repeat)'),
      ]);
}

/// Keyboard nudging for the Crop and Place pages (desktop, 2026-09-15): an arrow key moves by
/// one px, ten with Shift; key repeat keeps moving. Anything else is ignored so the page's other
/// keys (Escape, Tab) keep their meaning. Pure: the pages wire it into a `Focus.onKeyEvent`.
KeyEventResult nudgeKeyHandler(KeyEvent event, void Function(int dx, int dy) nudge, {bool shift = false}) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;
  final k = event.logicalKey;
  final step = shift ? 10 : 1;
  if (k == LogicalKeyboardKey.arrowLeft) {
    nudge(-step, 0);
  } else if (k == LogicalKeyboardKey.arrowRight) {
    nudge(step, 0);
  } else if (k == LogicalKeyboardKey.arrowUp) {
    nudge(0, -step);
  } else if (k == LogicalKeyboardKey.arrowDown) {
    nudge(0, step);
  } else {
    return KeyEventResult.ignored;
  }
  return KeyEventResult.handled;
}

/// The zoom cluster both the Crop and the Place pages put at the end of their status row:
/// zoom-out · readout · zoom-in, each button disabled at its bound. Rebuilds through [onChanged]
/// so the owner's `setState` repaints the preview.
class ViewZoomControls extends StatelessWidget {
  final CropView view;
  final VoidCallback onChanged;
  const ViewZoomControls({super.key, required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, bool enabled, bool inward) => IconButton(
          tooltip: tip,
          icon: Icon(icon, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: enabled
              ? () {
                  view.zoomStep(inward: inward);
                  onChanged();
                }
              : null,
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.zoom_out, 'Zoom out', view.canZoomOut, false),
      Text(view.label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
      btn(Icons.zoom_in, 'Zoom in', view.canZoomIn, true),
    ]);
  }
}

/// The one-line gesture legend under the status row: the view gestures were undiscoverable
/// (a user asked how to change "Zoom: fit" and tried the app-bar icons).
Widget viewGestureHint(String oneFinger) => Text(
      'Pinch, double-tap, or scroll to zoom. One finger $oneFinger.',
      style: const TextStyle(fontSize: 11, color: Colors.white54),
    );

/// How a raster to import relates to the canvas (2026-09-01): the Fit / Stretch / Crop chooser
/// only earns its place for a source larger than the canvas in at least one dimension. A source
/// no larger than the canvas is placed 1:1 centered unless the user asks to scale it up; one the
/// exact canvas size has a single outcome and no scaling UI at all.
enum ImportSizeClass { exact, small, large }

ImportSizeClass importSizeClass(int srcW, int srcH, int canvasW, int canvasH) {
  if (srcW == canvasW && srcH == canvasH) return ImportSizeClass.exact;
  if (srcW <= canvasW && srcH <= canvasH) return ImportSizeClass.small;
  return ImportSizeClass.large;
}

/// The engine's `mode` codes for `mkpx_import` (0 Fit · 1 Stretch · 2 Crop · 3 Native).
const int kImportModeFit = 0, kImportModeStretch = 1, kImportModeCrop = 2, kImportModeNative = 3;

/// Whether the 1:1 choice is offered for a large source (ADR 0030): only when the whole source
/// fits within the storage area (canvas + gutter), so every pixel has somewhere to land.
bool nativeSizeOffered(int srcW, int srcH, int storageW, int storageH) => srcW <= storageW && srcH <= storageH;

/// Engine arguments for a source no larger than the canvas: [scaleUp] → Fit (mode 0, the
/// aspect-kept upscale to fill the canvas); otherwise the whole source as an explicit crop
/// region, which the engine places 1:1 centered (never upscaled) — the documented crop path
/// rather than the anchor-centered Crop mode, so the placement is the one the crop editor uses.
({int mode, Rect? crop}) smallSourceImportArgs({required bool scaleUp, required int srcW, required int srcH}) =>
    scaleUp ? (mode: 0, crop: null) : (mode: 2, crop: Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()));

/// What the crop editor returns: the rectangle in **source pixels**, and — import mode — whether
/// an oversize region keeps its size ([native], the default: the overhang is parked off-canvas,
/// ADR 0034) or is downscaled to fit the canvas. Meaningless when the rect fits the canvas.
class CropChoice {
  final Rect rect;
  final bool native;
  const CropChoice(this.rect, {this.native = true});
}

/// A large, dedicated crop editor for imported rasters (static or animated). Returns a
/// [CropChoice] (or null on cancel). The engine (`mkpx_import`) places that region 1:1 centered
/// on the canvas — downscaling a larger region only when the choice says so.
///
/// View gestures (user decisions 2026-09-01): one finger always edits the crop (a corner reticle
/// or the rect body); two fingers pan and pinch-zoom about the pinch point; a trackpad pan/pinch
/// does the same; the mouse wheel zooms about the cursor (the editor canvas's step); a right- or
/// middle-button drag pans; double-tap toggles fit ↔ 4× at the tapped point; the status row's
/// zoom buttons step 1.5× and the app bar's "Fit to screen" resets. Zoom runs from fit to 32
/// screen px per source px.
/// Which document the crop editor is cropping: a raster being imported, or the open canvas
/// itself (Crop canvas, ADR 0027 — same page, same gestures, same controls).
enum CropPageMode { import, canvas }

class CropPage extends StatefulWidget {
  /// The shared decoded-frames preview (the owner creates and disposes it; the import flow's
  /// Place page reuses the same instance so a many-frame GIF is decoded once).
  final FramePreview preview;
  final int srcW, srcH, canvasW, canvasH;
  final CropPageMode mode;
  /// The rectangle to open with (source px; clipped). Canvas mode: a selection's bounds; import
  /// mode: the previous choice when the crop is re-edited. Null or fully outside = the default
  /// (canvas mode: the whole source).
  final Rect? initialRect;
  /// Import mode: the 1:1 / fit choice to open with (re-editing keeps the previous one).
  final bool initialNative;
  /// Import mode: the off-canvas gutter beyond each canvas edge (storage = canvas + 2 × gutter),
  /// so the result line can say when a 1:1 region is wider than even the storage area.
  final int gutterW, gutterH;
  /// Canvas mode: the tight box around all non-transparent pixels — the "Trim to content" target.
  /// Null = fully transparent document (the button is disabled).
  final Rect? contentBounds;
  /// Canvas mode: an optional note under the result line for a given result size (the Club size
  /// status); return null for nothing. Whatever it returns should keep one height across sizes:
  /// the panel's height feeds the preview's fit scale, and a height that flips during a corner
  /// drag moves the image under the finger.
  final Widget? Function(int w, int h)? sizeNote;
  const CropPage({
    super.key,
    required this.preview,
    required this.srcW,
    required this.srcH,
    required this.canvasW,
    required this.canvasH,
    this.mode = CropPageMode.import,
    this.initialRect,
    this.initialNative = true,
    this.gutterW = 0,
    this.gutterH = 0,
    this.contentBounds,
    this.sizeNote,
  });
  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> with SingleTickerProviderStateMixin {
  static const double _reticleRadius = 11; // drawn radius
  static const double _reticleHit = 28; // touch radius
  // One wheel notch zooms by this factor (the editor canvas's constants: 60 logical px per notch).
  static const double _kWheelZoomStep = 1.2, _kWheelNotchDelta = 60.0;

  late final CropGeometry _geo;
  late final CropView _view;
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'CropPage');
  /// Import mode: an oversize region keeps its size (default) or is downscaled to the canvas.
  late bool _native = widget.initialNative;
  int _current = 0;
  bool _playing = false;
  Duration _last = Duration.zero;
  Duration _acc = Duration.zero;

  // Crop-drag state (snapshot on start to avoid fractional drift).
  CropCorner? _dragCorner;
  bool _dragMove = false;
  Offset _startLocal = Offset.zero;
  int _startX = 0, _startY = 0;
  // View-gesture state: a scale gesture is a view gesture from its start (two fingers / trackpad)
  // or becomes one the moment a second finger lands — and stays one until it ends, so lifting
  // back to one finger never resumes a crop edit mid-air.
  bool _viewGesture = false;
  // ScaleUpdateDetails.scale is cumulative only until the finger count changes (the recognizer
  // re-references and reports 1 again), so zoom is applied as the ratio between consecutive
  // updates, with the reference re-seeded on every pointer-count change.
  double _lastGestureScale = 1;
  int _lastPointerCount = 0;
  // Mouse: a right/middle-button drag pans; tracked from the raw Listener so the primary-button
  // scale recognizer never sees it as a crop edit.
  bool _mousePan = false;
  Offset _mouseLast = Offset.zero;

  @override
  void initState() {
    super.initState();
    _geo = CropGeometry(srcW: widget.srcW, srcH: widget.srcH, canvasW: widget.canvasW, canvasH: widget.canvasH);
    final init = widget.initialRect;
    if (init != null) _geo.setRect(init.left.round(), init.top.round(), init.width.round(), init.height.round());
    _view = CropView(srcW: widget.srcW, srcH: widget.srcH);
    _ticker = createTicker(_onTick);
    widget.preview.addListener(_onPreview);
    widget.preview.load();
  }

  @override
  void dispose() {
    widget.preview.removeListener(_onPreview);
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onPreview() {
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    _acc += dt;
    final (cur, left) = widget.preview.advance(_current, _acc);
    _acc = left;
    if (cur != _current && mounted) setState(() => _current = cur);
  }

  /// The nudge arrows and the keyboard arrows: shift the rect one px (clamped), killing any live
  /// drag first ([G-45]: a held corner would otherwise keep writing pre-nudge geometry).
  void _nudge(int dx, int dy) => setState(() {
        _endCropDrag();
        _geo.nudge(dx, dy);
      });

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return KeyEventResult.ignored;
    return nudgeKeyHandler(event, _nudge, shift: HardwareKeyboard.instance.isShiftPressed);
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        _last = Duration.zero;
        _acc = Duration.zero;
        _ticker.start();
      } else {
        _ticker.stop();
      }
    });
  }

  /// Step one frame forward or back (2026-09-06), wrapping at either end like the loop itself.
  /// Stepping pauses playback: a scrubbed frame that kept advancing would be gone before the
  /// crop could be judged against it.
  void _stepFrame(int delta) {
    final n = widget.preview.frames.length;
    if (n < 2) return;
    setState(() {
      if (_playing) {
        _playing = false;
        _ticker.stop();
      }
      _current = (_current + delta) % n;
    });
  }

  // ---- gestures ----

  void _endCropDrag() {
    _dragCorner = null;
    _dragMove = false;
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (_mousePan) return;
    _viewGesture = d.pointerCount >= 2 || d.kind == PointerDeviceKind.trackpad;
    if (_viewGesture) {
      _endCropDrag();
      _lastGestureScale = 1;
      _lastPointerCount = d.pointerCount;
      return;
    }
    // One finger: corner reticles first (generous radius), then inside-rect move.
    final p = d.localFocalPoint;
    for (final c in CropCorner.values) {
      if ((p - _cornerScreen(c)).distance <= _reticleHit) {
        _dragCorner = c;
        _dragMove = false;
        return;
      }
    }
    final rectScreen = Rect.fromLTWH(
      _view.origin.dx + _geo.x * _view.scale,
      _view.origin.dy + _geo.y * _view.scale,
      _geo.w * _view.scale,
      _geo.h * _view.scale,
    );
    if (rectScreen.contains(p)) {
      _dragMove = true;
      _dragCorner = null;
      _startLocal = p;
      _startX = _geo.x;
      _startY = _geo.y;
    } else {
      _endCropDrag();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_mousePan) return;
    if (!_viewGesture && d.pointerCount >= 2) {
      // A second finger joined a crop edit: it is a view gesture from here on.
      _viewGesture = true;
      _endCropDrag();
      _lastGestureScale = d.scale;
      _lastPointerCount = d.pointerCount;
    }
    if (_viewGesture) {
      if (d.pointerCount != _lastPointerCount) {
        _lastPointerCount = d.pointerCount;
        _lastGestureScale = d.scale; // re-referenced: no zoom step on this update
      }
      final ratio = _lastGestureScale > 0 ? d.scale / _lastGestureScale : 1.0;
      _lastGestureScale = d.scale;
      setState(() {
        // Pinch about the (moving) focal point: zoom keeps the source under the focal point
        // fixed, then the focal drift pans.
        if (ratio != 1) _view.zoomAt(d.localFocalPoint, _view.zoom * ratio);
        _view.panBy(d.focalPointDelta);
      });
      return;
    }
    if (_dragCorner != null) {
      setState(() =>
          _geo.dragCorner(_dragCorner!, _view.srcX(d.localFocalPoint.dx), _view.srcY(d.localFocalPoint.dy)));
    } else if (_dragMove) {
      final dx = ((d.localFocalPoint.dx - _startLocal.dx) / _view.scale).round();
      final dy = ((d.localFocalPoint.dy - _startLocal.dy) / _view.scale).round();
      setState(() => _geo.setOrigin(_startX + dx, _startY + dy));
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _viewGesture = false;
    _endCropDrag();
  }

  void _onDoubleTapDown(TapDownDetails d) => setState(() => _view.toggleDoubleTap(d.localPosition));

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse && (e.buttons & (kSecondaryButton | kMiddleMouseButton)) != 0) {
      _mousePan = true;
      _mouseLast = e.localPosition;
      _endCropDrag();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_mousePan) return;
    final delta = e.localPosition - _mouseLast;
    _mouseLast = e.localPosition;
    if (delta != Offset.zero) setState(() => _view.panBy(delta));
  }

  void _onPointerUp(PointerEvent e) => _mousePan = false;

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final factor = math.pow(_kWheelZoomStep, -e.scrollDelta.dy / _kWheelNotchDelta).toDouble();
    setState(() => _view.zoomAt(e.localPosition, _view.zoom * factor));
  }

  Offset _cornerScreen(CropCorner c) {
    final l = _view.origin.dx + _geo.x * _view.scale;
    final t = _view.origin.dy + _geo.y * _view.scale;
    final r = l + _geo.w * _view.scale;
    final b = t + _geo.h * _view.scale;
    switch (c) {
      case CropCorner.topLeft:
        return Offset(l, t);
      case CropCorner.topRight:
        return Offset(r, t);
      case CropCorner.bottomLeft:
        return Offset(l, b);
      case CropCorner.bottomRight:
        return Offset(r, b);
    }
  }

  Future<void> _editField(String field, int current, String label) async {
    final ctrl = TextEditingController(text: '$current');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label (px)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (t) => Navigator.pop(ctx, int.tryParse(t.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())), child: const Text('Set')),
        ],
      ),
    );
    if (v != null) setState(() => _geo.setField(field, v));
  }

  Widget _coordChip(String field, String label, int value) => ActionChip(
        label: Text('$label $value'),
        onPressed: () => _editField(field, value, label),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final animated = p.animated;
    final canvasMode = widget.mode == CropPageMode.canvas;
    final native = !canvasMode && _native;
    final (rw, rh) = _geo.resultDims(native: native);
    final downscaled = rw < _geo.w || rh < _geo.h;
    final oversize = !canvasMode && _geo.exceedsCanvas;
    // A 1:1 region wider than the whole storage area loses its far part at import (the Place
    // page shows exactly which part); say so here, where the size is being chosen.
    final beyondStorage =
        native && (_geo.w > widget.canvasW + 2 * widget.gutterW || _geo.h > widget.canvasH + 2 * widget.gutterH);
    final trim = widget.contentBounds;
    final trimIsCurrent = trim != null &&
        _geo.x == trim.left.round() &&
        _geo.y == trim.top.round() &&
        _geo.w == trim.width.round() &&
        _geo.h == trim.height.round();
    final sizeNote = canvasMode ? widget.sizeNote?.call(_geo.w, _geo.h) : null;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(canvasMode ? 'Crop canvas' : 'Crop'),
          actions: [
            IconButton(
              tooltip: 'Fit to screen',
              icon: const Icon(Icons.fit_screen),
              onPressed: _view.isHome ? null : () => setState(_view.fit),
            ),
            if (canvasMode)
              IconButton(
                tooltip: trim == null ? 'Nothing to trim: the drawing is empty' : 'Trim to content',
                icon: const Icon(Icons.crop_free),
                onPressed: trim == null || trimIsCurrent
                    ? null
                    : () => setState(() {
                          _endCropDrag();
                          _geo.setRect(trim.left.round(), trim.top.round(), trim.width.round(), trim.height.round());
                        }),
              ),
            IconButton(
              tooltip: _geo.aspectLocked ? 'Aspect locked to canvas' : 'Lock to canvas aspect',
              icon: Icon(_geo.aspectLocked ? Icons.lock : Icons.lock_open),
              // [G-45] Kill any live drag first: an in-flight corner/move drag would otherwise
              // keep writing geometry derived from before the toggle.
              onPressed: () => setState(() {
                _endCropDrag();
                _geo.toggleAspectLock();
              }),
            ),
            IconButton(
              tooltip: 'Reset crop',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => setState(() {
                // [G-45] Same here: without this the still-held drag resurrects the pre-reset rect.
                _endCropDrag();
                final fresh = CropGeometry(
                    srcW: widget.srcW, srcH: widget.srcH, canvasW: widget.canvasW, canvasH: widget.canvasH);
                _geo
                  ..x = fresh.x
                  ..y = fresh.y
                  ..w = fresh.w
                  ..h = fresh.h
                  ..aspectLocked = false;
              }),
            ),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: p.loadError
                ? const Center(child: Text('Could not decode this image.'))
                : !p.loaded
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(builder: (ctx, cons) {
                        // Keep the fit view's corners out of the OS back-swipe zone (Android gesture
                        // navigation): the system claims a touch that starts there, so a reticle at
                        // the screen edge could never be grabbed. Desktop and button-nav phones
                        // report zero insets and keep the tight fit.
                        final gesture = MediaQuery.systemGestureInsetsOf(ctx);
                        final edge = math.max(gesture.left, gesture.right);
                        _view.setMargins(
                          x: math.max(_view.marginY, edge > 0 ? edge + _reticleRadius + 8 : 0),
                          y: _view.marginY,
                        );
                        _view.setView(Size(cons.maxWidth, cons.maxHeight));
                        // Raw pointer layer (wheel zoom, right/middle-drag pan) around the gesture
                        // layer (primary-button scale = crop edit or two-finger view; double-tap).
                        // The scale recognizer is restricted to the primary button so a mouse pan
                        // never doubles as a crop edit.
                        return Listener(
                          onPointerDown: _onPointerDown,
                          onPointerMove: _onPointerMove,
                          onPointerUp: _onPointerUp,
                          onPointerCancel: _onPointerUp,
                          onPointerSignal: _onPointerSignal,
                          child: RawGestureDetector(
                            behavior: HitTestBehavior.opaque,
                            gestures: <Type, GestureRecognizerFactory>{
                              ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                                () => ScaleGestureRecognizer(
                                    debugOwner: this, allowedButtonsFilter: (b) => b == kPrimaryButton),
                                (r) => r
                                  ..onStart = _onScaleStart
                                  ..onUpdate = _onScaleUpdate
                                  ..onEnd = _onScaleEnd,
                              ),
                              DoubleTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
                                () => DoubleTapGestureRecognizer(debugOwner: this),
                                (r) => r..onDoubleTapDown = _onDoubleTapDown,
                              ),
                            },
                            child: ClipRect(
                              child: CustomPaint(
                                size: Size(cons.maxWidth, cons.maxHeight),
                                painter: _CropPreviewPainter(
                                  image: p.frames[_current],
                                  geo: _geo,
                                  scale: _view.scale,
                                  origin: _view.origin,
                                  reticleRadius: _reticleRadius,
                                  checker: canvasMode,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(
                  tooltip: 'Previous frame',
                  icon: const Icon(Icons.skip_previous, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: animated ? () => _stepFrame(-1) : null,
                ),
                IconButton(
                  tooltip: _playing ? 'Pause' : 'Play',
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  visualDensity: VisualDensity.compact,
                  onPressed: animated ? _togglePlay : null,
                ),
                IconButton(
                  tooltip: 'Next frame',
                  icon: const Icon(Icons.skip_next, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: animated ? () => _stepFrame(1) : null,
                ),
                Text(
                  animated ? 'Frame ${_current + 1} / ${p.frames.length}' : 'Static',
                  style: const TextStyle(fontSize: 13),
                ),
                if (p.truncated)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text('(preview truncated — full animation still imports)',
                        style: TextStyle(fontSize: 11, color: Colors.white54)),
                  ),
                const Spacer(),
                ViewZoomControls(view: _view, onChanged: () => setState(() {})),
              ]),
              viewGestureHint('moves the crop'),
              const SizedBox(height: 4),
              // Position row: the X/Y chips with the nudge arrows that move them (the Place page's
              // row); size row: W/H with what sets a size — the 1:1 / fit choice (import) or the
              // presets (canvas). Two rows of fixed composition, so the panel height never
              // depends on the rect (the no-reflow rule: the panel height feeds the fit scale).
              Row(children: [
                _coordChip('x', 'X', _geo.x),
                const SizedBox(width: 6),
                _coordChip('y', 'Y', _geo.y),
                const Spacer(),
                NudgeArrows(onNudge: _nudge),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                _coordChip('w', 'W', _geo.w),
                const SizedBox(width: 6),
                _coordChip('h', 'H', _geo.h),
                if (!canvasMode) ...[
                  const Spacer(),
                  // Only meaningful for an oversize region; kept in the layout (invisible, same
                  // size) otherwise so a corner drag across the canvas size does not reflow.
                  Visibility(
                    visible: oversize,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('1:1')),
                        ButtonSegment(value: false, label: Text('Fit to canvas')),
                      ],
                      selected: {_native},
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      onSelectionChanged: (s) => setState(() {
                        _endCropDrag();
                        _native = s.first;
                      }),
                    ),
                  ),
                ],
              ]),
              if (canvasMode)
                // Size presets (the Resize canvas dialog's), only those that fit some side — on
                // their own captioned row: they set a size, the chips above show the rectangle.
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text('Presets', style: TextStyle(fontSize: 12, color: Colors.white60)),
                    ),
                    Expanded(
                      child: Wrap(spacing: 6, runSpacing: 4, children: [
                        for (final p in const [16, 32, 64, 128, 256, 512])
                          if (p <= math.max(widget.srcW, widget.srcH))
                            ActionChip(
                              label: Text('$p²'),
                              onPressed: () => setState(() {
                                _endCropDrag();
                                _geo.setSize(p, p);
                              }),
                            ),
                      ]),
                    ),
                  ]),
                ),
              const SizedBox(height: 6),
              Text(
                canvasMode
                    ? 'New canvas: ${_geo.w} × ${_geo.h} px'
                    : downscaled
                        ? 'On canvas: $rw × $rh px (downscaled to fit ${widget.canvasW}×${widget.canvasH})'
                        : beyondStorage
                            ? 'Placed 1:1: $rw × $rh px, larger than the off-canvas area — the far part is dropped at import'
                            : oversize
                                ? 'Placed 1:1: $rw × $rh px; the part beyond the ${widget.canvasW}×${widget.canvasH} canvas is kept off-canvas'
                                : 'On canvas: $rw × $rh px (placed 1:1)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: beyondStorage ? Colors.amber : Colors.white60),
              ),
              if (sizeNote != null) Padding(padding: const EdgeInsets.only(top: 8), child: sizeNote),
            ]),
          ),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                // Canvas mode: a whole-canvas rect has nothing to crop, so OK stays disabled.
                onPressed: !p.loaded || (canvasMode && _geo.isWhole)
                    ? null
                    : () => Navigator.pop(context, CropChoice(_geo.toRect(), native: native)),
                child: Text(canvasMode ? 'Crop' : 'Use crop'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CropPreviewPainter extends CustomPainter {
  final ui.Image image;
  final CropGeometry geo;
  final double scale;
  final Offset origin;
  final double reticleRadius;
  /// Draw the editor's transparency checker under the image (the document itself is being
  /// cropped, so transparency must read as it does on the canvas).
  final bool checker;
  _CropPreviewPainter({
    required this.image,
    required this.geo,
    required this.scale,
    required this.origin,
    required this.reticleRadius,
    this.checker = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imgRect = Rect.fromLTWH(origin.dx, origin.dy, geo.srcW * scale, geo.srcH * scale);
    if (checker) canvas.drawRect(imgRect, CanvasPainter.checkerPaint);
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    // Nearest-neighbor so pixel art stays crisp.
    canvas.drawImageRect(image, src, imgRect, Paint()..filterQuality = FilterQuality.none);

    final crop = Rect.fromLTWH(
      origin.dx + geo.x * scale,
      origin.dy + geo.y * scale,
      geo.w * scale,
      geo.h * scale,
    );
    // Shade the image OUTSIDE the crop rect (even-odd: outer minus inner).
    final shade = Path()
      ..addRect(imgRect)
      ..addRect(crop)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = const Color(0x99000000));

    // Crop outline.
    canvas.drawRect(
      crop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.amber,
    );

    // Large corner reticles.
    final fill = Paint()..color = Colors.white;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black87;
    for (final c in [crop.topLeft, crop.topRight, crop.bottomLeft, crop.bottomRight]) {
      canvas.drawCircle(c, reticleRadius, fill);
      canvas.drawCircle(c, reticleRadius, ring);
    }
  }

  @override
  bool shouldRepaint(_CropPreviewPainter old) =>
      old.image != image ||
      old.checker != checker ||
      old.scale != scale ||
      old.origin != origin ||
      old.geo.x != geo.x ||
      old.geo.y != geo.y ||
      old.geo.w != geo.w ||
      old.geo.h != geo.h;
}
