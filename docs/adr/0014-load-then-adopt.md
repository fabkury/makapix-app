# A drawing's identity is adopted only after its load succeeds, and one writer owns a drawing folder

**Decided 2026-08-25 during the UI specification-gap grilling** (survey: `docs/ui-gaps/REPORT.md`,
root cause 5, gaps G-37…G-42).

Identity was adopted *before* the incoming load was known to have succeeded, and teardown was never
serialized against startup. Three flows had each invented a different failure outcome: opening a
corrupt library drawing adopted its identity anyway and then autosaved foreign content into it
(G-37); a discard-then-failure resurrected the discarded drawing, differently on each path (G-38);
and a fast pillar round-trip raced the outgoing editor's teardown writes against the incoming
editor's restore (G-41). Separately, startup restore clobbered strokes drawn during the async load,
leaving pixels in the document that appear in no Journal (G-39).

Three commitments:

- **Load, then adopt.** The incoming document loads into the engine first; identity, Journal and
  autosave switch only on success. On failure the outgoing drawing keeps its identity untouched and
  its Journal re-attaches in resume mode. One funnel, one rule, no per-path failure semantics.
- **One writer per drawing folder.** A write lock (or a completion future handed to the next mount)
  guarantees exactly one editor instance touches a drawing's folder at a time, so a teardown flush
  can never interleave with the next mount's `readDoc`/`attachResume`.
- **Canvas input is gated until restore resolves.** The boot canvas does not accept strokes it
  cannot journal.

Alternatives rejected:

- **Adopt-then-load with rollback**: a smaller diff, but rollback paths are exactly what rotted
  here — three flows already invented three different failure outcomes, and a fourth would join
  them.
- **Per-path specified outcomes** (leave the flows as they are and simply document what each does
  on failure): cheapest, and it institutionalizes the divergence.
- **Forking a dirtied boot canvas into its own drawing** rather than gating input: avoids losing the
  strokes, but it manufactures library entries the artist never asked for.

Consequences: G-40 (Post-to-Club assembling the publish draft from two different document states)
and G-42 (dispose tearing down the Journal before the write-ahead marker lands, so every session
end re-anchors) sit in this cluster but are *not* closed by the policy; both are tracked as point
fixes.
