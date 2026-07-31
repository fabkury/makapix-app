# Q2 — Prioritization: UI cost vs. usefulness on a phone

*Ranking the Q1 landscape for a smartphone-first app. The currency being spent is not
engineering effort (out of scope here) but **screen real estate, gesture budget, and concept
load** — the three resources a phone UI actually runs out of. The 2026-07-30 grilling turned
this ranking into commitments: §5 records the decided v0.1 slice.*

## 1. How "UI cost" is judged

A feature's UI cost on a phone is the sum of:

- **Chrome** — persistent pixels it demands (panels, rows, handles). The Editor's three-row
  grammar shows how little there is to spend.
- **Gestures** — how many distinct touch interactions it needs, and whether they collide with
  ones already claimed by the app (drag, pinch, long-press are near-exhausted on any canvas
  app) or by the OS itself (edge and bottom-bar navigation —
  [06-gesture-safety.md](06-gesture-safety.md)).
- **Concept load** — what the user must hold in their head before the feature makes sense.
  Keyframes alone are a real hurdle for newcomers; every additional concept (parenting, curves,
  time-remap) multiplies.
- **Precision demand** — features needing pointer-precision (grabbing a 4px key marker, a
  Bézier handle) are expensive on touch even when visually small.

Usefulness is judged against the thesis in the README: the Animator wins where keyframing
beats redrawing — for an Editor graduate, on a phone, publishing loops to the Club.

## 2. The tiers

### Tier 0 — the tool does not exist without these

| Feature | UI cost | Notes |
|---|---|---|
| Scene setup (size ≤256, fps from the GIF-safe list, duration, background) | Low | One-time sheet; the Editor's new-drawing flow already sets the pattern. |
| Import Props (.mkpx / PNG / GIF / WEBP; Whole/Parts card for layered .mkpx) | Low | Reuses gallery/file-picker patterns that already exist in the app. |
| Place / stack / duplicate Actors | Low | Direct manipulation; z-order is a list. |
| Transform Keys: position, uniform scale, rotation, flip, opacity, pivot | **Low, if auto-key** | The Stage *is* the input surface: select-then-drag, Rotate-mode orbit ([06-gesture-safety.md](06-gesture-safety.md)); scale is deliberately sheet-only. No inspector typing required for the core loop. |
| Auto-key (record mode) | Low | One armed/disarmed state. It *removes* UI: no "add keyframe" button in the main loop. |
| Tween + easing presets | Low–Med | A per-tween chip cycling a curated set (linear · ease · ease-in · ease-out · hold). The *graph editor* is what's expensive; presets deliver ~90% of its value for ~5% of its cost. |
| Hold/step keys | Low | One member of the easing set, not a separate concept. Carries all sprite-swapping. |
| Scrub + loop playback | Low | Playhead drag plus one play button. Must be flawless, not minimal — this is the most-executed interaction in the tool. |
| Track timeline (compact) | **Med–High** | The honest price of the pillar: a new timeline surface distinct from the Editor's filmstrip. Where most of the design effort in Q3 goes. |
| Export GIF/WEBP + integer upscale | Low | Mirrors the Editor's publish/export flow. |
| Undo/redo, autosave, project gallery | Low | Direct transplants of existing app patterns. |

### Tier 1 — what makes it *first-class* rather than a toy

| Feature | UI cost | Value case |
|---|---|---|
| **Animated Props with independent Cycles** | Med | A flapping bird flying a keyframed path — composition of live loops — is *the* effect flipbook tools can't match and feeds directly on Editor-made animations. Cost is conceptual (two clocks), tamed by the decided quantize-at-import rule ([ADR-0001](../adr/0001-frame-grid-timing.md)). **Pulled forward into the v0.1 slice** (§5) so imported animations animate from day one. |
| **Loop/work-region tools** | Low | Loop region, ping-pong, "make cycle seamless" assist. Disproportionate value: the Club feed plays loops. |
| **Retiming: drag keys, stretch selections** | Med | Pass 2 (timing) lives here; without it users re-pose instead of re-timing. A compact dopesheet-like *zoom level* of the one timeline — not a separate view. |
| **Anchor/pivot editing** | Low–Med | One draggable pivot marker in a prop-edit state. Unlocks believable rotation (flapping, waving, nodding). |
| **Motion paths on stage** | Med | Spatial trajectory editing is unusually touch-friendly — better on a phone than the desktop-native dopesheet is. Differentiator; candidate for early inclusion. |
| **Parenting (one level: "pin to")** | Med–High concept, Low chrome | "Pin the hat to the head." One level, no chains, no IK — delivers most cutout-character value while staying explainable in one sentence. |
| **Pixel-native motion preview** (quantized scrub, cleanEdge vs. nearest per prop) | Low | Mostly a *rendering honesty* stance plus one style toggle. Identity-defining; cheap. |
| **Onion/ghost of key poses** | Low | One toggle, ghosting keys only (not every frame — tweens make full onion skin less necessary). |
| **Motion presets** ("bounce", "slide in", "shake", "spin") | Low | Presets that *drop editable keys* — simultaneously a beginner on-ramp, a speed tool, and a teaching device (users open them and see how the keys are placed). |

