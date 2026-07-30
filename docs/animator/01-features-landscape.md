# Q1 — The features and workflows of animation software

*What sprite/timeline animation tools are made of: the domain model, the feature checklist, and
the workflows users expect. Decisions from the 2026-07-30 grilling are marked **[decided]**;
prioritization happens in [02-prioritization.md](02-prioritization.md).*

## 1. The domain model of a compositing animator

Every sprite/timeline animation tool — from After Effects down to Alight Motion — is built on
the same handful of nouns. Getting these right matters more than any individual feature,
because they are the words users think in. The Makapix vocabulary is **[decided]** and
canonical in [CONTEXT.md](../../CONTEXT.md):

| Generic noun | What it is | Makapix name |
|---|---|---|
| Project / scene | The document: canvas size, duration, frame rate, background. | **Scene** |
| Viewport / canvas | The composition surface where things are placed and manipulated. | **Stage** |
| Asset library | The document's collection of imported art. | **Cast** |
| Asset | A piece of art brought in to be animated: a still, an animation, or a layered drawing. Imported once, placed many times. | **Prop** |
| Placed instance | One placement of an asset — the thing you tap, transform, and keyframe. Six copies of one star = one Prop, six of these. | **Actor** |
| Layer / track | An Actor's lane in the timeline: duration bar, keys, tweens. One per Actor. | **Track** |
| Keyframe | A recorded value of an Actor's property (position, rotation, …) at a moment in time. | **Key** |
| Tween / interpolation | The computed in-between motion connecting two Keys, shaped by an easing style. | **Tween** |
| Playhead | The current moment; scrubbing it is the single most-used gesture in any animation tool. | **Playhead** |

The spatial/temporal split is deliberate: the **Actor** is what you touch on the Stage; the
**Track** is where its time lives. "Layer" is banned on both sides — it belongs to the Editor
(and to `.mkpx` files, whose layers arrive here as separate Props).

A crucial distinction against the Editor: in the Editor, the timeline holds *drawings* (each
frame is an image you made). In the Animator, the timeline holds *instructions* (each Track is
"this Actor, moving like this"). Frames are a *rendering* of the timeline, not its content.
This inversion is the entire point of the pillar, and the UI must teach it implicitly.

## 2. The feature landscape, by cluster

### 2.1 Stage & composition

- **Scene setup** — size, background color/transparency, duration, frame rate. **[decided]**
  Scene canvas matches the Editor's world: 1×1–256×256.
- **Placing Actors** — position, z-order, initial pose. Multiple Actors of the same Prop
  ("six copies of the same star"). **[decided]** Props may be larger than the Scene (pans,
  scrolling panorama backgrounds), capped at 1024 px per side.
- **Transform set** — the properties that can be animated. **[decided]** for v1:
  - position (x, y)
  - rotation
  - scale (uniform; per-axis deferred — see Tier 2)
  - flip (horizontal/vertical)
  - opacity (with the GIF-export caveat in §2.6)
  - anchor/pivot point (what the Actor rotates and scales *around* — underrated; a wing
    pivoting at its root vs. its center is the difference between flapping and spinning)
- **Grouping / parenting** — a child moves with its parent (cart carries the passenger; head
  carries the eyes). Alight Motion ships parent/child linking on phones; it is the gateway to
  cutout-style character motion *without* a bones system. **[decided]** one level ("pin to"),
  no chains, no IK.
- **Stage guides** — pixel grid, snapping, alignment, safe center.

### 2.2 Time & keyframes

- **Keyframing** — set a value at a time; the tool interpolates between keys. The core loop.
- **Auto-key ("record mode")** — when armed, *any* manipulation at the current playhead time
  drops a key automatically. On touch this is not a convenience but a necessity (see
  [03-smartphone-approaches.md](03-smartphone-approaches.md)).
- **Hold/step keys** — no interpolation; value jumps at the key. Essential for pixel art:
  a blink, a sprite swap, a scene cut are all holds. In pixel-art culture, stepped motion is a
  *style*, not a fallback.
