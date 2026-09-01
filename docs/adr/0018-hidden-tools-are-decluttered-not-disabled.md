# Hidden row-3 tools are decluttered, not disabled

**Decided 2026-09-01.** Shell only: `app/lib/editor/tools.dart` (`visibleToolOrder`,
`restoreHiddenTools`, `reconcileHiddenTools`, `canHideAnotherTool`), `_setToolHidden` /
`_showAllTools` in `editor_page.engine.dart`, the sheet in `editor_page.toolgrid.dart`, the
☰ → View → "Show/hide tools…" entry in `editor_page.timeline.dart`. No engine, FFI, journal, or
`.mkpx` change.

Users reported that row 3 — the horizontally scrolling tool grid — needs constant scrolling.
Reordering already existed; this adds hiding. The sheet lists every catalog tool (catalog order,
icon + name), visible tools carry a check, tapping a row toggles it, the grid reflows live behind
the sheet, and the choice persists editor-wide (`tool_hidden_v1`, a sibling of `tool_order_v1`).

**A hidden tool is removed from the grid and from nothing else.** Keyboard shortcuts, the hold-pick
Eyedropper, Primary+V (which switches to the Copy tool), the 3-row pinned slot, and the keyboard
cheat sheet all keep working for it; selecting a hidden tool by any of those routes simply shows
no highlighted tile (row 1 and the tips band still name it). "Hidden" is a toolbar preference,
not a capability switch — the alternative (no-op shortcuts for hidden tools) would silently break
desktop muscle memory the moment a user tidies the grid.

**Hidden tools keep their slot in the order.** Like the pinned tool before them, hidden tools stay
in `_toolOrder` and are filtered out at display time only, so unhiding puts a tool back exactly
where it was and a drag-reorder of the visible grid never disturbs a hidden slot. The two
exclusions (hidden set + pinned tool in 3-row mode) are one set for the visible↔full mapping:
`restoreHiddenTools` reinserts each excluded tool at its former index, ascending, which makes
remove-then-restore an exact round-trip (property-tested).

**The pinned slot and the hidden set are independent surfaces.** In 3-row mode the pinned tool
always shows in slot 3 whether hidden or not, and the pin picker keeps listing every tool. A tool
that is both pinned and hidden is visible in 3-row mode and absent in 2-row mode — by design, not
drift.

**Hiding the active tool is allowed, and it stays active.** The sheet is a settings surface; it
never calls the tool-switch path, so no draft is cancelled and nothing is re-pointed in the
engine. The row is marked "active".

**One decided side effect: hiding Onion while onion skinning is on turns it off.** Onion is the
grid's only action toggle; an invisible toggle that keeps shading the canvas was judged worse than
a settings tap changing the view. Unhiding does not turn it back on. (The N key can still toggle
onion skinning while the tile is hidden — see the first rule.)

**Floor and escape hatch.** At least one catalog tool stays visible: the last visible row is not
tappable, and a persisted set that would hide everything (only reachable through catalog drift
or a damaged preference) is discarded on load. A "Show all" row restores every tool; the order is
untouched. Tools added to the catalog in a later version are visible by construction (the set
stores hidden names, never visible ones); names removed from the catalog are dropped on load.

**Entry point.** ☰ → View → "Show/hide tools…" only, with the hidden count appended while
anything is hidden ("… (3 hidden)"). No extra row-3 tile: the feature exists to remove tiles.
Undo/Redo are the fixed slots and cannot be hidden.

Deferred, not rejected: reordering inside the same sheet (drag handles, the palette-page idiom).
The list already mirrors the catalog rather than the order precisely so that a later reorder
surface is a separate decision.
