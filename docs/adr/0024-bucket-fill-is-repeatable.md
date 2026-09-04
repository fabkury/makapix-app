# The Bucket fill joins the Repeat set; Repeat means "the last repeatable op", period

**Decided 2026-09-04.** Engine: `RepeatOp::Bucket` + `Session::flood_fill_with` /
`bucket_record` in `crates/engine/src/session.rs`; the record is armed by the Bucket tap
(`pointer_down`, promoted on the stroke's commit) and by the off-finger Fill button
(`fill_cursor`). Shell: no change — the Redo tile's Repeat face already keys off the state
probe. Journal: `#mkpxj 3` (`app/lib/editor/replay/journal_format.dart`).

ADR 0017 closed the repeatable set at adjustment bakes, layer-scoped transforms, and the
paste-stamp, and said strokes stay out because they would need input replay. A Bucket tap is
a stroke by plumbing — a `PointerDown`/`PointerUp` pair — but it carries one point and no
path, so it fits the record model the other ops use: parameters snapshotted at commit, target
live. This ADR adds **exactly the Bucket fill**; it does not generalize to "positioned ops"
or reopen strokes. Each future candidate is its own decision.

**What is snapshotted (user decisions):** the seed as a **canvas** pixel (storage
coordinates hang off the gutter origin, which a canvas resize moves; the canvas pixel is what
the artist tapped), the **primary color** at the tap (the ADR 0017 rule — "same region,
same color on the next frame"; the live-color alternative was declined as the odd one out),
and the Threshold, Contiguous, and All-layers settings. Decided live at Repeat time, like
every target: the active frame and layer, the selection clip, and the All-layers composite.
A seed that has left the canvas after a shrink is refused by the flood itself — an empty
edit, nothing recorded, the same silence the other verbs keep.

**Arming is unconditional on effect.** A tap that changed no pixels (filling a region with
its own color) still becomes the record: the record is the tap's parameters, not its diff,
as Flip already arms. Arming happens at the stroke's **commit**, not at the press where the
fill lands: a two-finger gesture that began as a fill reverts the pixels through
`cancel_stroke` and must not clobber the record it never earned, so the armed record rides
the `Stroke` and is promoted only by `pointer_up` / `settle_open_edits`.

**Repeat is "the last repeatable op", period.** The cost was named and accepted: Bucket taps
are frequent and cheap, so "apply Levels, patch one spot with Bucket, step frame, Repeat"
now re-fills instead of re-leveling. A recency or expense rule that let an adjustment record
outlive later fills was declined — one rule, no exceptions.

**Replay fork, accepted.** `Repeat()` shipped in 1.7.0+35 on both stores, so a journal
holding a repeatable op, then a Bucket tap, then `Repeat()` replays differently from today
on; the reverse holds for a 1.7.0 app replaying a newer journal. Per ADR 0015 the engine has
one behavior and nothing branches on the epoch; the inert `#mkpxj` marker bumps to 3 so the
boundary is recorded, and every past epoch stays readable (the header-recognition test
guards that). The affected population is judged to be zero at this size of user base.
