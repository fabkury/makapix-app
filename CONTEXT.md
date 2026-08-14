# Makapix Club App

The native (Rust + Flutter) client for the makapix.club pixel-art social network. One app,
multiple pillars sharing one binary and one aesthetic.

## Language

### Product structure

**Pillar**:
A top-level, co-equal creative or social surface of the app, mounted one at a time by the app
shell. Current pillars: Club, Editor, Animator.
_Avoid_: tab, section, mode

**Makapix Club**:
The product as a whole — the website and this app together — and, within the app, the social
pillar (feeds, reactions, comments, profiles, publish).
_Avoid_: "the social network" (when the pillar is meant)

**Makapix Editor**:
The drawing pillar — a first-class animated pixel-art editor whose timeline is a stack of
drawn frames. It is a feature inside this app, not a separate product.
_Avoid_: "the app" (the Editor is one pillar of it)

**Makapix Animator**:
The animating pillar — a first-class sprite/timeline compositing tool where finished art is
given motion via keyframes. Its timeline holds instructions, not drawings. A co-equal third
pillar (decided 2026-07-30), not an Editor sub-mode and not a content-launched flow.
_Avoid_: "animation mode", "the animation editor", Stage, Studio, Motion (as pillar names)

### Editor vocabulary

**Open**:
Bringing a whole file into the Editor as a new drawing, faithfully: layers, blend modes,
opacity, palette, and timing survive the trip. A file either Opens true to the source or is
refused; only representational details the Editor lacks may degrade, and the artist is told
when the look changes. Applies to .mkpx and Aseprite files.
_Avoid_: import (that is a different gesture), load (reserve for engine internals)

**Import**:
Bringing outside pixels into the current drawing — flattened, scaled or cropped to the
canvas, placed as new frames or as a new layer. Import converts; Open preserves.
_Avoid_: open (when pixels join an existing drawing)

**Airbrush mode**:
One of the Airbrush's three ways of laying paint — Dots, Soft, or Mist — toggled in the tool's
options row. One tool to the artist; the mode decides what a pass leaves behind.
_Avoid_: brush type, variant

**Dots**:
The Airbrush's original mode: a scatter of hard, fully opaque pixels. The pixel-art-oriented
spray.
_Avoid_: Pixel (as a mode name)

**Soft**:
The Airbrush mode that lays a smooth translucent stamp, strongest at the center and fading to
nothing at the rim. Passes build up toward opaque.
_Avoid_: soft brush (it is a mode, not a tool)

**Mist**:
The Airbrush mode that scatters faint translucent specks, denser near the center. Passes
accumulate into grainy clouds.
_Avoid_: Spray (that word belongs to the precision-row dab button)

### Animator vocabulary

**Scene**:
The Animator's document: a composition with a canvas size, duration, background, and a cast
of Props performed by Actors. In v1 a Scene is a single shot.
_Avoid_: project, movie, clip

**Stage**:
The Scene's canvas surface — where Actors are placed and manipulated. The primary editing
surface of the Animator.
_Avoid_: canvas (that word belongs to the Editor), viewport

**Prop**:
A piece of art imported into a Scene's cast to be animated: a still image, an animation, or a
layered Makapix drawing. Reusable; placing it does not copy it.
_Avoid_: asset, sprite, resource

**Cast**:
The Scene's collection of Props — what the prop-library panel shows.
_Avoid_: library, assets, media

**Actor**:
One placement of a Prop in a Scene — the thing you tap, transform, and keyframe on the Stage.
Six copies of one star = one Prop, six Actors.
_Avoid_: instance, layer, object

**Track**:
An Actor's lane in the timeline: its duration bar, Keys, and tweens. One Track per Actor.
_Avoid_: layer, channel, row

**Key**:
A recorded value of an Actor's property (position, rotation, scale, opacity, …) at a moment
in Scene time.
_Avoid_: keyframe (in UI copy; acceptable in explanatory prose)

**Tween**:
The computed motion between two Keys, shaped by an easing style. A hold tween jumps with no
interpolation.
_Avoid_: transition, interpolation (as UI terms)

**Playhead**:
The current moment in Scene time; scrubbing it is the core review gesture.

**Cycle**:
A multi-frame Prop's own looping animation, mapped to whole Scene frames when the Prop joins
the Cast. An Actor in Playing mode loops its Prop's Cycle.
_Avoid_: animation (ambiguous), loop (reserve for Scene loop regions)

**Pose**:
One frame of a multi-frame Prop used as a held stance. An Actor in Posing mode shows the Pose
chosen by hold Keys instead of playing its Cycle. Playing vs. Posing is a per-Actor mode.
_Avoid_: state, variant

### Replay vocabulary (Editor)

**Journal**:
The per-drawing, append-only stream of timestamped editor actions persisted beside the
drawing's autosave. The raw material a Replay executes.
_Avoid_: recording, log, tape, history (that word belongs to undo)

**Chapter**:
A segment of a Journal that replays from a fixed starting document: an empty canvas or a
captured base (an import, a Club remix, a re-anchor). A Journal is a sequence of Chapters;
their boundaries are invisible in a Replay.
_Avoid_: session (that is the engine's stateful entry point), segment, part

**Replay**:
Deterministic re-execution of a Journal by the engine — the in-app, scrubbable "making-of"
view of a drawing's creation.
_Avoid_: playback (that is the Editor's frame-animation preview)

**Timelapse**:
The exported, shareable video rendition of a Replay — upscaled, resampled, and encoded for
posting outside the app.
_Avoid_: replay video, movie, GIF (a format it may use, not the artifact)
