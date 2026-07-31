# Makapix Animator — design foundation

*The UX/product foundation for the app's third pillar: a first-class, smartphone-first
animation tool for pixel art. Brainstormed and then grilled to decisions on 2026-07-30;
gesture-safety rules and the resulting layout/grammar redesign decided 2026-07-31 after the
first Android device pass. This folder reads as post-decision truth; the two
hardest-to-reverse calls also have ADRs ([0001](../adr/0001-frame-grid-timing.md),
[0002](../adr/0002-self-contained-scenes.md)), and the canonical vocabulary lives in
[CONTEXT.md](../../CONTEXT.md). Documents 01–04 and 06 are UX/product; the technical side
lives in [05-feasibility.md](05-feasibility.md).*

## The idea in one paragraph

The Makapix Editor is a first-class **drawing** tool that happens to produce animations: you
draw every frame, and the timeline is a stack of drawings. The Makapix **Animator** is the
complementary first-class **animating** tool: you bring finished art in — your own `.mkpx`
drawings first and foremost, plus PNG/GIF/WEBP — place it on a Stage, and give it **motion**:
Keys, Tweens, timing, easing, loops. You rarely draw in the Animator; you *direct*. The
output is a GIF/WEBP animation (and a re-editable `.mkps` Scene file). The result is that a
Makapix artist can draw a character's parts once in the Editor and then make that character
walk, bounce, blink, and emote — without redrawing anything, and without leaving their phone.

## Decisions (2026-07-30)

| Area | Decision |
|---|---|
| Identity | **Co-equal third pillar** named **Makapix Animator** — not an Editor sub-mode, not a content-launched flow. |
| Paradigm | **Sprite/timeline compositing** — Actors on Tracks, keyframed transforms, tweening. Not skeletal rigging, not flipbook (the Editor's job). |
| Aesthetic contract | **Pixel-native** — motion computed in subpixel math, always rendered on the pixel grid. |
| Vocabulary | Scene · Stage · Cast · Prop · Actor · Track · Key · Tween · Playhead · Cycle · Pose — canonical in [CONTEXT.md](../../CONTEXT.md). |
| Scene size | **1×1–256×256** (Editor parity). Props may exceed the Scene, capped at **1024 px/side**. |
| Timing | **Fixed fps from a curated GIF-safe list; Keys on the frame grid** ([ADR-0001](../adr/0001-frame-grid-timing.md)). Prop Cycles quantize to the grid at import. |
| Import | Layered `.mkpx` shows a **Whole / Parts** card (>1 layer only). **Playing vs. Posing is a per-Actor mode.** |
| Properties (v1) | Position, rotation, uniform scale, flip H/V, opacity, draggable pivot. Opacity exports true to WEBP; GIF export thresholds it with a notice. |
| Interaction | Auto-key **on by default**; per-Prop pixel style (cleanEdge vs. nearest); one-level **"pin to"** parenting; **one timeline, three zoom levels**. |
| Gesture safety | **No drag may require starting in an OS gesture zone** (decided 2026-07-31): bottom tap dock + tooltip strip, adaptive side gutters, select-then-drag-anywhere Stage grammar with a Move/Rotate mode, scale demoted to the Transform sheet — [06-gesture-safety.md](06-gesture-safety.md). |
| Scene file | **`.mkps`**, fully self-contained — embeds all Prop art ([ADR-0002](../adr/0002-self-contained-scenes.md)). |
| Front door | Contribute-hub entry (Scene gallery) + **"Animate this"** on drawings; Club-post entry waits for remix permissions. |
| v0.1 slice | **Full Tier 0 plus Playing Cycles** (imported GIFs animate); Posing, parenting, presets, paths come after. |
| Primary audience | **Editor graduates** animating their own drawings; external import secondary. |
| Audio | Out of scope for v1 (GIF/WEBP carry none); implications noted in [04-recommendations.md](04-recommendations.md). |

## Document map

| Doc | What it covers |
|---|---|
| [01-features-landscape.md](01-features-landscape.md) | The domain model and feature landscape of sprite/timeline animation, with the Makapix decisions marked. |
| [02-prioritization.md](02-prioritization.md) | Feature tiers ranked by UI cost vs. usefulness on a phone; what v1 includes, defers, and refuses. |
| [03-smartphone-approaches.md](03-smartphone-approaches.md) | The design stances that make a phone animator first-class rather than a shrunken desktop tool. |
| [04-recommendations.md](04-recommendations.md) | The Editor⇄Animator seam, scope guardrails, risks, Club ties, and next steps. |
| [05-feasibility.md](05-feasibility.md) | Technical feasibility on this codebase: reuse maps (Rust + Flutter), the `crates/scene` design sketch, `.mkps` container, FFI seam, memory under the Android wall, phases and risks. |
| [06-gesture-safety.md](06-gesture-safety.md) | The Android/iOS system-gesture inventory, the app-wide collision rules (R1–R5), and the 2026-07-31 layout + interaction-grammar redesign that satisfies them. |

## The one-line thesis

> **The Animator's competition is not other animation apps — it is the Editor's own timeline.**
> The Animator earns its existence only where "redraw it frame by frame" loses to "keyframe it":
> motion of finished art, timing iteration, reuse, and scenes with independently moving parts.
> Every feature in these documents was weighed against that test.

## Precedents consulted

Light research pass, cited in the documents where it changed a conclusion:

- [Alight Motion](https://vocal.media/photography/alight-motion-app-complete-guide-features-editing-tools-and-animation-workflow) — proof that keyframe-everything animation with easing curves and parent/child layers is viable on a phone.
- [FlipaClip](https://play.google.com/store/apps/details?id=com.vblast.flipaclip&hl=en) — the mobile reference for frame-by-frame UX (onion skin, filmstrip timeline); largely what the *Editor* already is, and therefore what the Animator must *not* duplicate.
- [Aseprite animation docs](https://www.aseprite.org/docs/animation/) — the pixel-art timeline vocabulary (cels, linked cels, tags, per-frame duration) our audience already thinks in.
- [Spine](http://esotericsoftware.com/) — the desktop gold standard for "first-class animating" (dopesheet, graph editor, ghosting); useful as a ceiling, not a template.
- [PixelOver](https://pixelover.io/) — the closest existing product to this exact concept: keyframes + pixel-accurate transforms producing pixel-perfect GIFs. Desktop-only, which means **a smartphone-first pixel-native animator is open territory**.
