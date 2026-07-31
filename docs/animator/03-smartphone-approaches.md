# Q3 — Delivering a first-class animation workflow, smartphone-first

*Approaches, not screens: the design stances that make a phone animator pleasant instead of a
shrunken desktop tool. The Editor already proved the app can host a deep creative tool in a
6-inch portrait window; this document is about extending that proof to time.*

## 1. The founding stance: the stage is the editor

Desktop animation tools are timeline-centric: the timeline is the document and the viewport is
a preview. On a phone this must invert. **The stage (canvas) is the primary editing surface;
the timeline is an instrument panel.** Users animate by *doing things to props at moments in
time*, not by managing rows of keyframes:

- **Scrub, then touch.** The core loop is: drag the Playhead → select an Actor and drag it
  into pose → a Key drops (auto-key) → scrub to feel it → adjust. Zero buttons in the loop.
- **Select, then act — anywhere.** Tap selects; a one-finger drag starting *anywhere* on the
  Stage moves the selected Actor (relative delta — the finger never covers the art, and an
  Actor parked at a screen edge stays grabbable). With the Actor pill's mode toggle on
  Rotate, the same drag orbits the pivot with 15° snap stops. Two fingers always pan/zoom
  the view: one finger acts, two fingers navigate — the Editor's exact grammar. Scale is
  deliberately *not* a gesture (pixel art overwhelmingly wants 1:1; accidental pinch-scaling
  was the likeliest mis-trigger) — it lives in the Transform sheet with the other precision
  edits. The platform physics behind this grammar:
  [06-gesture-safety.md](06-gesture-safety.md). (Direct manipulation remains the phone's
  genuine advantage over the desktop:
  [touch scrubbing and direct manipulation feel more immediate than mouse workflows](https://aimensa.com/alight-motion-ui-animation-motion-graphics) —
  the phone is a *better* posing device, and a worse spreadsheet. Design to the strength.)
- **On-stage affordances instead of panels.** Pivot marker on the selected prop; motion path
  drawn as a draggable polyline; ghosts of neighboring keys. Spatial data gets spatial editing.

## 2. Auto-key as the default state of the world

"Record mode" is the single highest-leverage decision in the whole design. If arming it is the
user's job, newcomers pose props, see nothing move, and conclude the app is broken. Therefore:

- **Auto-key is on by default and visually ambient** — e.g. the playhead/scrub area carries a
  quiet "recording" tint whenever the playhead is off a key. Manipulating a prop always records.
- The advanced escape hatch is the reverse: a temporary "adjust without recording" mode for
  staging-only nudges, tucked behind long-press.
- **Every key drop gets feedback** — a tick on the timeline lane, a haptic pulse. The user's
  mental model ("I moved it *at this time*") is built entirely from this feedback.

## 3. One timeline, three zoom levels

The desktop trio (track view / dopesheet / graph editor) collapses into one surface with
semantic zoom, docked just above the bottom tap dock — the screen's bottom-most strip
belongs to taps and the tooltip line, never drags, and the timeline's content sits inside
adaptive side gutters ([06-gesture-safety.md](06-gesture-safety.md)). It echoes the Editor's
low-docked timeline so the app keeps one spatial grammar:

1. **Strip (collapsed, default)** — a single lane: scrubber + aggregated key ticks + loop
   region. The stage gets maximum room. Most sessions never leave this level.
2. **Tracks (one flick up)** — one slim lane per track: duration bars, key ticks, drag keys to
   retime, tap a tween segment to open its easing chip. Track names double as selection.
3. **Focus (tap a track's handle)** — one track expanded: per-property key rows (position /
   rotation / scale / opacity), stretch-select retiming, per-key easing. This is the dopesheet,
   scoped to one prop at a time — full generality without ever showing the full matrix.

Two deliberate differences from the Editor's timeline, so the surfaces are never confused
(risk flagged in [04-recommendations.md](04-recommendations.md) §5): the Animator timeline is
continuous (bars and ticks, not thumbnails), and it is visually distinct (no filmstrip frames).

## 4. Modal focus, inherited from the Editor

The Editor's grammar — one active tool, options in the top row, sheets for depth, long-press
for alternates — transplants cleanly:

- **One selected Actor at a time** carries the interaction: its transform gestures, its pivot,
  its path, its focus lane. (Multi-select exists for retiming, not for posing.)
- **Bottom sheets for occasional depth** — prop settings (pixel-style toggle, cycle options,
  "pin to…"), scene settings, export. Nothing occasional earns persistent chrome.
- **Chips for high-frequency toggles** — easing preset on a selected tween, loop mode,
  ghost-keys on/off. Mirrors the Editor's tool-options row.
- **Landscape earns the wide timeline.** The app already supports editor landscape; in the
  Animator, landscape is the natural "timing pass" posture (timeline stretches, stage shrinks),
  while portrait is the "posing pass" posture. The two-pass workflow from Q1 maps onto device
  orientation for free — worth leaning into rather than merely tolerating.

## 5. Presets as the on-ramp, keys as the truth

The blank-stage problem (nothing moves, user doesn't yet think in keys) is solved by verbs:

- **Motion presets** — select a prop, tap "bounce / slide in / spin / shake / pop", get real,
  editable keys placed on the timeline. The preset is scaffolding, not a black box: opening
  what it made *is* the keyframe tutorial.
- **Template scenes** — new-scene flow offers tiny complete examples (a bouncing ball, a
  two-prop parallax, a sprite-swap blink) the user can pick apart. In an app with a social
  pillar, templates can eventually be *community things* — but that's the Club section's topic.
- **Progressive concept reveal** — props/keys/tweens on day one; cycles surface the first time
  an animated prop is imported ("this prop has its own loop — it keeps playing while you
  animate it"); "pin to" surfaces in the prop sheet; paths surface when a position tween is
  tapped on stage. Nothing is taught before it is needed.

## 6. Touch honesty: fat targets, snap, haptics

Keys and playheads are precision objects; fingers are not. Standard mitigations, stated as
commitments:

- **Targets ≥ the platform minimum** even when lanes are slim (the tick is small; its hit area
  is not). Dragging a key magnifies its local neighborhood (the classic text-cursor loupe,
  applied to time).
- **Snap everything, physically.** Keys *live* on frame boundaries (the decided frame-grid
  timing model, [ADR-0001](../adr/0001-frame-grid-timing.md) — snapping in time isn't an
  aid, it's the truth) and additionally snap to other Keys and loop edges; Actors snap to the
  pixel grid (pixel-native rendering makes this the truth too), to canvas center/edges, to
  15° rotation stops — each snap with a haptic tick. Snapping is how a thumb achieves pointer
  precision.
- **Numbers on demand, never required.** Any snapped drag can be finished exactly; the focus
  lane offers a numeric stepper for the rare exact need (x = 32, rotation = 90°). Typing is
  the exception path, not the workflow.
- **Two-finger timeline gestures** — pinch zooms time, two-finger drag pans it, matching every
  mobile video editor users have touched.
- **Respect the OS's own gestures.** No interaction requires starting a drag inside a system
  gesture zone (screen edges, the bottom bar); the rules and the layout that satisfies them
  are load-bearing design, not polish — [06-gesture-safety.md](06-gesture-safety.md).

## 7. Preview truth as a feature

A pixel-native animator can make a promise general mobile tools break: **what you scrub is
what exports.** Quantized positions, real easing, exact frame timing — guaranteed *by
construction* now that Scene frame rates come from a GIF-representable list and Keys live on
the frame grid ([ADR-0001](../adr/0001-frame-grid-timing.md)) — and correct loop behavior.
The one disclosed exception: semi-transparency in GIF exports is thresholded, and the export
flow says so ([01-features-landscape.md](01-features-landscape.md) §2.6). Every place the
preview is honest, iteration speeds up, because users stop exporting "just to check." This
costs UI nothing and buys trust — the cheapest first-class feel available.

## 8. The session shape: many small loops

Phone creative sessions are short and frequent. The design should assume a scene is built
over many two-minute sittings:

- **Zero-cost resume** — the scene reopens exactly where it was left: playhead, selection,
  zoom, loop region. (The Editor's session-restore culture, extended to temporal state.)
- **Loop-while-editing** — playback can keep looping while props are adjusted; the loop *is*
  the workspace during the polish pass. Live tuning against a running loop is a delightfully
  phone-native way to animate — and doubly rewarding when the loop is the thing being perfected
  for the feed.
- **Glanceable progress** — the strip view shows the whole scene's rhythm at a glance, so a
  two-minute sitting can start with orientation instead of archaeology.

## 9. What "first-class" ultimately means here

Not feature parity with Spine — *workflow* parity: blocking, timing, and polish each have a
posture in which they are pleasant. Blocking = portrait, stage-first, auto-key gestures.
Timing = landscape (or Tracks zoom), drag-to-retime, snap and haptics. Polish = loop-while-
editing with easing chips. If each pass feels like the app was built for that pass, the tool
is first-class regardless of how many desktop features it declined to port.

## References

[Alight Motion touch/UX observations](https://aimensa.com/alight-motion-ui-animation-motion-graphics) ·
[Alight Motion keyframing](https://alightmotionapp.net/keyframing-tools/) ·
[FlipaClip](https://apps.apple.com/us/app/flipaclip-draw-2d-animation/id1101848914) ·
[Spine in depth](http://esotericsoftware.com/spine-in-depth) ·
[PixelOver manual](https://docs.pixelover.io/manual/introduction/)
