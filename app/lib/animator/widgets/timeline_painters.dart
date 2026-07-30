// Timeline painters — the one-timeline surface's three zoom levels share these: the ruler
// (frame labels, playhead, loop dimming, auto-key recording tint), the Strip lane
// (aggregated ticks + loop handles), a per-Actor Track lane (duration bar + merged key
// ticks + tween segments), and a Focus property row. Geometry comes exclusively from
// TimelineLayout so painting and hit-testing can never disagree.
import 'package:flutter/material.dart';

import 'package:makapix_club/animator/model/timeline_layout.dart';

const Color kLaneBg = Color(0xFF15171A);
const Color kLaneAltBg = Color(0xFF1A1C1F);
const Color kBarColor = Color(0xFF26292E);
const Color kAccent = Color(0xFF4080C0);
const Color kRecordTint = Color(0x22CC4444);
const Color kLoopDim = Color(0x66000000);

/// The shared ruler: labels + playhead + loop dimming + the ambient auto-key recording tint
/// (shown while a selected Actor has NO key at the playhead — the design's quiet signal that
/// manipulating will record).
class TimelineRulerPainter extends CustomPainter {
  final TimelineLayout layout;
  final int playhead;
  final int loopA, loopB;
  final bool recordTint;
  const TimelineRulerPainter({
    required this.layout,
    required this.playhead,
    required this.loopA,
    required this.loopB,
    required this.recordTint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kLaneBg);
    if (recordTint) {
      canvas.drawRect(Offset.zero & size, Paint()..color = kRecordTint);
    }
    // Loop dimming: outside [loopA, loopB].
    final dim = Paint()..color = kLoopDim;
    final loopLeft = layout.leftOfFrame(loopA);
    final loopRight = layout.leftOfFrame(loopB) + layout.pxPerFrame;
    if (loopLeft > 0) {
      canvas.drawRect(Rect.fromLTRB(0, 0, loopLeft.clamp(0, size.width), size.height), dim);
    }
    if (loopRight < size.width) {
      canvas.drawRect(
          Rect.fromLTRB(loopRight.clamp(0, size.width), 0, size.width, size.height), dim);
    }
    // Frame labels.
    final step = layout.labelStep();
    final (first, last) = layout.visibleRange();
    for (var f = (first ~/ step) * step; f <= last; f += step) {
      final x = layout.xAtFrame(f);
      final tp = TextPainter(
        text: TextSpan(
            text: '$f',
            style: const TextStyle(fontSize: 9, color: Colors.white38)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, 2));
      canvas.drawLine(
        Offset(x, size.height - 4),
        Offset(x, size.height),
        Paint()
          ..strokeWidth = 1
          ..color = Colors.white24,
      );
    }
    // Playhead.
    final px = layout.xAtFrame(playhead);
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..strokeWidth = 1.4
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(TimelineRulerPainter old) =>
      old.layout.pxPerFrame != layout.pxPerFrame ||
      old.layout.scroll != layout.scroll ||
      old.layout.width != layout.width ||
      old.layout.frameCount != layout.frameCount ||
      old.playhead != playhead ||
      old.loopA != loopA ||
      old.loopB != loopB ||
      old.recordTint != recordTint;
}

/// Strip zoom level: one lane = scrubber + aggregated key ticks + loop-edge handles.
class StripLanePainter extends CustomPainter {
  final TimelineLayout layout;
  final List<double> tickXs; // pre-aggregated by aggregateTicks
  final int playhead;
  final int loopA, loopB;
  final bool recordTint;
  const StripLanePainter({
    required this.layout,
    required this.tickXs,
    required this.playhead,
    required this.loopA,
    required this.loopB,
    required this.recordTint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    TimelineRulerPainter(
      layout: layout,
      playhead: playhead,
      loopA: loopA,
      loopB: loopB,
      recordTint: recordTint,
    ).paint(canvas, size);
    // Aggregated key ticks along the lane's middle band.
    final tick = Paint()
      ..strokeWidth = 2
      ..color = Colors.white70;
    for (final x in tickXs) {
      canvas.drawLine(
          Offset(x, size.height * 0.35), Offset(x, size.height * 0.75), tick);
    }
    // Loop-edge handles.
    final handle = Paint()..color = kAccent;
    for (final f in [loopA, loopB]) {
      final x = f == loopA ? layout.leftOfFrame(f) : layout.leftOfFrame(f) + layout.pxPerFrame;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, size.height * 0.55), width: 6, height: size.height * 0.6),
            const Radius.circular(3)),
        handle,
      );
    }
  }

  @override
  bool shouldRepaint(StripLanePainter old) =>
      old.layout.pxPerFrame != layout.pxPerFrame ||
      old.layout.scroll != layout.scroll ||
      old.tickXs != tickXs ||
      old.playhead != playhead ||
      old.loopA != loopA ||
      old.loopB != loopB ||
      old.recordTint != recordTint;
}