### Tier 2 — nice-to-have, wants evidence before spending

| Feature | UI cost | Why it waits |
|---|---|---|
| Graph/curve editor | High | Touch-hostile precision; presets + an optional per-tween "strength" slider cover most needs. Revisit only if power users ask. |
| Camera (animatable viewport) | Med | Cheap parallax and pans are lovely, but it's another track type and another concept. A "camera is just a special prop" design could make it nearly free — worth a later look. |
| Per-axis scale / skew | Low–Med | Squash & stretch argues for per-axis scale eventually; skew rarely earns its slot in pixel art. |
| Blend modes / opacity effects beyond simple alpha | Med | Palette discipline (GIF export) complicates it; niche demand. |
| Sprite-swap manager UI | Med | Hold keys already enable swapping; a dedicated pose-picker UI is a refinement once real usage shows the pain. |
| Text/titling | Med | Useful for memes and credits; pixel-font questions deserve their own thought. |
| Scene-to-scene assembly (shots) | High | A second level of structure; v1 scenes are single shots. |

### Tier 3 — explicitly out (v1), with reasons

| Feature | Reason |
|---|---|
| Bones/IK rigs, mesh deformation | The skeletal paradigm was ruled out of frame; "pin to" parenting is the ceiling. Spine-class rigging on a phone is a different product. |
| Audio | Out of scope by decision (formats carry none); see [04-recommendations.md](04-recommendations.md) §4. |
| Effects stack (glow, blur, particles) | Aesthetic drift risk (pixel purity) + UI surface + palette chaos at export. Pixel-native effects (color cycling!) can return later as curated, palette-safe presets. |
| Expressions/scripting | Desktop-power-user territory. |
| Drawing tools inside the Animator | **The most important exclusion.** The moment the Animator draws, the pillar boundary dissolves and both tools blur. Editing art = round-trip to the Editor ([04-recommendations.md](04-recommendations.md) §1). One deliberate exception worth debating: a *scene background fill/color*, which is scene setup, not drawing. |

## 3. The cost/value picture at a glance

```
                    │ low UI cost              high UI cost
────────────────────┼────────────────────────────────────────────
 high value         │ auto-key transforms      compact timeline + retiming
                    │ easing preset chips      animated props (two clocks)
                    │ loop tools, scrub        "pin to" parenting
                    │ motion presets           motion paths
                    │ pixel-native preview     │
                    │ pivot editing            │
────────────────────┼────────────────────────────────────────────
 lower value (v1)   │ per-axis scale           graph editor
                    │ ghost-keys toggle        camera / shot assembly
                    │ text (later)             bones/IK, mesh, effects
                    │                          audio
```

Read column-first: ship the entire left-top cell, design the right-top cell carefully (that's
Q3's whole job), sample the left-bottom cell opportunistically, and let the right-bottom cell
wait for demand.

## 4. The two hills worth dying on

1. **The timeline is the only expensive UI the tool is allowed.** Everything else must ride
   the stage (direct manipulation), sheets (the app's existing grammar), or chips. If a feature
   needs a second persistent surface, it goes to Tier 2+ automatically.
2. **Concept budget: three.** A newcomer must succeed knowing only *Props, Keys, Tweens*.
   Parenting, Cycles, and paths may exist, but must be discoverable-later, never prerequisite.
   (Alight Motion demonstrates the failure mode: enormously capable, famously overwhelming —
   the [tutorial ecosystem around it](https://filmora.wondershare.com/advanced-video-editing/how-to-add-keyframes-in-alight-motion.html)
   exists largely because the app itself doesn't teach.)

## 5. The decided v0.1 slice (2026-07-30)

**v0.1 = all of Tier 0, plus Playing Cycles from Tier 1.** The Cycle pull-forward resolves an
incoherence in the original tiering: Tier 0 imports GIF/WEBP, but without Cycles an imported
GIF would freeze on its first frame — an animator where imported animations don't animate.
With Cycles riding along, the v0.1 core loop is genuinely complete: import (including the
layered-`.mkpx` Whole/Parts card), auto-key transforms, easing chips, the compact timeline,
loop playback, Cycles playing, GIF/WEBP export, undo/autosave/gallery.

Still deferred past v0.1: Posing mode, "pin to" parenting, motion presets, motion paths,
stretch-select retiming refinements, and everything in Tiers 2–3. v0.1 is an internal
prototype milestone, not a release.