- **Easing** — the shape of the tween: linear, ease-in/out, overshoot, bounce. Desktop tools
  expose Bézier graph editors ([Spine](http://esotericsoftware.com/),
  [Alight Motion](https://alightmotionapp.net/keyframing-tools/) both do); the *effect* is
  essential, the *graph UI* is not (see Q2).
- **Timing model** — two traditions collide here:
  - *Frame-based* (pixel art, Aseprite): a sequence of frames, each with its own duration in
    milliseconds. What Editor graduates already know.
  - *Time-based* (video tools): a continuous clock at a fixed fps; keys sit at arbitrary times.
  - **[decided — [ADR-0001](../adr/0001-frame-grid-timing.md)]** the Animator is
    frame-based: a Scene has a fixed frame rate from a curated GIF-safe list (e.g.
    10 / 12.5 / 20 / 25 / 50 fps) and **every Key sits on a frame boundary**. A continuous
    clock was considered and rejected: a Key between frames is never rendered (nudging it
    changes nothing visible, breaking preview truth), and frame snapping doubles as the
    precision aid touch input needs. Time snaps to frames exactly as motion snaps to pixels.
- **Loops & cycles** — loop a key segment (walk cycle), ping-pong, and "loop this prop's cycle
  independently of the scene" (see §2.4). Pixel-art animations are overwhelmingly loops; the
  Club feed plays loops. First-class looping is a defining feature, not a checkbox.
- **Motion paths** — see and edit the trajectory of a moving prop directly on the stage as a
  curve with handles. Spatial editing of temporal data; extremely touch-friendly.
- **Time display** — frames, milliseconds, or beats; total duration always visible.

### 2.3 Timeline views

Desktop animation software offers up to three synchronized views of the same data:

1. **Track timeline** — rows of tracks with key markers and duration bars. The workhorse.
2. **Dopesheet** — a condensed all-keys-per-row grid for retiming many keys at once
   ([Spine's](http://esotericsoftware.com/spine-in-depth) primary timing tool).
3. **Graph editor** — property value vs. time as editable curves, for polish.

On a phone, these cannot coexist; Q2/Q3 argue for one adaptive view with zoom levels rather
than three modes.

### 2.4 Assets & reuse

- **Import** — PNG (still), GIF/WEBP (animated), and — the differentiator — **`.mkpx` with its
  layers intact**. A Makapix drawing whose character has body/arm/head on separate layers can
  arrive as separate Props, one per layer. No other mobile animator has anything like this
  (detailed in [04-recommendations.md](04-recommendations.md) §1). **[decided]** importing a
  multi-layer `.mkpx` shows a two-choice card — *Whole drawing* / *Separate parts* — with a
  visual preview of the split; single-layer files import silently. The card is discovery, not
  friction: it advertises "layers become limbs" at exactly the right moment.
- **Animated Props (Cycles)** — a Prop that is *itself* an animation (an imported GIF, or a
  multi-frame `.mkpx`) keeps playing its own Cycle while its Actor moves around the Scene: a
  flapping bird flies across the sky along a keyframed path. Two layers of time — the Prop's
  Cycle and the Scene's clock. **[decided — [ADR-0001](../adr/0001-frame-grid-timing.md)]**
  Cycles are quantized to the Scene's frame grid when the Prop joins the Cast (each prop frame
  becomes a whole number of scene frames; the import surfaces the mapping; cycle speed is
  adjusted thereafter in integer scene-frames per prop frame). Live millisecond sampling was
  rejected: non-integer clock ratios produce judder, and pixel-art loops live by rhythm.
- **The Cast** — per-Scene Prop collection, plus a personal library across Scenes; recently
  used; multiple Actors share their Prop's art.
- **Sprite-swap sequences (Poses)** — cycling through named stances (open/closed mouth, three
  walk poses) via hold Keys. This is the compositing answer to frame-by-frame character work,
  and pairs perfectly with the Editor ("draw three poses, swap between them"). **[decided]**
  *Playing vs. Posing is a per-Actor mode*: the same multi-frame Prop can loop its Cycle in
  one Actor (a bird flying) and be pose-driven in another (a bird perched), switchable at any
  time — no import-time fork, no Prop-level lock-in. A Posing Actor's shown frame is simply a
  hold-only keyable property.

### 2.5 Playback & review

- **Scrubbing** — instant, smooth, always available. The animator's equivalent of the artist's
  glance; it must never lag or hide.
- **Loop playback** — play the whole scene or only a marked work region, looping.
- **Onion skin / ghosting** — see adjacent moments as ghosts. In a *tweened* tool this is less
  load-bearing than in flipbook tools (the tween already shows you the in-between when you
  scrub), but ghosting of key poses remains valuable for spacing.
- **Playback speed** — half/quarter speed for studying fast motion.
- **True-speed guarantee** — preview must play at export timing, or users will tune motion
  against a lie. (A known pain in mobile tools; a place to be rigorously correct.)

### 2.6 Output

- **Export** — GIF and WEBP; loop count; integer upscaling (a 64×64 scene exported at 4× =
  256×256 with fat pixels — the Editor's existing publish pipeline already thinks this way).
- **Format-driven timing quantization** — a product-visible fact, not a technicality: GIF frame
  delays are in **hundredths of a second**, animated WEBP in milliseconds. **[decided]** the
  frame-grid timing model's curated fps list (10/12.5/20/25/50) is drawn from rates GIF can
  represent exactly, so preview timing and export timing are identical *by construction* —
  no drift, no surprise.
- **Opacity at export** — **[decided]** opacity Keys are in the v1 property set; animated WEBP
  exports true alpha, while GIF (1-bit transparency) thresholds semi-transparent pixels **and
  tells the user it did** at export time. The one disclosed exception to preview truth,
  disclosed at the moment it matters.
- **Scene file** — **[decided — [ADR-0002](../adr/0002-self-contained-scenes.md)]** the
  Animator's own format, `.mkps`: re-editable (Cast + Actors + Keys + timing; baked exports
  are flattened) and **fully self-contained** — it embeds every Prop's art, so gallery
  deletions can never break a Scene and sharing/remixing a Scene is one file.

### 2.7 The pixel-native layer (what makes this *Makapix*)

The frame decision — subpixel math, pixel-grid rendering — creates features general tools don't have:

- **Pixel-aware rotation/scale** — naive rotation destroys pixel art. The Editor already ships
  cleanEdge-based rotation; **[decided]** the Animator offers the same choice as a **per-Prop**
  style toggle (crisp cleanEdge vs. chunky nearest-neighbor — the art's identity, not the
  placement's). [PixelOver](https://pixelover.io/) validates that "pixel-accurate transforms"
  is the load-bearing feature of this niche.
- **Staircase motion honesty** — a slow diagonal drift on a 64px canvas *is* a staircase of
  1px steps. The tool should embrace this (show quantized positions while scrubbing) rather
  than preview smooth motion the export can't deliver. Preview truth is a feature.
- **Palette discipline** — pixel artists manage palettes deliberately (the Editor has a whole
  palette system). Compositing several props raises palette questions at export (GIF's 256-color
  limit) that the tool should handle gracefully and visibly.
- **Motion resolution** — on small canvases motion is inherently chunky; an explicit "supersize"
  export (author at 64, export at 256) trades chunk for smoothness under the artist's control.

### 2.8 Everything else tools eventually grow

For completeness — effects/filters (glow, shake, color cycling), text titling, camera (an
animatable pan/zoom viewport, cheap parallax), masks/clipping, mesh deformation, IK/bones,
audio, blending modes, scripting/expressions. All real; almost all deferred or rejected in Q2.

## 3. The workflows users expect

Feature lists don't make a tool feel first-class; workflow fit does. The canonical animation
workflow is three passes, and the UI should be honest about which pass the user is in:

1. **Blocking (posing)** — place props, set the key poses at rough times. Spatial thinking;
   lives on the *stage*. Motion is stepped, timing is wrong, and that's fine.
2. **Timing (spacing)** — shift and stretch keys until the rhythm reads. Temporal thinking;
   lives on the *timeline/dopesheet*. Scrub–adjust–scrub, dozens of times a minute.
3. **Polish (easing)** — soften the mechanics: ease curves, overshoot, follow-through,
   anticipation, secondary motion on child parts.

Other expectations that shape the UX:

- **Iteration at second scale** — the change→preview loop must cost roughly nothing. Animators
  make hundreds of micro-adjustments; every extra tap in the loop multiplies by a hundred.
- **Start from something** — the blank-stage cold start is deadlier than blank-canvas in a
  drawing app (you can't doodle time). Templates, motion presets, and remixable examples are
  workflow features, not marketing (see [04-recommendations.md](04-recommendations.md)).
- **Safe experimentation** — deep undo, autosave, and cheap "try a variant" (the Editor's
  gallery/autosave culture carries straight over).
- **Small screens forgive nothing** — every one of the above workflows must survive a 6-inch
  portrait screen and a thumb. That constraint is the subject of
  [03-smartphone-approaches.md](03-smartphone-approaches.md).

## References

[Alight Motion feature guide](https://vocal.media/photography/alight-motion-app-complete-guide-features-editing-tools-and-animation-workflow) ·
[Alight Motion keyframing](https://alightmotionapp.net/keyframing-tools/) ·
[FlipaClip](https://play.google.com/store/apps/details?id=com.vblast.flipaclip&hl=en) ·
[Aseprite animation](https://www.aseprite.org/docs/animation/) ·
[Aseprite timeline](https://www.aseprite.org/docs/timeline/) ·
[Aseprite linked cels](https://www.aseprite.org/docs/linked-cels/) ·
[Spine](http://esotericsoftware.com/) · [Spine in depth](http://esotericsoftware.com/spine-in-depth) ·
[PixelOver](https://pixelover.io/) · [PixelOver manual](https://docs.pixelover.io/manual/introduction/)
