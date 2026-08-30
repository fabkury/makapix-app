# Inserting a blank layer is preparation for a commit, not a context change

**Decided 2026-08-30** as an amendment to ADR 0011 (Draft lifecycle; vocabulary — Draft, Active
target — in `CONTEXT.md`). Shell gate: `_isBlankLayerVerb` / `_cancelLayerBoundDraftsForBlankLayer`
in `app/lib/editor/editor_page.engine.dart`.

ADR 0011 makes any change of the active frame or layer a context change, and 237ba232 (2026-08-28)
applied that literally to every structural verb: `AddLayer`/`AddLayerAt` activate the new layer, so
they cancelled every open Draft. That killed the most ordinary two-step there is — *draw a Line
draft, realize it belongs on its own layer, tap +, commit* — and its clipboard twin, *paste → new
layer → commit*, which every raster editor treats as the canonical paste.

The decision: **`AddLayer` and `AddLayerAt` are not context changes.** A blank layer inserted into
the frame the artist is looking at does not move them anywhere: the composited preview is
pixel-identical before and after, and the new empty active layer is exactly the surface "on its own
layer" wants the Draft to land on. ADR 0011's objection — a preview that is no longer visible on the
surface being viewed — does not apply.

The carve-out is **typed by Draft family**, not a hole:

- **Survive** — the families that retarget to whatever is active at commit: figure Drafts (shape,
  gradient), paste Drafts, and the Select-tool marquee (a selection is frame-scoped; it never
  belonged to a layer). Their commit lands on the new blank layer, which is the point.
- **Still cancel** — the families bound to the *old* layer's content: transform Drafts
  (Move/Rotate/Scale) hold lifted pixels pinned by frame and layer id, so surviving would let the
  commit pill land on a layer that is no longer active — precisely the hidden off-surface commit
  of G-13/G-15 that ADR 0011 forbids. Adjust Drafts (HSV, brightness/contrast, Levels) preview the
  active layer, which is now blank — a stuck slider adjusting nothing, with no way back (the
  return `SetActiveLayer` is itself a context change).

ADR 0011's "one predicate wearing one name" worry is honored by keeping two named predicates:
`_isContextChangeVerb` (unchanged contract, minus the two verbs) and `_isBlankLayerVerb`, whose
cancel path names the bound families explicitly. Cancellation remains silent and irrecoverable.

Scope is deliberately the blank-layer verbs only. **`DuplicateLayer` stays a context change**: it
activates a layer that already has content under the Draft, so "preparation for the commit" does not
describe it. `RemoveLayer`, `MergeDown`, and every frame verb are untouched.

Alternatives rejected:

- **Exempt every family** (AddLayer simply leaves the set): coherent as a rule, incoherent on screen
  for transform and adjust Drafts, as above.
- **A commit-then-add affordance** ("Commit and new layer" on the pill): preserves ADR 0011's
  purity but makes the artist commit onto the wrong layer first, which is the complaint.
- **Exempt `DuplicateLayer` too**: testers may expect it, but the rationale stops describing the
  verb; revisit only with a concrete workflow that needs it.

Consequences: the Journal records nothing new — Drafts are shell state, and the eventual commit verb
is what it always was, now preceded by an `AddLayer[At]` line. Replays are unaffected (ADR 0015 is
not engaged). `CONTEXT.md`'s Draft entry gains the exception in one clause.
