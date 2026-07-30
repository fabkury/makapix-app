# Q4 — Recommendations, risks, and resolved questions

*The opinions that don't fit under Q1–Q3: the Editor⇄Animator seam (the real product thesis),
scope guardrails, risks, Club ties — and the questions the 2026-07-30 grilling resolved.*

## 1. The Editor⇄Animator seam is the product, not a feature

Everything else in this folder exists in some form elsewhere. The thing no competitor can
copy is that Makapix owns **both a first-class pixel-art drawing tool and the animation tool
next door**, sharing one gallery, one aesthetic, and one file format family. Three seam
workflows deserve to be designed as carefully as the Animator itself:

- **Layers become limbs.** A layered `.mkpx` drawing imports through a two-choice card —
  *Whole drawing* / *Separate parts*, with a visual preview of the split (decided; the card
  appears only when the file has more than one layer). An artist who draws a character with
  head/body/arms on separate layers has, without knowing it, **rigged a puppet**. This
  retroactively upgrades every layered drawing in every user's gallery into animation-ready
  material — and quietly teaches better layer discipline in the Editor. No mobile tool has
  this; even [PixelOver](https://pixelover.io/) (desktop) requires manual part slicing for
  imported art.
- **Round-trip editing.** "This arm needs a fix" → tap the Actor → *Edit in Editor* → the
  Editor opens that art → save → the Animator picks up the change, Keys untouched. Because
  Scenes are self-contained ([ADR-0002](../adr/0002-self-contained-scenes.md)), the round
  trip edits the **Scene's embedded copy** — the gallery original is untouched, and pulling a
  gallery fix into a Scene is an explicit *re-import from gallery* action. The app already has
  pillar-switching machinery and a pending-request bridge pattern between Club and Editor; the
  product expectation is the same seamlessness. The moment this loop works, the two pillars
  stop being neighbors and become one workflow.
- **Poses as frames.** A multi-frame `.mkpx` imports as a Prop whose frames are Poses — drawn
  in the Editor as a flipbook, performed in the Animator via hold Keys (blink, mouth shapes,
  walk poses). Playing vs. Posing is a per-Actor mode (decided), so the same Prop can loop as
  a Cycle in one Actor and be pose-driven in another. This is the cleanest possible division
  of labor between the two pillars: **the Editor makes the frames; the Animator decides when
  they show.**

## 2. Scope guardrails — what the Animator must refuse to become

- **Not a drawing app.** No brushes, no pixels-on-stage. The pull will be constant ("just a
  quick fix without switching…"); the round-trip must be so fast that the pull loses. The one
  deliberate exception: scene background color, which is Scene setup, not drawing.
- **Not a video editor.** No clips, no footage, no feed-style vertical video ambitions. The
  moment "import a video" appears, the pixel-native identity and the small-canvas UX both die.
- **Not a game-asset pipeline (yet).** Sprite-sheet export, tags-per-cycle, engine metadata —
  a real audience (Aseprite's), a different product. The `.mkps` format shouldn't preclude it;
  v1 shouldn't chase it.
- **Not a rigging tool.** "Pin to" one-level parenting is the ceiling (decided). If demand for
  bones/IK materializes, that's a v3 conversation to have on purpose, not a slope to slide
  down.

## 3. Naming and vocabulary — resolved

The pillar is the **Makapix Animator** (decided 2026-07-30) — parallel to Makapix Editor;
the "names the user" objection applies equally to *Editor* and has never hurt it. Stage,
Studio, and Motion were considered and rejected ("Stage" now names the composition surface
instead). The full vocabulary — Scene · Stage · Cast · Prop · Actor · Track · Key · Tween ·
Playhead · Cycle · Pose — is canonical in [CONTEXT.md](../../CONTEXT.md) and gets the same
strictness the repo already applies to *Makapix Club* vs. *Makapix Editor*. The Scene file is
**`.mkps`** — deliberately *not* named "the animation format," because `.mkpx` drawings are
already animations; `.mkpx` holds drawn frames, `.mkps` holds directed motion.

## 4. Audio: out of scope, and what that costs later

Decided out of scope for v1, and the export formats agree: GIF and animated WEBP carry no
audio. The note for the record: audio is the most-requested growth feature in mobile animation
apps (FlipaClip ships six audio tracks and voice recording), and adding it later implies
(a) a video export format (MP4/WebM), (b) a sync UI (waveform lane in the timeline), and
(c) rights/licensing questions for a social app the moment music enters. None of this needs
solving now; the only cheap insurance is to keep the `.mkps` timeline model open to a
non-visual track type someday, and to not promise users "loops are silent by design" as if it
were a philosophy rather than a version.

## 5. Risks worth writing down now

- **Two timelines, one app.** The Editor has a timeline of drawings; the Animator has a
  timeline of instructions. Users *will* conflate them, and the failure smells like "the app
  is inconsistent." Mitigations: distinct visual language (filmstrip thumbnails vs.
  bars-and-ticks), distinct vocabulary (frames vs. Keys), and never letting one pillar's
  timeline idiom leak into the other.
- **Concept-load cliff.** Keyframing is a real conceptual step up from flipbooking. If the
  first-session experience doesn't produce motion within a minute, the pillar will demo well
  and retain badly. The auto-key + presets + templates trio
  ([03-smartphone-approaches.md](03-smartphone-approaches.md) §2, §5) is the mitigation and
  should be treated as launch-blocking, not polish.
- **Aesthetic drift.** Tweened motion has a "digital slide" look that reads as cheap next to
  hand-animated pixel art; a feed full of Actors sliding linearly across static backgrounds
  would *lower* the Club's perceived quality bar. Mitigations are cultural as much as
  technical: stepped/hold easing as a first-class style, motion presets authored with real
  animation principles (anticipation, overshoot), staircase-honest preview, and template
  scenes that model good taste.
- **The pillar-boundary blur.** Every seam feature in §1 is also a blurring force. The test
  for any future feature: "does this make the Animator better at *directing*, or is it
  sneaking in *drawing*?" The pillar survives only if that question keeps getting asked.
- **Smartphone-first vs. session length.** Animation rewards long sittings; phones don't.
  The many-small-loops session shape ([03-smartphone-approaches.md](03-smartphone-approaches.md)
  §8) is a bet, not a fact — the v0.1 prototype should test whether a Scene genuinely
  survives twenty two-minute sittings.
- **No-propagation surprise.** Self-contained Scenes mean a gallery fix does not ripple into
  Scenes that use the drawing ([ADR-0002](../adr/0002-self-contained-scenes.md)). The
  trade-off is right, but the UX must make "re-import from gallery" discoverable at the
  moment a user goes hunting for the update they expected.

## 6. Club integration (deliberately brief, per the brainstorm frame)

- **Publish** — a Scene exports GIF/WEBP and enters the existing publish flow like any editor
  artwork; the feed does not need to know or care which pillar made a post.
- **Remix, eventually** — the genuinely new possibility: sharing the *Scene* (`.mkps` — one
  self-contained file, by design), not just the baked GIF, so others can retime, reskin, or
  extend it. This rhymes with the app's existing edit/remix direction and with `.mkpx`
  attachments on posts, and could make animation the most remixable content type on the
  platform. Licensing and asset-provenance questions ride along; a topic for its own document.
- **Assets from the Club** — importing a Club post as a Prop (respecting the existing remix
  permission model) turns the whole feed into a prop library. Powerful, and gated on the same
  permission work the Club already has planned ("allow others to edit"). The Club-post
  "Animate" entry point waits for this (decided).
- **Players** — animated loops are exactly what the physical players display; "send Scene to
  player" is a natural export target that already has app-side machinery.

## 7. Questions resolved by the 2026-07-30 grilling

1. **Identity & front door** — a co-equal third pillar; reached via the Contribute hub (its
   Scene gallery) and "Animate this" on drawings in the Editor gallery/Private tab.
2. **Scene size** — Editor parity (1×1–256×256); Props may exceed the Scene up to 1024
   px/side (pans, panoramas).
3. **Timing** — fixed fps from a curated GIF-safe list, Keys on the frame grid, Cycles
   quantized at import ([ADR-0001](../adr/0001-frame-grid-timing.md)).
4. **Frame-rate culture** — frames win over milliseconds: Editor graduates keep thinking in
   frames, and the fps list keeps GIF export exact.
5. **Property set (v1)** — position, rotation, uniform scale, flip, opacity (honest GIF
   thresholding), pivot; per-axis scale deferred.
6. **File** — `.mkps`, fully self-contained
   ([ADR-0002](../adr/0002-self-contained-scenes.md)).
7. **v0.1 slice** — Full Tier 0 plus Playing Cycles
   ([02-prioritization.md](02-prioritization.md) §5).

Still open, deliberately: the feasibility pass (explicitly out of scope for this folder —
cost and consequences deserve their own document before any code), template/preset content
strategy, and everything in Tiers 2–3.

## 8. Closing recommendation

Build the **v0.1 slice** ([02-prioritization.md](02-prioritization.md) §5) and test the three
load-bearing bets against it: auto-key gestures feel right on touch, layered drawings make
thrilling puppets, and small loops fit small sittings. The design decisions above give v0.1 a
stable target — vocabulary, timing model, file semantics, and scope are settled, so the
prototype measures the *experience*, not a moving spec. If the three bets hold, the pillar
graduates to a real spec and a feasibility document; if they don't, this folder documents
exactly which assumption failed and why.
