# Keyboard Commands route through the shell control layer, with ids as a persistent contract

**Decided 2026-08-16 during the keyboard-shortcuts grilling; not yet implemented** (design:
`docs/keyboard-shortcuts/DESIGN.md`; survey: `docs/keyboard-shortcuts/ANALYSIS.md`; vocabulary —
Command, Chord, Binding, Hold binding — in `CONTEXT.md`).

Physical-keyboard support enters the Editor as a **command registry in the Flutter shell**: a
pure-data catalog of Commands, each a thin index entry over an *existing* `_EditorPageState`
method — the same pathway its on-screen control takes. The keyboard is another way to press the
button, never a side door. Two commitments follow:

- **No Command may send raw DSL.** The shell methods carry the bookkeeping that makes an action
  safe — pausing playback, canceling the seven kinds of pending draft, clearing overlays,
  re-pushing tool settings — and they pass through the `_send` tap that records the Journal.
  Routing through them makes every keyboard invocation byte-identical in the Journal to its
  button-press twin: Replays and Timelapses are automatically faithful, and the engine, the FFI
  surface, and the `.mkpx`/journal formats are untouched by the entire feature. A binding that
  bypassed the shell would silently desync shell state from engine state and was rejected for
  that reason, not for style.
- **Command ids are a persistent contract.** The 6.B bindings file stores user customizations
  keyed by command id, so ids inherit the DSL's "retired verbs parse forever" discipline at
  shell scope: renaming, splitting (cf. Airbrush → three modes), or retiring a Command requires
  a migration entry, never a silent drop of a user's binding.

Alternatives rejected:

- **Bindings straight to DSL strings** (chord → `mkpx_run` text): seductively simple and
  journal-visible, but it skips the shell bookkeeping (a chord-triggered tool switch would leak
  pending drafts and overlays) and can express nothing the DSL doesn't (pan, zoom, sheet
  toggles, save — all shell concerns).
- **A native `UIKeyCommand` layer on iOS** (to gain the iPadOS hold-⌘ HUD): forks key handling
  per platform at the platform-channel level for one discoverability surface; instead the app
  ships its own registry-driven cheat sheet on both platforms.
- **Flutter's `Shortcuts`/`Actions` widgets as the dispatcher:** cannot express Hold bindings
  (keyDown/keyUp state) or the ordered modality gating the Editor needs; the design uses a
  single root `Focus.onKeyEvent` dispatcher over the registry instead. The registry concept —
  the actual decision — is dispatcher-agnostic.

Consequences: the registry stays a thin index (it must never become a refactor driver for the
nine `editor_page` part files); every future Editor feature decides at birth whether it gets a
Command, a default Chord, and a cheat-sheet row; Shift-constrain is deliberately *outside* the
registry (fixed gesture grammar transforming pointer coordinates before they become DSL cursor
traffic — no Command, not rebindable) so constrained drags journal as plain coordinates.