/// Tracks zoom level: one per-Actor lane — duration bar, merged key ticks, selection tint.
class TrackLanePainter extends CustomPainter {
  final TimelineLayout layout;
  final Set<int> keyFrames;
  final int playhead;
  final bool selected;
  final int? draggedFrom;
  final int? draggedTo;
  const TrackLanePainter({
    required this.layout,
    required this.keyFrames,
    required this.playhead,
    required this.selected,
    this.draggedFrom,
    this.draggedTo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..color = selected ? const Color(0xFF20242A) : kLaneAltBg);
    // Duration bar across the whole scene.
    final barTop = size.height * 0.3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
            (-layout.scroll).clamp(-4, size.width),
            barTop,
            (layout.contentWidth - layout.scroll).clamp(0, size.width),
            size.height * 0.7),
        const Radius.circular(3),
      ),
      Paint()..color = kBarColor,
    );
    // Key ticks (the dragged key rides the finger at draggedTo).
    for (final f in keyFrames) {
      final drawn = (f == draggedFrom && draggedTo != null) ? draggedTo! : f;
      final x = layout.xAtFrame(drawn);
      if (x < -8 || x > size.width + 8) continue;
      final isDragged = f == draggedFrom && draggedTo != null;
      canvas.drawLine(
        Offset(x, size.height * 0.2),
        Offset(x, size.height * 0.8),
        Paint()
          ..strokeWidth = isDragged ? 3 : 2
          ..color = isDragged ? Colors.amber : Colors.white70,
      );
    }
    // Playhead hairline through the lane.
    final px = layout.xAtFrame(playhead);
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white38,
    );
  }

  @override
  bool shouldRepaint(TrackLanePainter old) =>
      old.layout.pxPerFrame != layout.pxPerFrame ||
      old.layout.scroll != layout.scroll ||
      old.keyFrames != keyFrames ||
      old.playhead != playhead ||
      old.selected != selected ||
      old.draggedFrom != draggedFrom ||
      old.draggedTo != draggedTo;
}

/// One key on a Focus property row (frame + selection + tween-to-next).
class FocusKey {
  final int frame;
  final String tween;
  const FocusKey(this.frame, this.tween);
}

/// Focus zoom level: one property row of the focused Actor — keys as diamonds, tween
/// segments labeled by dash style (hold = no connecting line).
class PropertyRowPainter extends CustomPainter {
  final TimelineLayout layout;
  final List<FocusKey> keys; // sorted by frame
  final int playhead;
  final int? selectedKeyFrame;
  final int? draggedFrom;
  final int? draggedTo;
  const PropertyRowPainter({
    required this.layout,
    required this.keys,
    required this.playhead,
    this.selectedKeyFrame,
    this.draggedFrom,
    this.draggedTo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kLaneAltBg);
    final midY = size.height / 2;

    double xOf(int frame) {
      final drawn = (frame == draggedFrom && draggedTo != null) ? draggedTo! : frame;
      return layout.xAtFrame(drawn);
    }

    // Tween segments between consecutive keys (hold draws no line — the value jumps).
    for (var i = 0; i + 1 < keys.length; i++) {
      if (keys[i].tween == 'hold') continue;
      final x0 = xOf(keys[i].frame);
      final x1 = xOf(keys[i + 1].frame);
      canvas.drawLine(
        Offset(x0, midY),
        Offset(x1, midY),
        Paint()
          ..strokeWidth = 1.4
          ..color = kAccent.withValues(alpha: 0.7),
      );
    }
    // Key diamonds.
    for (final k in keys) {
      final x = xOf(k.frame);
      if (x < -8 || x > size.width + 8) continue;
      final isSel = k.frame == selectedKeyFrame;
      final isDragged = k.frame == draggedFrom && draggedTo != null;
      final r = isSel || isDragged ? 5.0 : 4.0;
      final path = Path()
        ..moveTo(x, midY - r)
        ..lineTo(x + r, midY)
        ..lineTo(x, midY + r)
        ..lineTo(x - r, midY)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = isDragged ? Colors.amber : (isSel ? Colors.amberAccent : Colors.white70),
      );
    }
    // Playhead hairline.
    final px = layout.xAtFrame(playhead);
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white38,
    );
  }

  @override
  bool shouldRepaint(PropertyRowPainter old) =>
      old.layout.pxPerFrame != layout.pxPerFrame ||
      old.layout.scroll != layout.scroll ||
      old.keys != keys ||
      old.playhead != playhead ||
      old.selectedKeyFrame != selectedKeyFrame ||
      old.draggedFrom != draggedFrom ||
      old.draggedTo != draggedTo;
}
