# Gesture safety — coexisting with Android and iOS system navigation

*Foundational rules and the resulting redesign, decided 2026-07-31 after the first Android
device pass of Animator v0.1 collided with system navigation gestures. This document is the
inventory of what the OS claims, the rules that follow, and the decided layout + interaction
grammar that satisfies them. The v0.1 build on the `animator` branch predates these
decisions; bringing it into conformance is the next implementation step. The rules
themselves are app-wide physics and are recorded in [CONTEXT.md](../../CONTEXT.md); this
document applies them to the Animator.*

## 1. What the device pass showed

v0.1 placed the timeline flush against the physical bottom of the screen
(`SafeArea(bottom: false)`) and mapped frame 0 / the last frame to the physical left/right
edges. On a gesture-navigation Android phone that is a collision course:

- Grabbing the Playhead (or a loop handle, or a Key) near either end of the timeline starts
  a drag inside the **Back-gesture** zone — the OS takes it; the app never sees it.
- Scrubbing sideways along the bottom of the screen *is* the **app-switch** gesture on the
  bottom bar. The most-executed interaction in the tool was parked on the one screen region
  the OS refuses to share.

These are not bugs to patch around; they are constraints the layout must be designed
against — the way the Android allocator wall is for memory
([docs/memlab/REPORT.md](../memlab/REPORT.md)).

## 2. Inventory: what the OS claims

### Android (gesture navigation — the default since Android 10)

| Gesture | Trigger zone | Collides with |
|---|---|---|
| Back | Horizontal swipe **starting** in a ~24–32 dp band at the left or right edge (user-widenable in settings), full screen height | Any drag that must start near a side edge: timeline ends, loop handles, Actors parked at an edge |
| Home | Swipe up from the bottom gesture bar | Vertical drags near the bottom |
| Quick app switch | Horizontal swipe **along** the bottom gesture bar | A bottom-docked scrub gesture, exactly |
| Recents | Swipe up + hold from the bottom | The same zone |
| Assistant (some OEMs) | Diagonal swipe from a bottom **corner** | Corner interactions |
| Notification shade / quick settings | Swipe down starting at the top edge | Drags starting at the very top |

### iOS

| Gesture | Trigger zone | Collides with |
|---|---|---|
| Home / app switcher | Swipe up from the home-indicator zone; horizontal swipe **along** the indicator = quick app switch | The same bottom collision as Android |
| Notification Center / Control Center | Swipe down from the top edge (left/center vs. top-**right**) | Top-edge drag starts; the top-right corner |
| Reachability | Short swipe down in the bottom zone | The bottom again |
| iPad: Dock / Slide Over / multitasking | Short swipe up from the bottom; right-edge swipe; 4–5-finger system gestures | The bottom; the right edge |

iOS has **no system side-edge Back gesture** — left-edge back-swipe is an in-app navigation
convention, and the Animator is a mounted pillar, not a pushed route. The bottom is the
enemy both platforms share.

### Facts that shape the solution space

- The OS claims drags that **start** in a zone. A drag that starts inside the screen and
  *ends* at an edge is delivered normally — "scrub toward frame 0" is safe; "grab the
  Playhead already parked at frame 0" is not.
- A **long-press before dragging defeats edge interception** — the system only claims
  immediate flings from the edge (launchers rely on this).
- Android's opt-out (`View.setSystemGestureExclusionRects`) covers **side edges only**, is
  capped at 200 dp of height per edge, and needs a platform channel in Flutter. **The bottom
  bar is mandatory** — no app can reclaim Home/app-switch. No API rescues a bottom-docked
  drag surface.
- iOS's opt-out (`preferredScreenEdgesDeferringSystemGestures`) merely defers: the first
  swipe shows the indicator, the second one acts. Apple reserves it for immersive contexts.
- Flutter reports the live zones as `MediaQuery.systemGestureInsets` — **zero on the sides
  for 3-button-navigation users** — so layouts can adapt instead of paying for gutters
  everywhere.

## 3. The rules

Recorded app-wide in [CONTEXT.md](../../CONTEXT.md); restated here as the Animator's
contract:

- **R1 — Side edges.** No interaction may *require* starting a drag inside the side gesture
  insets. Taps are fine; drags may *end* there.
- **R2 — Bottom.** No interaction may require starting a drag in the bottom gesture zone,
  and tap targets sit *above* the home indicator.
- **R3 — Top.** No drag starts at the very top edge; a tap-only top band buffers the shade
  and Notification/Control Center.
- **R4 — Corners.** Nothing requires precision at a screen corner (Assistant diagonals,
  Control Center).
