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

## Gesture safety (app-wide rules)

Rules, not vocabulary — canonical here because they are platform physics that bind every
pillar (decided 2026-07-31; the inventory behind them and the Animator's application live in
[docs/animator/06-gesture-safety.md](docs/animator/06-gesture-safety.md)):

- **R1 — Side edges**: no interaction may require *starting* a drag inside the side gesture
  insets (Android Back). Taps are fine; drags may *end* there.
- **R2 — Bottom**: no interaction may require starting a drag in the bottom gesture zone
  (Home / app switch — a zone no API can reclaim); tap targets sit above the home indicator.
- **R3 — Top**: no drag starts at the very top edge (notification shade, Control Center).
- **R4 — Corners**: nothing requires precision at a screen corner.
- **R5 — Pannable surfaces need an edge story**: content that can park at an edge gets
  indirect manipulation, scroll padding, or a hold-then-drag rescue — never luck.

Known follow-up: the Editor's bottom rows contain sideways slider drags (R2 exposure);
noted, not yet redesigned.
