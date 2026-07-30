# Scene files (.mkps) embed their Prop art

A Makapix Animator Scene file carries the art of every Prop in its Cast; it never references
gallery drawings by ID. Consequence a future reader will trip over: editing a drawing in the
Editor does **not** update Scenes that used it — the round-trip edit ("Edit in Editor" on an
Actor) modifies the Scene's embedded copy, and propagating a gallery fix is a manual
"re-import from gallery" action per Scene.

We chose this because references break: deleting a gallery drawing would corrupt every Scene
using it (or force "in use, can't delete" bookkeeping), and because a self-contained Scene is
a complete, shareable, remixable unit — which the Club's project-level remix ambition needs.
A reference+snapshot hybrid was rejected as two sources of truth per Prop. Duplication cost
is negligible at pixel-art sizes.

Decided 2026-07-30 during the Animator design grilling.