- **R5 — Pannable surfaces need an edge story.** Any surface whose content can end up
  parked at an edge (the Stage; the timeline's ends) gets a deliberate answer — indirect
  manipulation, scroll padding, or a rescue gesture — never luck.

## 4. The decided design

### 4.1 The vertical stack: drags in the middle, taps at the extremes

Portrait, top to bottom (landscape keeps its side band and applies the same ordering inside
its main column):

| Band | Contents | Input |
|---|---|---|
| Top band | menu · title · frame readout · fit · cast | Taps (buffers the top edge — R3) |
| Stage | the Scene | The full grammar (§4.3) |
| **Timeline** | Strip / Tracks / Focus | **All timeline drags — lifted off the bottom** |
| **Transport dock** | play · loop · zoom level · easing chip · undo · redo | **Taps only** — the one input the bottom zone tolerates (R2) |
| **Tooltip strip** | the safe-area pad under the dock | **Passive text, nothing interactive**: live values during gestures ("frame 12 → 15", "rot 45°"), a context hint when idle, brief confirmations after actions (absorbing some snackbar duty) |

The swap costs nothing — it is a reorder, not an addition — and improves adjacency: the
timeline now sits directly under the Stage it controls, and the previously dead
home-indicator padding becomes the tooltip strip.

### 4.2 Adaptive side gutters on the timeline

The timeline's *content* is inset horizontally by the queried `systemGestureInsets`
(~24–32 dp per side on gesture-nav Android, collapsing to a small cosmetic margin on
3-button devices and on iOS). Frame 0's tick, the Playhead at frame 0, and the loop-start
handle all live inboard of the Back zone (R1). Supporting mechanics:

- The x↔frame mapping (`TimelineLayout`) owns the insets; the gutters themselves are not
  part of the drag surface (a two-finger time-zoom cannot start in them either).
- **Over-scroll padding** in Tracks and Focus: the timeline scrolls ~half a screen past
  both ends, so frame 0 or the last frame can be brought to mid-screen before grabbing Keys
  or loop handles there (R5). Strip (fit-all) relies on the gutters alone.
- Endpoints need no dedicated buttons: scrubbing is absolute (tap jumps, drag follows), and
  a drag *ending* at an edge is safe — frame 0 is always one safe drag away.
  (Go-to-start/end taps were considered and declined; the dock stays lean.)

### 4.3 The Stage grammar: select, then act — anywhere

The founding stance ("the stage is the editor",
[03-smartphone-approaches.md](03-smartphone-approaches.md) §1) stays; the gesture
vocabulary changes to make edge-parked Actors a non-problem and to remove the easiest
mis-trigger:

- **Tap selects** (taps at edges are safe); a tap on empty Stage deselects.
- **A one-finger drag starting anywhere moves the selected Actor** (relative delta). The
  drag never has to begin on the Actor's pixels — an Actor hugging a screen edge is moved
  from mid-screen (R1/R5), and the finger no longer covers the art being posed.
- **Two fingers always pan/zoom the view.** No actor pinch. One finger acts, two fingers
  navigate — the Editor's exact grammar, now with zero ambiguity.
- **A Move | Rotate mode toggle lives in the Actor pill** (the floating pill near the
  selection). It exists only while something is selected and **auto-resets to Move**
  whenever the selection changes or clears — no stale-mode surprises. In Rotate mode the
  one-finger drag **orbits the pivot**: the angle follows the finger's bearing with the
  existing 15° snap stops, haptics, and snap guides; distance from the pivot is natural
  leverage (farther = finer), with a minimum-radius guard against degenerate near-pivot
  touches.
- **Scale is deliberately not a gesture.** Pixel art overwhelmingly wants 1:1, and
  accidental pinch-scaling was the design's likeliest mis-trigger. Scale moves to the
  **Transform sheet** — a section grouping scale (slider 0.1×–8×, detent at 1.0,
  tap-to-type), flips, pivot numerics, and precise x/y/rotation entry. Everything there
  routes through `SetAtPlayhead`, so auto-key records these edits exactly like gestures.
- **The pivot keeps its on-stage ⊕ drag handle** (pivot placement is inherently spatial),
  with the numeric fallback in the Transform sheet.
- Auto-key semantics are untouched: the mode toggle routes the one-finger drag; what gets
  recorded, and when, does not change.

### 4.4 The universal rescue: hold-then-drag

Wherever an edge drag-start remains physically possible (an Actor zoomed to hug an edge; a
loop handle at frame 0 in Strip on a device with an extra-wide Back zone), a **~150 ms hold
before dragging** is delivered to the app even inside Android's Back zone. A silent safety
net on every drag surface — never the taught path, always available.

## 5. Considered and rejected (or deferred)

| Option | Verdict |
|---|---|
| Android `setSystemGestureExclusionRects` on the timeline ends; iOS deferred bottom edge | **Deferred** — the design solves it; revisit only if a future device pass still shows friction. Stays inside platform guidance and out of platform-channel code. |
| Immersive full-screen "focus mode" (hide system bars; first swipe reveals them) | **Not the foundation** — disorienting, two-step exit. At most a future opt-in. |
| Floating-island timeline card | A cosmetic variant of the gutters; not adopted — the flat band with adaptive insets reads cleaner in this UI. |
| Go-to-start/end transport buttons | Declined — endpoints are reachable via safe drag-ends plus over-scroll; the dock stays lean. |
| Relative/jog scrubbing | Unnecessary once the strip is inset; absolute scrubbing is more direct. |
| Two-finger twist-on-Actor for rotation (pinch component ignored) | Rejected — reintroduces start-point sensitivity and makes view-zoom fail whenever fingers land on the Actor. |
| Sheet-only rotation | Rejected — rotation is a primary animated property; burying it taxes the core loop. |

## 6. Verification checklist (the next device pass)

On a gesture-navigation Android phone, mirrored on iOS:

- [ ] Scrub from frame 0 and back to frame 0; grab the Playhead parked at both ends.
- [ ] Drag loop handles at both extremes; drag Keys at frame 0 and the last frame (Tracks
      and Focus, using over-scroll).
- [ ] Move and rotate an Actor parked half-off each screen edge without panning first.
- [ ] Every transport-dock control answers a tap, while Back / Home / app-switch still work
      normally over the dock.
- [ ] The tooltip strip shows live values during a drag and never intercepts input.
- [ ] On a 3-button-navigation device: the gutters collapse and nothing feels inset.
- [ ] Deliberate system gestures (Back, Home, app switch) still work everywhere outside an
      intentional drag.
