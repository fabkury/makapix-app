# Every uncommitted Draft dies at any context change — silently and irrecoverably

**Decided 2026-08-25 during the UI specification-gap grilling** (survey: `docs/ui-gaps/REPORT.md`,
root cause 2, gaps G-13…G-19; vocabulary — Draft — in `CONTEXT.md`).

Before this decision Drafts cancelled on tool switch **only**. Frame switches, layer switches and
even document switches (Open, New) left them armed, and the two Draft families then landed
differently: fid-pinned transform Drafts committed invisibly onto the frame the artist had left
(G-13, G-15), while figure and adjust Drafts retargeted to whatever was active at Commit time
(G-16). A Draft could commit into an entirely different document (G-17). The rule is now uniform:
**any context change — tool, frame, layer, or document — cancels every open Draft.**

Three commitments follow:

- **All four uncommitted families are Drafts**: figure Drafts (shape, gradient), transform Drafts
  (Move, Rotate, Scale), adjust previews (HSV, brightness/contrast, Levels sliders merely at
  non-zero), and paste Drafts. One concept, one lifecycle. This extends the contract the codebase
  had already written for tool switches rather than inventing a second one.
- **The inertness guard stays as broad as the lifecycle.** `_hasAnyDraft` gates the right-click
  eyedropper pick, and it keeps gating on all four families — so the pick is refused while a Levels
  slider is merely touched (G-18). Narrowing the guard to "Drafts a tool round-trip can actually
  disturb" was considered and rejected: a predicate that means one thing for lifecycle and another
  for inertness is two predicates wearing one name, and that divergence is the exact species of
  drift this survey catalogued. G-18 is therefore **closed as accepted behavior**, not fixed.
- **Cancellation is irrecoverable and silent.** Drafts do not live in undo history, and no restore
  affordance, confirm dialog, or notice is offered. A Rotate Draft holding a minute of careful
  positioning vanishes on a stray film-roll tap with no indication. This is the sharpest edge in
  the policy set and it was chosen with that named: the Editor gets exactly one non-silent
  interaction event (below), and re-dragging a transform is seconds of work.

**The one thing the Editor says out loud** is a refused eyedropper pick: the Draft's commit pill
flashes and a brief non-modal line names the blocker. It earns the exception because the pick fails
with no visible consequence at all, whereas every other automatic act in ADRs 0010–0014 leaves
visible evidence — a finished stroke is on the canvas, a paused playback is paused, a cancelled
Draft's preview is gone from the canvas the artist is looking at.

Alternatives rejected:

- **Commit to origin on context change**: preserves the work and makes it undoable, but it is a
  silent commit onto a surface the artist is no longer viewing — the precise complaint in G-15.
- **Block navigation while a Draft is open** (resolve the commit pill first): matches Photoshop's
  free-transform modality, but a film-roll tap that does nothing reads as a bug, and it puts a
  modal gate in the middle of routine frame-stepping.
- **Pin the Draft and keep it alive across navigation**: coherent on paper, incoherent on screen —
  the preview is not visible on the frame being viewed.
- **A short-lived restore affordance on a feedback line**: honors the loss without a modal, but
  every Draft family would then need to serialize and reconstruct itself, adding a second lifecycle
  to the concept this ADR exists to unify.

Consequences: `_cancelActiveDraft`-style teardown must be reachable from the frame, layer and
document funnels, not just the tool switch; a pillar switch tears the Editor down and therefore
cancels Drafts too, by the same rule. G-19 (palette extraction reading the un-baked document) is
*not* closed by this policy — pushing the palette page is not a context change — and is tracked as
a point fix.

**Amended by ADR 0016 (2026-08-30):** inserting a *blank* layer (`AddLayer`/`AddLayerAt`) is
preparation for a commit, not a context change — figure, paste, and Select-marquee Drafts survive
it and commit onto the new layer; transform and adjust Drafts, which are bound to the old layer's
content, still cancel. `DuplicateLayer` and every other structural verb remain context changes.
