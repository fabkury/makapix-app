// The Frames page's id-keyed selection (frames/frame_selection.dart). Pure Dart, no engine.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/frames/frame_selection.dart';

void main() {
  const order = [10, 11, 12, 13, 14, 15]; // frame ids in roll order

  test('toggle adds, removes, and moves the anchor', () {
    var s = FrameSelection.empty;
    s = s.toggle(12);
    expect(s.ids, {12});
    expect(s.anchorId, 12);
    s = s.toggle(14);
    expect(s.ids, {12, 14});
    expect(s.anchorId, 14);
    s = s.toggle(12);
    expect(s.ids, {14});
    expect(s.anchorId, 12, reason: 'the last touched tile anchors even when deselected');
  });

  test('setOnly replaces everything and anchors', () {
    final s = FrameSelection(ids: {10, 11}, anchorId: 10).setOnly(15);
    expect(s.ids, {15});
    expect(s.anchorId, 15);
  });

  test('removeAll drops members, ignores strangers, and keeps or moves the anchor', () {
    final s = FrameSelection(ids: {10, 11, 12}, anchorId: 10);
    final a = s.removeAll([11, 99]);
    expect(a.ids, {10, 12});
    expect(a.anchorId, 10);
    final b = s.removeAll([10], anchor: 12);
    expect(b.ids, {11, 12});
    expect(b.anchorId, 12);
    final c = s.removeAll([10]);
    expect(c.anchorId, 10, reason: 'the anchor is a position, not a member');
  });

  test('rangeTo adds the span in either direction and keeps the anchor', () {
    var s = FrameSelection.empty.toggle(12);
    s = s.rangeTo(14, order);
    expect(s.ids, {12, 13, 14});
    expect(s.anchorId, 12);
    s = s.rangeTo(10, order);
    expect(s.ids, {10, 11, 12, 13, 14}, reason: 'backwards from the anchor, additive');
    expect(s.anchorId, 12);
  });

  test('rangeTo without a usable anchor is a toggle', () {
    expect(FrameSelection.empty.rangeTo(13, order).ids, {13});
    final gone = FrameSelection(ids: {10}, anchorId: 99).rangeTo(13, order);
    expect(gone.ids, {10, 13});
    expect(gone.anchorId, 13);
  });

  test('selectAll, invert, cleared', () {
    final all = FrameSelection.empty.selectAll(order);
    expect(all.ids, order.toSet());
    final some = FrameSelection(ids: {10, 12}, anchorId: 12);
    expect(some.invert(order).ids, {11, 13, 14, 15});
    expect(some.invert(order).anchorId, 12);
    expect(some.cleared().isEmpty, isTrue);
    expect(some.cleared().anchorId, isNull);
  });

  test('retain drops vanished members and a vanished anchor', () {
    final s = FrameSelection(ids: {10, 12, 14}, anchorId: 14).retain({10, 11, 12});
    expect(s.ids, {10, 12});
    expect(s.anchorId, isNull);
    final kept = FrameSelection(ids: {10, 12}, anchorId: 12).retain({10, 12});
    expect(kept.anchorId, 12);
  });

  test('replaceWith keeps the anchor when it survives, else takes the first', () {
    final s = FrameSelection(ids: {10, 12}, anchorId: 12);
    expect(s.replaceWith([12, 13]).anchorId, 12);
    expect(s.replaceWith([13, 14]).anchorId, 13);
    expect(s.replaceWith(const []).anchorId, isNull);
  });

  test('toIndices maps through the live index map, sorted, skipping unknown ids', () {
    final s = FrameSelection(ids: {15, 10, 77});
    expect(s.toIndices({10: 0, 11: 1, 15: 5}), [0, 5]);
  });

  test('signature, equality, and hashCode follow the membership and the anchor', () {
    final a = FrameSelection(ids: {12, 10}, anchorId: 10);
    final b = FrameSelection(ids: {10, 12}, anchorId: 10);
    expect(a.signature, '10,12');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == FrameSelection(ids: {10, 12}, anchorId: 12), isFalse);
    expect(a == FrameSelection(ids: {10}, anchorId: 10), isFalse);
  });

  test('the id set is unmodifiable', () {
    final s = FrameSelection(ids: {1});
    expect(() => s.ids.add(2), throwsUnsupportedError);
  });
}
