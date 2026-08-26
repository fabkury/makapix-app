# Makapix Editor UI — specification-gap survey

**Date:** 2026-08-24 · **State analyzed:** working tree at `c4568f6` plus the uncommitted desktop
mouse-affordances work (right-click menus/eyedropper, `StripScroller`). Code analysis only — nothing
here was reproduced in a running build yet.

## The experiment

Question: *are there gaps in the Makapix Editor UI — unintended consequences or odd behaviors caused
by the correct behavior never having been specified?* A "gap" here is not a bug in an implemented
rule; it is a place where two features, each sensible in isolation, collide in a state nobody
decided, and the resulting behavior is whatever the code happens to do.

Method: a 14-agent sweep over `app/lib/editor/` (~15k lines, with engine-side cross-checks into
`crates/engine`). Seven finder agents each owned one area — canvas/gestures, tools/controls,
timeline/playback, sheets/layers, palette/color, keyboard/dialogs, persistence/replay — and each
finder's output went to an adversarial verifier instructed to *refute* its findings against the
code, defaulting to refuted when the evidence didn't hold. Results: **55 raw findings → 51 confirmed
by code trace, 1 plausible (timing-dependent), 3 refuted.** After merging duplicates found
independently by two areas, **49 distinct gaps** remain, cataloged below as G-01…G-49.

## Answer

Yes — emphatically. The editor's individual features are well specified (the verifiers repeatedly
found deliberate, documented guards: the id-pinned undo commit, the wheel-zoom stroke guard, the
move-draft undo rule, the sheet stay-open carve-outs). The gaps are almost entirely **pairwise
interaction states**, and they cluster into five root causes. Fixing at the root-cause level would
close most of the catalog with a handful of policies rather than 49 point fixes:

1. **No global "gesture in flight" rule.** Exactly one code path consults
   `EditorAccess.pointerActive` (the hold-Alt eyedropper spring). Keyboard tap commands, row-3
   tiles, film-roll/layer taps, and second-finger touches all dispatch mid-stroke, splitting
   strokes across frames, changing a stroke's meaning under the finger, and creating pixels the
   undo system can never remove. *(G-01…G-12; the worst individual findings in the sweep.)*
2. **No draft lifecycle contract.** Drafts cancel on tool switch only. Frame navigation and
   document switches leave them armed — and the two draft families then land differently:
   fid-pinned transform drafts commit invisibly onto the *old* frame, while figure/adjust drafts
   retarget to whatever is active at Commit. *(G-13…G-19.)*
3. **Playback pause/inertness is a convention, not a policy.** Auto-pause is applied per call
   site, so equivalent routes to one action disagree; and canvas inertness is keyed to the Play
   *tool* rather than playback *running*, so keyboard-started playback leaves the whole editing
   surface live under the animation. *(G-20…G-29.)*
4. **Stay-open sheets vs. index-based, auto-activating engine verbs.** Sheets now operate on
   non-active items, but structural verbs still unconditionally activate their result and the
   move-group is raw indices into the active frame's stack. *(G-30…G-36.)*
5. **Document identity adopted before load success; teardown never serialized against startup.**
   The replace-the-canvas flows can adopt a corrupt drawing's identity, resurrect an explicitly
   discarded drawing, or clobber strokes drawn during an async restore. *(G-37…G-42.)*

## Decisions (2026-08-26)

A follow-up grilling session turned the five root causes into six adopted policies, each recorded as
an ADR. Every finding in the catalog below now carries a **Disposition** line.

| Policy | Rule in one line | ADR | Closes |
|---|---|---|---|
| Gesture atomicity | A gesture is atomic: competing input finishes it first; Esc/Undo/Redo cancel it instead. In-flight covers canvas drag, pinch, control drags, trackpad gestures, precision pen. | [0010](../adr/0010-gesture-atomicity.md) | 11 |
| Draft lifecycle | Any context change — tool, frame, layer, document — cancels every open Draft, silently and irrecoverably. | [0011](../adr/0011-draft-lifecycle.md) | 5 |
| Playback is a mode | Editing intent pauses first, at the `_act` funnel; inertness keys on playback running. The Playhead is a pure preview — pause returns to the Active target. | [0012](../adr/0012-playback-mode-and-playhead.md) | 9 |
| Explicit activation | The Active target moves only by explicit activation; the shell addresses frames and layers by id, and the move-group is a transient id set. | [0013](../adr/0013-explicit-activation-and-ids.md) | 6 |
| Load-then-adopt | Identity switches only after a load succeeds; one writer per drawing folder; canvas input gated until restore resolves. | [0014](../adr/0014-load-then-adopt.md) | 4 |
| Accepted replay fork | Engine semantics are fixed properly and pre-change Journals may replay differently; the header bumps to `#mkpxj 2` and nothing branches on it. | [0015](../adr/0015-replay-semantics-fork.md) | — |

**Coverage:** 35 closed by policy · **1 accepted as designed** (G-18) · **13 point fixes** — G-09,
G-19, G-23, G-30, G-40 and G-42 from inside the clusters, plus G-43…G-49 from the keyboard and
palette sections.

**Two sharp edges, chosen deliberately.** A cancelled Draft is irrecoverable *and* silent: the
refused eyedropper pick is the Editor's only non-silent interaction event, so a minute of Rotate
positioning can vanish on a stray film-roll tap with no indication (ADR 0011). And accepting the
replay fork means a Journal containing a frame delete or reorder may replay to a different result
than the session that produced it — including already-published Timelapses (ADR 0015).

**Status (2026-08-26): all 49 are implemented** on branch `ui-gaps-policies` — `66675fe`
(ADR 0013 engine), `c87433f0` (ADR 0015), `22a55766` (ADRs 0010/0011/0012/0014, the ADR 0013 shell
half, and the 13 point fixes). `cargo test --workspace` and `flutter test` are green and
`flutter analyze` is clean. Two notes against the plan: **no goldens moved** (ADR 0015 anticipated
re-pins that were never needed), and **G-43 changed shape** — rather than guarding the Alt spring,
the hold-pick moved off Alt entirely to bare **S**, because Alt is an OS chord modifier. Nothing
here has been exercised in a running build yet; the Q14 device pass is the remaining step.

**Delivery.** One branch, a commit per root cause plus one for the point fixes, and no dedicated
release — the work rides with the next feature. Done means one regression test per policy (Dart for
the shell rules, Rust scenarios for the engine ones) plus a hand-repro on G-01, G-02, G-13, G-14,
G-30 and G-21. The new vocabulary — Gesture, Draft, Active target, Move group, Playhead — is in
`CONTEXT.md`.

## Priority ladder

Ranked by user damage; severity shown is post-verification (the verifiers corrected two claims and
downgraded one severity).

| # | ID | Gap | Severity |
|---|----|-----|----------|
| 1 | G-01 | Frame/layer switch mid-stroke splits a Pencil stroke; the second half is permanently un-undoable | high |
| 2 | G-02 | Keyboard tap commands dispatch during an in-flight stroke (no `pointerActive` gate) — umbrella for G-03…G-06 | high |
| 3 | G-13 | Move/Rotate/Scale drafts survive frame switches as invisible armed state | high |
| 4 | G-14 | Undo/Redo under an open Rotate/Scale draft silently rewinds history; Commit resurrects undone pixels | high |
| 5 | G-30 | Layer-opacity slider records one undo step per drag tick, evicting the frame's undo history (128-record cap) | high |
| 6 | G-20 | Undo emptying the timeline mid-playback parks the clock for up to 1 hour with Pause disabled | medium |
| 7 | G-21 | Keyboard-started playback leaves the editing surface live — painting lands invisibly on the active frame | medium |
| 8 | G-37/38/39 | Identity/persistence failures: corrupt-open adopts identity, discard-then-fail resurrects, startup restore clobbers | medium |
| 9 | G-31/32 | Frame-sheet reorder/delete leave the layer move-group pointing into the wrong frame's stack | medium |
| 10 | G-24/25/26 | The auto-pause rule is applied inconsistently across equivalent routes (three areas found it independently) | medium |

## How to read the catalog

Findings are grouped by root-cause theme, not by severity. Every entry carries the finder's code
evidence (`file:line`) and the adversarial verifier's verdict; where the verifier corrected a claim,
the correction is printed — read it, it narrows several findings (e.g. G-01 is Pencil-only; the
coat tools are id-pinned end-to-end). The three refuted findings are kept in the appendix because
each documents a deliberate design that would otherwise get re-flagged.

Nothing had been fixed when this report was written; it was the experiment's deliverable. The **Disposition** lines added 2026-08-26 record what each finding resolves to (see Decisions above) — the code work itself is still ahead. Line numbers refer to the
working tree of 2026-08-24 and will drift.

## Mid-gesture collisions

The editor has exactly one guard that asks "is a pointer gesture in flight?" — the hold-Alt eyedropper spring in `keyboard/dispatcher.dart`. Every other input route (keyboard tap commands, row-3 tiles, film-roll and layer-strip taps, row-1 controls, second-finger touches) dispatches freely while a stroke, pinch, or slider drag is open, and the engine executes whatever arrives. Each finding below is one concrete way that unguarded dispatch corrupts the gesture, the undo history, or both.

### G-01 · Frame/layer switch mid-stroke splits the stroke and makes its second half permanently un-undoable

**Severity:** high · **Verdict:** confirmed · **Found by:** canvas-gestures

**Disposition (2026-08-26).** Closed by ADR 0010 (gesture atomicity). The tap finishes the stroke before SetActiveFrame/SetActiveLayer reaches the engine, so no pixels land outside the recorded patch.

**Collision.** An in-flight freehand canvas stroke vs. active-frame/active-layer changes (film-roll or layer-strip tap with a second finger, or the frame.prev/frame.next keyboard commands)

**Current behavior.** While one finger (or the mouse) is mid-stroke, tapping a film-roll frame tile fires _act('SetActiveFrame(i)') and a layer tile fires _act('SetActiveLayer(i)') with no gesture guard; the keyboard frame.prev/next commands are enabled purely on frameCount>1 (pointerActive is consulted only by the Alt-eyedropper hold). The engine's set_active_frame just reassigns doc.active_frame with no stroke finalization, and every subsequent PointerMove paints via stroke_active into doc.active_frame_mut().active_layer_mut() — i.e. onto the NEW frame/layer. At PointerUp, commit_edit deliberately resolves the stroke's ORIGINAL frame/layer by id ([audit F-29]) and diffs only that layer, so all pixels painted after the switch are visible on the new frame but appear in no undo record: Undo can never remove them.

**Why this is a gap.** Both sides were individually hardened — the engine id-pins the undo commit precisely because 'the DSL may have changed [the active frame] mid-stroke', and the shell guards the hold-Alt tool spring against active drags — but nobody specified what a frame/layer NAVIGATION should do to an in-flight stroke (abort it, finish it, or be refused). The result is a stroke that silently forks across two frames with half its pixels outside the undo history.

**Repro.** Frames 1 and 2 exist. Start a Pencil drag on the canvas and, while the finger is still down, tap frame 2 in the film roll with a second finger (or press Ctrl+.). Keep dragging, lift. Half the stroke is on frame 1, half on frame 2; pressing Undo removes only the frame-1 half — the frame-2 marks can never be undone.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.timeline.dart:68-72 and :496-497 (unguarded SetActiveFrame/SetActiveLayer taps); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/keyboard/commands.dart:152-167 (frame.prev/next enabled on frameCount only); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/keyboard/dispatcher.dart:191 (pointerActive gates only the Alt hold); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.canvas.dart:593-613 (_continueDraw keeps sending PointerMove); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/crates/engine/src/session.rs:2724-2728 (set_active_frame, no stroke handling), :1809-1814 (stroke_active paints the CURRENT active frame each move), :1184-1196 (commit_edit id-pinned — post-switch pixels excluded from the recorded patch)

**Verifier correction.** Applies to the Pencil (incl. pixel-perfect) only, which is what the repro uses. The coat family — Brush, Eraser, Airbrush x3, Dodge, Burn — is id-pinned end-to-end (open_coat captures fid/lid at session.rs:1444-1445; flatten_coat resolves by id at 1462-1468), so those strokes stay whole on the original layer and undo correctly after a mid-stroke frame switch. The finding's generic 'every subsequent PointerMove paints onto the NEW frame' overstates the affected tool set.

**Suggested behavior.** Either finish (PointerUp) or cancel (CancelStroke) the in-flight stroke before any SetActiveFrame/SetActiveLayer reaches the engine — mirroring what pointer_down already does defensively — or gate frame/layer navigation on _drawPointer == null the way the wheel-zoom handler gates itself.

### G-02 · Tap Commands dispatch during an in-flight canvas stroke (no pointerActive gate)

**Severity:** high · **Verdict:** confirmed · **Found by:** keyboard-dialogs

**Disposition (2026-08-26).** Closed by ADR 0010. Tap Commands finish the gesture first; Esc/Undo/Redo cancel it instead and consume the keystroke.

**Collision.** Keyboard tap Commands (tool mnemonics, frame.prev/next, frame.delete, edit.undo/redo, view.zoomIn/Out, sheet openers) vs. a mouse/touch stroke already in progress on the canvas

**Current behavior.** The dispatcher consults access.pointerActive only for the hold-Alt eyedropper spring (dispatcher.dart:191); the tap-dispatch path (dispatcher.dart:208-231) and every Command's enabled predicate (commands.dart) ignore it. So while a stroke is in flight (mouse button held, PointerDown already sent to the engine): pressing a tool mnemonic runs _selectTool, which sends SelectTool(...) plus the whole _pushToolSettings barrage mid-stroke and never ends or cancels the stroke (_drawPointer is untouched, editor_page.engine.dart:477-567) — subsequent _continueDraw calls then dispatch through the NEW tool's branch, so the stroke changes meaning under the finger and the original stroke never receives PointerUp; pressing ',' or '.' (repeats:true) runs _stepFrame -> SetActiveFrame mid-stroke (editor_page.engine.dart:1000-1008), splitting the remainder of the stroke onto another frame; Ctrl+Backspace deletes the frame currently being painted (editor_page.keyboard.dart:80-85); Ctrl+Z (repeats:true) sends Undo() into an open stroke; and Ctrl+= / Ctrl+- (repeats:true) call _zoomStep -> _zoomAt (editor_page.keyboard.dart:108-110, 192-201), shifting the screen-to-canvas mapping so the in-flight stroke jumps sideways — the exact hazard the mouse-wheel zoom path explicitly guards against with 'if (_drawPointer != null || _pinching) return' (editor_page.canvas.dart:221-227).

**Why this is a gap.** The design carefully specified this invariant for holds — the Alt spring refuses mid-drag because 'the stroke would change meaning under the finger' (dispatcher.dart:189-190), setSpacePan defers to drag-begin routing (editor_page.keyboard.dart:143-147), and the wheel zoom is suppressed mid-stroke — but nobody specified what tap Commands do while a pointer gesture is live. On desktop, left-hand-on-keyboard while right-hand draws is the normal workflow, so this state is hit constantly.

**Repro.** On Windows, start a Pencil stroke with the mouse and keep the button down; with the other hand press E (or '.', or Ctrl+Z, or hold Ctrl+=). The stroke switches tool / hops frames / undoes history / jumps position under the still-moving cursor, and the original stroke is left without a PointerUp.

**Evidence.** dispatcher.dart:208-231 (no pointerActive check in tap dispatch); dispatcher.dart:189-191 (holds ARE guarded); editor_page.canvas.dart:221-227 (wheel zoom guarded, keyboard zoom not); editor_page.engine.dart:477-567 (_selectTool neither cancels nor closes an in-flight stroke); editor_page.engine.dart:1000-1008 (_stepFrame has no drag guard); editor_page.keyboard.dart:80-85, 108-110; commands.dart:98-113, 152-188, 212-227 (enabled predicates never consult pointerActive)

**Verifier correction.** One detail is overbroad: for freehand-to-freehand tool switches (e.g. Pencil→Eraser), _endDraw's fallthrough branch still sends PointerUp() (editor_page.canvas.dart:674), so the engine stroke does close. PointerUp is lost only when the mid-stroke switch lands on a tool whose _endDraw takes a different branch (CopyPaste, Move, draft tools, cursor tools). The core claim — tap Commands fire un-gated mid-stroke and change the stroke's meaning, hop frames, undo, delete the frame being painted, or shift the zoom mapping — is correct.

**Suggested behavior.** Gate tap dispatch on access.pointerActive the way holds already are — either swallow chords mid-gesture, or (for view commands) allow only the ones that cannot change the stroke's meaning. At minimum, tool-select, frame, structural, and undo/redo Commands should be refused (or the stroke force-ended via PointerUp) while pointerActive is true.

### G-03 · Tool or Precision/mode switch mid-stroke re-routes _endDraw so PointerUp() is never sent — the engine stroke stays open and its undo step is deferred to the next touch

**Severity:** medium · **Verdict:** confirmed · **Found by:** canvas-gestures

**Disposition (2026-08-26).** Closed by ADR 0010. A gesture always ends under the tool it began with, via the old tool's path.

**Collision.** The begin/continue/end gesture dispatch keying on the CURRENT _tool at each event vs. tool changes landing mid-gesture (keyboard tool commands, enabled unconditionally; a second finger tapping a row-3 tile; the row-1 Precision chip)

**Current behavior.** _selectTool never touches _drawPointer or closes an in-flight stroke, and the engine's SelectTool arm just assigns self.tool. After a mid-stroke switch from Pencil to e.g. Move, _continueDraw and _endDraw dispatch into the Move branches (which return without sending PointerUp()), so the engine's self.stroke stays open: the painted marks are on the canvas but no undo step is recorded until the NEXT pointer_down defensively finalizes it (session.rs:1305). In the interim, Undo skips the stroke and undoes the action before it. Switching Pencil→Eraser mid-stroke instead keeps sending PointerMove, so one continuous gesture paints then erases and commits as a single undo step. Toggling Precision on mid-stroke hits the cursor branch of _endDraw with _penDown false — again no PointerUp.

**Why this is a gap.** Each dispatcher branch is correct for a gesture that begins and ends under one tool; the routing decision is re-taken per event, but nothing pins a gesture to the tool it began with (the way _panDragLast pins a Space-pan), and _selectTool's leave-cleanup covers drafts but not open pointer strokes.

**Repro.** On desktop, start a Pencil drag with the mouse and press M (Move) while dragging; release. The marks are drawn but pressing Ctrl+Z undoes the PREVIOUS action, not the stroke; the stroke only becomes undoable after the next canvas touch. Alternatively press E (Eraser) mid-drag: the same stroke starts erasing.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.engine.dart:477-567 (_selectTool: cancels drafts, never closes/aborts an open stroke); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.canvas.dart:616-677 (_endDraw dispatches on the current _tool; the Move/cursor/draft branches return without PointerUp()); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/keyboard/commands.dart:143-150 (tool commands enabled: _always); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/crates/engine/src/session.rs:246 (SelectTool(t) => self.tool = t) and :1301-1312 (open stroke finalized only by the next pointer_down)

**Verifier correction.** The Pencil→Eraser sub-claim is wrong: the engine's ADR-0007 dispatch (session.rs:1529-1543) paints nothing for a coat tool over a coat-less Pencil stroke (only the Pencil arms and the coat branch paint), and _endDraw's bottom path still sends PointerUp() for Eraser, whose commits_stroke() is true — so that variant commits the pencil half normally instead of 'the same stroke starts erasing'. The finding stands on the Move/draft/precision re-routing branches.

**Suggested behavior.** In _selectTool (and _setPrecision), if _drawPointer != null, first end or cancel the in-flight gesture via the OLD tool's path (send PointerUp()/CancelStroke() and clear _drawPointer), so a gesture always ends under the tool it began with.

### G-04 · Keyboard tool switch fires mid canvas stroke; the guard written for the hold-Alt eyedropper was not applied to tap tool Commands

**Severity:** medium · **Verdict:** confirmed · **Found by:** tools-controls

**Disposition (2026-08-26).** Closed by ADR 0010. Keyboard tool switches take the same finish-first path as every other competing Command.

**Collision.** A canvas stroke in progress vs. the tool-select keyboard Commands (and a second finger tapping a row-3 tile). The dispatcher's hold-Alt spring explicitly refuses to switch tools mid-drag ('the stroke would change meaning under the finger'), but plain tool Commands are enabled unconditionally.

**Current behavior.** commands.dart:143-150 gives every tool Command enabled:_always, and the dispatcher only consults access.pointerActive for the Alt spring (dispatcher.dart:189-195; pointerActive defined at keyboard.dart:36). Pressing a tool key mid-stroke runs the full _selectTool during the drag, and _continueDraw/_endDraw dispatch on the NEW _tool (canvas.dart:511-614, 616-677). Concrete outcomes: for a coat stroke (Brush/Airbrush/Dodge/Burn) the engine deliberately keeps painting the OLD tool until finger-up (session.rs:1529-1544) while the UI already shows the new tool selected; switching to Eyedropper mid-stroke makes the remaining drag pick colors per move (session.rs:1471-1481); switching to Move mid-stroke stops the shell from ever sending PointerUp, leaving the engine stroke open until the NEXT pointer_down finalizes it as a deferred undo record (session.rs:1301-1307).

**Why this is a gap.** The mid-drag hazard was recognized and encoded for one input route (the Alt hold spring) and for the canvas's own second-finger rule (_cancelDraw), but the tap tool Commands shipped without the same pointerActive gate - no one decided what a tool key mid-stroke should mean.

**Repro.** Start a Brush stroke with the mouse and, while dragging, press the Pencil key: the Pencil tile lights up but the stroke keeps painting brush marks until release. Or press the Move key mid-Pencil-stroke: the stroke freezes, and its undo record only lands when you next touch the canvas.

**Evidence.** app/lib/editor/keyboard/commands.dart:143-150; app/lib/editor/keyboard/dispatcher.dart:189-195; app/lib/editor/editor_page.keyboard.dart:36; app/lib/editor/editor_page.canvas.dart:511-614, 616-677; crates/engine/src/session.rs:1301-1307, 1471-1481, 1529-1544

**Suggested behavior.** Gate tool-select Commands on !access.pointerActive (as the Alt spring already does), or make _selectTool finalize/cancel an in-flight stroke before switching.

> Overlaps G-cluster: this is the tool-switch instance of the un-gated tap dispatch (see the umbrella finding above) with the `_endDraw` re-route mechanism as its damage path.

### G-05 · Undo/Redo can fire mid-stroke; undoing the finished stroke then resurrects the previously-undone action

**Severity:** medium · **Verdict:** confirmed · **Found by:** canvas-gestures

**Disposition (2026-08-26).** Closed by ADR 0010, via its Esc/Undo carve-out: Undo and Redo cancel the in-flight gesture and never reach history mid-stroke.

**Collision.** The always-armed Undo/Redo (pinned row-3 tiles tappable with a second finger; Z/Y keyboard commands gated only on canUndo/canRedo) vs. an open engine stroke edit

**Current behavior.** Mid-stroke, _doToolAction('Undo') sends Undo(), which runs doc.undo() with no stroke finalization — the previous committed action reverts on-screen under the still-painting stroke (wiping any of the stroke's marks that overlapped it). The stroke keeps painting on the reverted document; at PointerUp, commit_edit diffs the layer against the PRE-undo, pre-stroke snapshot, so the recorded patch bundles 'the stroke' together with 'the reversal of the undone action'. Undoing that one step later restores the pre-stroke snapshot — which resurrects the content the user explicitly undid mid-stroke — while the new record has also cleared the redo entry for it.

**Why this is a gap.** The undo commands were gated on history availability (canUndo/canRedo) and the pointerActive accessor exists on EditorAccess, but only the Alt-hold consults it; no one specified whether history stepping is legal while a stroke's begin_edit baseline is open, and the engine's Undo arm assumes no edit is in flight.

**Repro.** Draw dot A (one undo step). Start a long Brush drag and, mid-drag, tap the pinned Undo tile with a second finger (or press Z on desktop while dragging with the mouse): dot A vanishes. Finish the drag. Press Undo once more: the drag vanishes AND dot A reappears.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/keyboard/commands.dart:98-113 (edit.undo/redo enabled by canUndo/canRedo only, repeats:true); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.toolgrid.dart:50-67 and :146-152 (_doToolAction → _act('Undo()'); pinned tiles); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/crates/engine/src/session/parse.rs:374-383 (Undo runs doc.undo() with no stroke close); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/crates/engine/src/session.rs:1173-1203 (commit diffs against the stale pre-stroke EditScope.before)

**Suggested behavior.** Gate edit.undo/edit.redo (and the pinned tiles) on _drawPointer == null / !_pinching, or have the engine's Undo/Redo arms finalize or cancel the open stroke first.

### G-06 · Keyboard zoom commands shift the screen→canvas mapping mid-stroke — the exact invariant the wheel-zoom guard documents

**Severity:** medium · **Verdict:** confirmed · **Found by:** canvas-gestures

**Disposition (2026-08-26).** Closed by ADR 0010. Keyboard zoom finishes the stroke first, matching the wheel-zoom guard it was modeled on.

**Collision.** The wheel/trackpad zoom guards ('ignored while a stroke or pinch is in flight so an established gesture's screen→canvas mapping never shifts under the pointer') vs. the keyboard view.zoomIn/zoomOut/zoomFit/zoom100 commands, which have no such gate

**Current behavior.** onPointerSignal and onPointerPanZoomUpdate both refuse while _drawPointer != null, but view.zoomIn/zoomOut (repeats: true), view.zoomFit and view.zoom100 are enabled unconditionally and call _zoomAt/_fitView directly. Fired mid-stroke (keys with one hand, mouse drawing with the other), _zoom/_pan change and the very next _continueDraw maps the stationary pointer to a different canvas cell — the stroke teleports and the engine interpolates an unwanted straight line between the old and new cells. The same applies mid selection-drag, mid shape-handle drag, and mid ruler drag (all _drawPointer gestures).

**Why this is a gap.** The mapping-stability invariant was implemented locally in the two pointer-driven zoom routes; when the keyboard route to the same conceptual action was added later (v1 shortcuts), the guard was not carried over, so two input routes behave differently for the same action.

**Repro.** Start a slow Pencil drag with the mouse and press '+' (or hold it — it auto-repeats) mid-drag. The paint jumps to a different canvas position under the unmoving cursor, drawing a stray connecting line.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.canvas.dart:218-227 (wheel guard + invariant comment) and :240-241 (trackpad guard); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.keyboard.dart:108-114 and :190-206 (_zoomStep/_zoomTo/_fitView, unguarded); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/keyboard/commands.dart:212-241 (zoom commands enabled: _always, zoomIn/out repeat)

**Suggested behavior.** Give the zoom/fit Commands an enabled gate of !a.pointerActive (the accessor already exists), matching the pointer zoom routes.

### G-07 · Toggling Move's mode mid-mask-drag strands an open MoveSelectionBegin session, making later selection moves silently non-undoable

**Severity:** medium · **Verdict:** confirmed · **Found by:** canvas-gestures, tools-controls

**Disposition (2026-08-26).** Closed by ADR 0010. The Move mode toggle is competing input and ends the mask drag before flipping.

**Collision.** The MoveSelectionBegin/Commit coalescing protocol (Begin at drag start, Commit at drag end) vs. the row-1 'Move layer/pixels ↔ Move selection' toggle being tappable with a second finger while the drag is in flight

**Current behavior.** _beginDraw in mask mode sends MoveSelectionBegin(). If the mode toggle is tapped mid-drag (it only cancels a pending move DRAFT, not an in-flight mask drag), _endDraw dispatches into the _isMoveDrafting branch and MoveSelectionCommit() is never sent. Engine-side move_sel_before stays Some, and while it is set every MoveSelection updates the mask in place WITHOUT recording an undo step (session.rs:2245-2248). So after toggling back to mask mode, the nudge arrows and further drags move the marquee with no undo records — until some future drag's Commit finally lands, which then records everything since the stranded Begin (including previously 'finished' moves) as one giant step against a stale before-mask.

**Why this is a gap.** The Begin/Commit pairing assumes the gesture that opened the session also closes it; the mode toggle re-routes the close handler mid-gesture, and its mid-draft cleanup was specified (line 132-133) while the mid-mask-drag case was not.

**Repro.** Make a selection, choose Move → 'Move selection', start dragging the marquee, and mid-drag tap 'Move layer/pixels' in row-1 with a second finger; lift. Toggle back to 'Move selection' and use the nudge arrows: the marquee moves but Undo does not step those moves.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.canvas.dart:471-475 (Begin at drag start) and :648-653 (Commit only in the mask-mode branch of _endDraw); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.controls.dart:131-135 (toggle cancels only _hasMoveDraft); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/crates/engine/src/session.rs:2208-2222 (begin/commit) and :2245-2250 (in-place, record-free MoveSelection while the session is open)

**Suggested behavior.** Have the mode toggle (like its draft branch) close an in-flight gesture first: if a mask drag is live, send MoveSelectionCommit() and clear the drag state before flipping _moveSelectionMode.

> Also found independently by the tools-controls reviewer as “Toggling Move mode mid-drag orphans the engine's coalesced selection-move session, corrupting later undo granularity” — merged here.

### G-08 · A row-1 slider drag survives a tool switch and writes into the new tool's per-tool memory (or a different setting entirely)

**Severity:** low · **Verdict:** confirmed · **Found by:** tools-controls

**Disposition (2026-08-26).** Closed by ADR 0010, including its value-gesture rule: a control drag is in-flight state, committing on finish and reverting to the pre-drag value on cancel.

**Collision.** The geared slider's stateful drag (accumulator + live gesture survive rebuilds) vs. per-tool remembered options resolved at setter-call time, when the tool is switched mid-drag by a keyboard tool key or a second finger.

**Current behavior.** Size/Intensity are remembered per tool via maps keyed by the CURRENT _tool at setter execution (editor_page.dart:176-181, 260-261), and the Size closure writes through that setter (controls.dart:233-236). _GearedSlider keeps its drag accumulator and active gesture recognizer in State (toolgrid.dart:562-596), and the row-1 children carry no keys, so when a tool key (commands.dart:143-150, no mid-gesture guard) switches e.g. Pencil->Brush mid-drag, the same slider element continues the drag with the new closure: Pencil's mid-drag size value (plus further travel) is committed into Brush's remembered size, and the engine gets SetBrushSize for the wrong tool's intent. Worse, switching to a tool whose row-1 puts a DIFFERENT slider at that tree position (e.g. Pencil->Bucket, where the slot becomes Threshold, controls.dart:309-313) lets the continuing drag start driving Threshold from the old Size accumulator.

**Why this is a gap.** Per-tool option memory and the geared slider were each designed in isolation; nothing decided what an in-flight slider drag means once the tool underneath it changes, because on pure touch-with-one-finger that could never happen - keyboard shortcuts made it routine.

**Repro.** Set Brush size 30, switch to Pencil (size 1). Mouse-drag Pencil's Size slider and, while holding the drag, press the Brush tool key; keep dragging and release. Brush's remembered size is now Pencil's mid-drag value plus the extra travel, not 30.

**Evidence.** app/lib/editor/editor_page.dart:176-181, 260-261; app/lib/editor/editor_page.controls.dart:232-237, 309-313; app/lib/editor/editor_page.toolgrid.dart:550-597; app/lib/editor/keyboard/commands.dart:143-150

**Suggested behavior.** Key the row-1 option widgets by tool (ValueKey(_tool)) so a tool switch disposes the in-flight slider state, or capture the target tool in the onChanged closure instead of resolving _tool at setter time.

### G-09 · Lifting one finger of a 3-finger pinch re-pairs the pinch against the original pair's anchors — the view jumps

**Severity:** low · **Verdict:** confirmed · **Found by:** canvas-gestures

**Disposition (2026-08-26).** Point fix. Pinch-internal rather than a gesture-atomicity case: re-anchor from the current two pointers whenever the touching set changes.

**Collision.** The pinch math (anchored to _pinchStartDist/_pinchStartMid captured at _startPinch from the first two fingers) vs. _endTouch, which keeps _pinching true while ≥2 fingers remain but never re-anchors when the finger PAIR changes

**Current behavior.** _updatePinch always reads pts[0]/pts[1] of the insertion-ordered _touchPos map. With three fingers down, lifting one of the ORIGINAL pair leaves two fingers whose distance/midpoint bear no relation to the recorded start distance/midpoint; the next move applies the ratio against the stale anchors and the canvas abruptly zooms/pans. (Dropping to one finger and re-adding correctly re-anchors via _startPinch — only the ≥3→2 transition skips it.)

**Why this is a gap.** The two-finger state machine was specified for exactly two fingers; a third resting finger (common when holding a tablet) enters _touchPos but was never considered in the pair-selection or re-anchoring rules.

**Repro.** On a touch device, pinch with two fingers, rest a third finger on the canvas, then lift the FIRST finger while continuing to move: the view lurches to a different zoom/pan.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.canvas.dart:398-402 (_endTouch: stays pinching while ≥2 fingers, no re-anchor); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.engine.dart:860-887 (_startPinch/_updatePinch use pts[0]/pts[1] vs the start-time anchors)

**Suggested behavior.** Re-run _startPinch (re-anchor from the current two fingers and the current _zoom/_pan) whenever the set of touching pointers changes while _pinching.

### G-10 · Trackpad pan/zoom started mid-stroke applies its whole accumulated transform in one jump when the stroke ends; the no-hover fallback anchor is the value the code itself distrusts

**Severity:** low · **Verdict:** confirmed · **Found by:** canvas-gestures

**Disposition (2026-08-26).** Closed by ADR 0010. Trackpad gestures join the in-flight predicate, so one started mid-stroke is never admitted.

**Collision.** The trackpad gesture's cumulative-from-start model vs. the mid-stroke guard being on Update only (Start is unguarded), plus the hover-tracked focal anchor vs. a first gesture that arrives before any hover event

**Current behavior.** onPointerPanZoomStart records _trackpadStartZoom/Pan/Focal even while a stroke or pinch is in flight; onPointerPanZoomUpdate then drops events until the stroke ends, after which the next update applies the ENTIRE accumulated e.pan/e.scale since gesture start in a single frame — a sudden view leap rather than either a clean refusal or a smooth resume. Separately, the anchor falls back to e.localPosition when _canvasHoverPos is null (no hover yet since the canvas mounted), which is exactly the value the adjacent comment documents as unreliable on Windows ('can arrive as the window origin', 'sent the canvas flying sideways').

**Why this is a gap.** The e96cd38/b88c056 fixes specified the anchor and the drift-free math for a gesture in isolation; the interaction with an overlapping stroke (start vs update asymmetry) and the cold-start no-hover case were left to fall through to the old, known-bad inputs.

**Repro.** On a Windows laptop, draw with the mouse while two fingers begin a scroll/pinch on the precision touchpad; release the mouse mid-trackpad-gesture — the canvas leaps by the whole accumulated pan/zoom. Or: open the editor and pinch the touchpad before ever moving the cursor over the canvas — the canvas can fly toward the window origin.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.canvas.dart:234-249 (Start unguarded, Update guarded on _drawPointer/_pinching, fallback anchor e.localPosition); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.dart:373-384 (comment: the PanZoom event position is untrusted on Windows)

**Suggested behavior.** Ignore a trackpad gesture entirely if it STARTED while _drawPointer/_pinching was set (latch a bool at Start, checked by Update), and when _canvasHoverPos is null refuse the zoom or anchor at the canvas box center instead of the untrusted event position.

### G-11 · A stroke in progress keeps painting underneath a modal palette sheet opened by a second finger

**Severity:** low · **Verdict:** confirmed · **Found by:** palette-color

**Disposition (2026-08-26).** Closed by ADR 0010. Opening a palette sheet is competing input and finishes the stroke first.

**Collision.** Multi-touch: an in-progress canvas stroke x the row-2 palette sheets (swatch menu / add-color menu), which assume they interrupt interaction

**Current behavior.** The palette strip sits outside the canvas Listener, so a second finger long-pressing a swatch (or the empty strip area) opens a modal bottom sheet mid-stroke (editor_page.controls.dart:885-921). Flutter routes move events to the gesture that won the arena at pointer-down, so the first finger keeps delivering PointerMove strokes to the engine under the sheet's barrier — the user paints blind behind the sheet. The sheets pause playback (906, 941) but nothing ends or suspends the active stroke, and the sheet's palette mutations (Remove/Edit/Swap via _act) interleave with the stroke's PointerMove stream in the journal. By contrast the canvas's own second-finger path deliberately aborts the draw before pinching (editor_page.canvas.dart:186-193), and the right-click pick refuses to run mid-stroke (canvas.dart:376) — the palette sheets are the one surface with no mid-stroke policy.

**Why this is a gap.** Each feature is sensible alone: strokes must survive incidental UI events, and the palette sheets pause playback because they were specified against the playback collision — but the stroke-in-progress collision was never specified for them, while sibling paths (pinch abort, _secondaryPick guard) show the pattern that was intended elsewhere.

**Repro.** On a touch device, start a slow drag with one finger on the canvas; with a second finger long-press a palette swatch. The menu opens while the first finger continues painting under the sheet; lifting it later ends a stroke drawn blind.

**Evidence.** app/lib/editor/editor_page.controls.dart:840-846 and 885-921 (strip gestures open modal sheets, no stroke guard), 905-906/940-941 (only _playing handled); app/lib/editor/editor_page.canvas.dart:186-193 (second canvas finger aborts the draw), 376 (_secondaryPick's _drawPointer guard shows the mid-stroke concern)

**Suggested behavior.** Mirror the pinch/right-click policy: when a palette sheet (or the add-color menu) opens, end or cancel the in-progress stroke — or refuse to open the sheet while _drawPointer != null.

### G-12 · Hold-Primary cheat-sheet overlay can appear over an in-progress stroke

**Severity:** low · **Verdict:** confirmed · **Found by:** keyboard-dialogs

**Disposition (2026-08-26).** Closed by ADR 0010. The cheat-sheet overlay does not arm while a gesture is in flight.

**Collision.** The hold-Ctrl (Primary) 600 ms cheat-sheet overlay vs. a canvas stroke drawn while Ctrl happens to be held

**Current behavior.** The overlay timer arms on a bare Primary keydown and is canceled only by another keydown, Primary keyUp, or focus loss (dispatcher.dart:121-133); pointer activity never cancels it, and the canvas Listener draws regardless of held modifiers (editor_page.canvas.dart:178-204 has no modifier filter). So a user who presses Ctrl (e.g. lining up Ctrl+Z) and then starts or continues a mouse stroke gets, 600 ms later, the full-screen dark reference card (KeyboardOverlay, dispatcher.dart:255-261) covering the artwork mid-stroke; the stroke continues invisibly beneath it (the overlay is IgnorePointer, cheat_sheet.dart:100-127) until Ctrl is released.

**Why this is a gap.** The overlay's disarm conditions were specified in keyboard terms only ('any other key, or release'); nobody specified what the reference card should do while the pointer is actively drawing — a state where covering the canvas is exactly wrong.

**Repro.** Hold Ctrl, then press and drag the mouse on the canvas and keep dragging for a second without pressing any other key: the shortcut overlay fades in over the canvas while your stroke continues under it.

**Evidence.** dispatcher.dart:121-133 (arm/disarm machine, no pointer condition), 255-261 (full-screen overlay); cheat_sheet.dart:100-127 (IgnorePointer, 0xC0000000 scrim); editor_page.canvas.dart:178-204 (strokes start regardless of held Ctrl)

**Suggested behavior.** Cancel (or refuse to arm) the overlay timer while access.pointerActive is true, mirroring the hold-Alt guard.

## Draft lifecycle

Drafts (Move/Rotate/Scale transforms, shape/gradient figures, HSV/BC/Levels previews, floating paste) are canceled on row-3 tool switch — and on nothing else. Frame navigation, document switches, and even Post to Club leave them armed, and the two draft families resolve their target differently (transform drafts are fid-pinned, figure/adjust drafts commit to whatever is active), so the same user action lands in two different wrong places depending on tool.

### G-13 · Frame-bound transform drafts (Move/Rotate/Scale) survive frame switches as invisible armed state

**Severity:** high · **Verdict:** confirmed · **Found by:** tools-controls

**Disposition (2026-08-26).** Closed by ADR 0011 (draft lifecycle). A frame change is a context change and cancels every open Draft.

**Collision.** An open Move/Rotate/Scale draft (engine-side, bound to its frame by fid) vs. frame navigation that does not cancel drafts (film-roll tap, keyboard frame.prev/next). Only a row-3 tool switch cancels drafts.

**Current behavior.** The engine's set_active_frame (crates/engine/src/session.rs:2724-2729) does not touch move_draft/rotate_draft/scale_draft, and the draft-rect reporters the shell's state JSON is built from (move_draft_rect session.rs:3222-3227; rotate_draft_rect canvas.rs:593-597; scale_draft_rect canvas.rs:878-882) report the draft regardless of the active frame, while the previews/washes are fid-gated (move_draft_preview_frame session.rs:3177-3186; rotate_draft_preview_frame canvas.rs:531-543). So after tapping another frame in the film roll (editor_page.timeline.dart:69-72) or pressing keyboard frame-step (commands.dart:152-167 -> _stepFrame, which never cancels drafts) with a draft open: (a) the floating Commit/Cancel pill and the rotate/resize handle stay on screen over the NEW frame with no preview behind them; (b) dragging the canvas or the row-1 nudge arrows (editor_page.canvas.dart:477-487, 561-575; editor_page.timeline.dart:405-418) sends MoveDraftMove/RotateDraftSetAngle with ZERO visual feedback while silently mutating the hidden draft; (c) Commit mutates the ORIGINAL, off-screen frame (move_draft_commit session.rs:3191-3211 and rotate_draft_commit canvas.rs:492-521 resolve the frame by fid); (d) the Move tool is wedged on the new frame because move_draft_begin refuses while a draft is open (session.rs:3085-3088), so drags do nothing until the invisible draft is resolved; (e) the Undo tile lights up and 'cancels' a draft the user cannot see (editor_page.toolgrid.dart:44-45, 55-56).

**Why this is a gap.** Tool switching was explicitly specified to cancel every draft (editor_page.engine.dart:489-525), and the pinch-interrupt and blank-document paths were also thought through, but frame navigation was never given a draft policy: the engine deliberately keeps drafts non-destructive and fid-bound, the shell deliberately keeps the commit pill up whenever state JSON reports a draft, and nobody decided what the combination should do.

**Repro.** 1) Move tool, drag pixels so the move draft lifts (commit pill appears). 2) Tap a different frame in the film roll. 3) Note the pill remains, the draft preview is gone, and dragging on the canvas does nothing visible. 4) Press Commit -> nothing visible changes; switch back to the first frame -> its pixels moved (including any invisible drags from step 3). Same shape with Rotate > Angle or Resize > Scale plus keyboard frame-step.

**Evidence.** crates/engine/src/session.rs:2724-2729, 3085-3088, 3177-3186, 3191-3211, 3222-3227; crates/engine/src/session/canvas.rs:492-521, 531-543, 593-597, 878-882; app/lib/editor/editor_page.timeline.dart:69-72, 405-418; app/lib/editor/editor_page.engine.dart:489-525, 1000-1008; app/lib/editor/keyboard/commands.dart:152-167; app/lib/editor/editor_page.canvas.dart:477-487, 561-575; app/lib/editor/editor_page.toolgrid.dart:44-45, 55-67

**Suggested behavior.** Cancel (or commit) any open transform draft on SetActiveFrame, mirroring the tool-switch contract - e.g. route every frame change through a _cancelActiveDraft-style guard, or have the engine drop fid-bound drafts in set_active_frame.

### G-14 · Undo/Redo while a Rotate/Scale draft is open silently rewinds history and resurrects undone pixels on Commit

**Severity:** high · **Verdict:** confirmed · **Found by:** tools-controls

**Disposition (2026-08-26).** Closed by ADR 0011 with ADR 0010: Undo/Redo cancel the Draft rather than rewinding history underneath it.

**Collision.** The committed undo history vs. an open Rotate/Scale draft that holds stale lifted pixel snapshots. The Undo tile/Ctrl+Z stays enabled mid-draft, but the draft preview masks what undo does.

**Current behavior.** Engine Undo just steps history (session/parse.rs:374-383), never touching an open draft. The rotate preview clones the current frame, CLEARS the lifted layer, and blits the snapshot taken at draft-begin (apply_rotation_to_frame canvas.rs:999-1036, used by rotate_draft_preview_frame canvas.rs:531-543). So with a Rotate 'Angle' draft open on a layer, pressing Undo (tile: editor_page.toolgrid.dart:50-67; Ctrl+Z routes to the same path via commands.dart:98-113 and keyboard.dart:43) visibly does NOTHING - the stale snapshot repaints over the undone content - inviting the user to press Undo repeatedly and blindly rewind many steps. Commit then bakes the pre-undo snapshot back onto the rewound frame (resurrecting undone strokes as a new undo step), while Cancel suddenly reveals a canvas several steps older than what was on screen. The shell already recognized this class of problem for the Move draft - _doToolAction makes Undo/Redo discard a pending move draft first (toolgrid.dart:44-45, 52-56 with an explicit comment) - but Rotate and Scale drafts got no equivalent rule.

**Why this is a gap.** The move-draft/undo interaction was explicitly designed ('Undo/Redo first discard an in-progress move draft'), proving the collision was known; the same decision was never extended to the rotate/scale drafts, which are strictly more dangerous because their previews repaint from stale snapshots and fully mask the history step.

**Repro.** 1) Draw a stroke. 2) Rotate tool -> Angle (draft opens; the stroke is lifted into it). 3) Press the Undo tile or Ctrl+Z: nothing visible happens, though history stepped back. 4) Press it a few more times (still nothing visible). 5) Commit: the stroke reappears rotated on a frame whose other recent strokes are gone; or Cancel: the canvas jumps back several undo steps at once.

**Evidence.** crates/engine/src/session/parse.rs:374-383; crates/engine/src/session/canvas.rs:531-543, 999-1036; app/lib/editor/editor_page.toolgrid.dart:41-67; app/lib/editor/keyboard/commands.dart:98-113; app/lib/editor/editor_page.keyboard.dart:43-45

**Suggested behavior.** Extend the existing move-draft rule: Undo/Redo with a rotate/scale draft open should first cancel (or commit) the draft, exactly as they discard a move draft today.

### G-15 · Open drafts survive frame switches inconsistently: a shape/gradient draft commits onto the NEW frame, a Rotate/Resize draft commits invisibly onto the OLD one

**Severity:** medium · **Verdict:** confirmed · **Found by:** canvas-gestures

**Disposition (2026-08-26).** Closed by ADR 0011. One rule for both Draft families, so neither commits onto a frame the artist is not looking at.

**Collision.** Draft lifetimes (canceled on tool switch, but not on frame navigation) vs. SetActiveFrame from the film-roll tap or frame.prev/next keys while a draft is open

**Current behavior.** Switching tools cancels every draft (_selectTool), but switching FRAMES cancels none, and the frame commands/film-roll taps are not gated on _hasAnyDraft. A pending Line/Shape/Gradient draft is stored as session-level endpoints and shape_commit rasterizes via begin_edit() on the CURRENT active frame — so a figure drafted over frame 1 silently commits onto frame 2 after a mid-draft frame switch (the preview and handles float over the new frame's pixels). A Rotate/Resize draft is the opposite: its commit is fid-pinned (frame_index_by_id(d.fid)), so after switching frames the handle overlay and commit menu remain live over frame 2 while dragging the handle and pressing Commit mutate frame 1, with no visible preview of what is changing.

**Why this is a gap.** Draft cancellation was specified for the tool axis ('every tool switch cancels the outgoing tool's draft', _hasAnyDraft's comment) but never for the frame axis; the two engine draft families then answered the 'which frame?' question independently and oppositely, so neither the preview nor the commit target is consistent under a frame switch.

**Repro.** Draft a rectangle with the Shape tool on frame 1 (don't commit), tap frame 2 in the film roll, press the floating Commit: the rectangle rasterizes onto frame 2. Conversely open Rotate → Angle on frame 1, switch to frame 2, drag the still-visible handle and Commit: frame 1 changes while you watch frame 2.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.engine.dart:477-567 (_selectTool cancels drafts; _stepFrame at :1000-1008 does not) ; C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.timeline.dart:68-72 (film-roll tap, no draft handling); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/crates/engine/src/session.rs:1728-1742 (shape_commit uses begin_edit → CURRENT active frame/layer); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/crates/engine/src/session/canvas.rs:492-510 (rotate_draft_commit resolves the ORIGINAL frame by fid)

**Suggested behavior.** Pick one rule and apply it to all drafts on SetActiveFrame: either cancel the pending draft (matching the tool-switch contract) or block frame navigation while _hasAnyDraft; if drafts are meant to survive, both families should target the same frame and keep their preview visible on it.

### G-16 · Shape/gradient and HSV/BC/Levels drafts retarget to whatever frame/layer is active at Commit time

**Severity:** medium · **Verdict:** confirmed · **Found by:** tools-controls

**Disposition (2026-08-26).** Closed by ADR 0011. A Draft cannot outlive the frame or layer it was made on, so there is nothing left to retarget at Commit.

**Collision.** Pending frame/layer-agnostic drafts (figure draft, selection-shape draft, non-identity HSV/Brightness-Contrast/Levels previews) vs. frame taps, layer taps, and keyboard frame stepping, none of which cancel drafts.

**Current behavior.** The engine's shape_draft is a bare endpoint pair with no frame binding (session.rs:287, 1709-1716) and shape_commit rasterizes into the active frame's active layer at commit time (session.rs:1728-1766); the HSV/BC/Levels pending settings are session-level and preview against the active layer/frame. Tool switching deliberately cancels all of these 'so returning starts clean' (editor_page.engine.dart:489-525), but tapping a frame thumbnail (timeline.dart:69-72), tapping a layer tile (timeline.dart:497), or keyboard frame.prev/next leaves them pending. Result: draft a line on frame 1, tap frame 2, press Commit -> the line is drawn into frame 2; dial Levels while looking at layer A, tap layer B -> the adjustment instantly re-previews on B and Commit bakes it into B; a purely shell-side Select-Shape draft (editor_page.dart:216-233) likewise commits a selection on whatever frame is now active (_commitSelDraft replays a pointer drag, engine.dart:692-706).

**Why this is a gap.** A cancel-on-leave contract exists and is enforced for one navigation axis (tools) but was never decided for the other two (frames, layers); the engine and shell each keep the draft alive for their own good reasons, and the combination lets a draft silently change its target between preview and commit.

**Repro.** Line tool, drag a draft (don't commit). Tap another frame in the film roll: the draft preview and handles ride onto the new frame. Commit -> the figure lands on the frame you navigated to, not the one you drafted on. Or: Levels tool, drag the thumbs, tap a different layer tile, Commit -> the remap applies to the newly tapped layer.

**Evidence.** crates/engine/src/session.rs:287, 1709-1716, 1728-1766, 2724-2729; app/lib/editor/editor_page.engine.dart:489-525, 692-706; app/lib/editor/editor_page.timeline.dart:69-72, 497; app/lib/editor/editor_page.controls.dart:515-634

**Suggested behavior.** Pick one rule and apply it to frames and layers like tools: either cancel pending drafts on SetActiveFrame/SetActiveLayer, or pin each draft to the frame/layer it was drafted on and commit there.

### G-17 · Pending drafts survive document switches (Open / New) and can commit into the wrong document

**Severity:** medium · **Verdict:** confirmed · **Found by:** tools-controls

**Disposition (2026-08-26).** Closed by ADR 0011. A document switch is a context change; the adopt/switch funnel cancels every Draft.

**Collision.** Pending drafts (figure draft, selection-shape draft, HSV/BC/Levels previews) vs. the document-switch flows (File > New, File > Open, My Drawings), which release the outgoing drawing but never clear draft state.

**Current behavior.** adopt_loaded_doc clears clipboard/paste/move drafts but NOT shape_draft, rotate_draft, scale_draft, or the pending HSV/BC/Levels settings (session.rs:3478-3490), and the shell never resets _shapeA/_shapeB, _selA/_selB, or the adjust sliders on a switch (_adopt persistence.dart:136-148; _openExistingDrawing 292-306; _switchToNewDrawing 280-288; _newDialog toolgrid.dart:435-453). So: open another drawing from the gallery while a Line draft is pending -> the draft preview and commit pill appear over the just-loaded artwork and Commit rasterizes the stale figure into it; open while HSV sliders are non-zero -> the loaded artwork immediately renders color-shifted with a commit pill floating; a pure shell Select-Shape draft commits a selection onto the new document at the old coordinates. File > New replaces the whole engine session (parse.rs:211-218), so there the shell shows ghost handles plus a commit pill over the fresh canvas whose Commit is an engine no-op (shape_commit returns on a None draft, session.rs:1738-1741) that still clears the shell state.

**Why this is a gap.** The document-switch funnel was carefully specified for persistence concerns (keep/discard ask, journal attach, thumb caches) and the engine's F-29 fix shows stale-draft-across-load was recognized for the move draft specifically - but the sweep never covered the other draft kinds or the shell-side draft fields.

**Repro.** Line tool, drag a draft. Menu > File > My Drawings > open another drawing (keep the current one). The opened artwork shows the old line draft + commit pill; Commit draws the stale line into the newly opened drawing as its first undo step. Variant: set HSV H to +120, then open another drawing - it loads visibly hue-shifted.

**Evidence.** crates/engine/src/session.rs:3478-3490, 1738-1741; crates/engine/src/session/parse.rs:211-218; app/lib/editor/editor_page.persistence.dart:136-148, 280-306; app/lib/editor/editor_page.toolgrid.dart:435-453; app/lib/editor/editor_page.dart:199, 216-233, 275-281

**Suggested behavior.** Clear every draft (engine and shell: figure, selection draft, rotate/scale, HSV/BC/Levels sliders) in the _adopt/_switchToNewDrawing funnel, matching what tool switches already do.

### G-18 · Right-click canvas color pick is silently dead during any draft - including mere non-zero HSV/BC/Levels sliders - and during playback

**Severity:** low · **Verdict:** confirmed · **Found by:** tools-controls

**Disposition (2026-08-26).** ACCEPTED AS DESIGNED (ADR 0011). The inertness guard stays as broad as the lifecycle - a merely touched Levels slider still blocks the pick - but a refused pick now flashes the commit pill and names the blocker. This is the Editor's only non-silent interaction event.

**Collision.** The desktop right-click eyedropper vs. _hasAnyDraft, which includes the adjust tools' 'a non-identity slider IS a draft' definition, and vs. running playback.

**Current behavior.** _secondaryPick returns silently when _hasAnyDraft or _playing (canvas.dart:375-376), and _hasAnyDraft counts a pending gradient/figure draft and any non-identity HSV/BC/Levels preview (editor_page.dart:530-546). So during a Gradient draft - exactly when row-1 shows the gradient color swatches inviting color choices (controls.dart:426-439) - right-clicking the canvas to pick a color does nothing, with no feedback; and since switching to the Eyedropper tool would CANCEL the draft (engine.dart:489-491), there is no way at all to pick a canvas color into a pending gradient. The same silent no-op applies while a Levels/HSV preview is merely non-zero, where a pick would be harmless (it only sets the primary).

**Why this is a gap.** The guard was written to protect tool-bound drafts from the momentary SelectTool round-trip, but _hasAnyDraft is a much broader predicate than 'a draft the round-trip could corrupt'; nobody specified which drafts actually need the guard, nor any feedback for the refused pick.

**Repro.** Windows: Gradient tool, drag a gradient draft; right-click a canvas pixel to make it the gradient's first color: nothing happens, no message. Cancel the draft and right-click again: the pick works.

**Evidence.** app/lib/editor/editor_page.canvas.dart:369-394 (guard at 375-376); app/lib/editor/editor_page.dart:530-546; app/lib/editor/editor_page.controls.dart:404-439; app/lib/editor/editor_page.engine.dart:489-491

**Verifier correction.** Accurate behavior, but partially a documented design choice: the canvas.dart:369-374 comment shows the inertness during drafts/playback was deliberate. The unspecified part is the guard's breadth — _hasAnyDraft includes draft kinds (shape/gradient, HSV/BC/Levels previews) that the momentary engine-only SelectTool round-trip could not corrupt — and the total absence of feedback for a refused pick.

**Suggested behavior.** Narrow the guard to drafts the tool round-trip can actually disturb (or pick via EyedropCursor-style sampling without a tool swap), and give refused picks some feedback.

### G-19 · 'From artwork colors' extracts from the un-baked document, ignoring any pending draft/preview the user is looking at

**Severity:** low · **Verdict:** confirmed · **Found by:** palette-color

**Disposition (2026-08-26).** Point fix. Pushing the palette page is not a context change, so the Draft rule never fires; warn when extraction would ignore a pending Draft.

**Collision.** Pending drafts (HSV/BC/Levels display-only previews, floating paste, shape drafts) x opening the palette page and extracting the artwork's colors

**Current behavior.** _openPalettePage does not resolve or guard against pending drafts (editor_page.controls.dart:926-938), unlike _selectTool which cancels every draft kind on tool exit (editor_page.engine.dart:488-525). The palette page's 'From artwork colors' calls usedColorsJson, which scans the document only (crates/engine/src/session.rs:2417-2427 -> probe::used_colors(&self.doc)); HSV/BC/Levels previews are display-time-only and floating paste pixels are not in the document until commit. So a user who has just recolored the whole layer with the HSV sliders (draft pending, commit menu showing) and opens Palettes -> Add -> From artwork colors gets a palette of the ORIGINAL colors, not the recolored ones filling the screen behind the page.

**Why this is a gap.** Each side is correct in isolation — previews are deliberately display-only, and used_colors deliberately reads the document — but the palette page being reachable mid-draft was never considered (the page's own docs discuss caps and destructive ops, not drafts), so 'artwork colors' can disagree with the visible artwork.

**Repro.** Select HsvShift, drag Hue +120 (layer visibly recolored, commit menu showing), tap the palette icon on row-2, Add -> From artwork colors. The created palette contains the pre-shift colors.

**Evidence.** app/lib/editor/editor_page.controls.dart:926-938 (no draft guard on push); app/lib/editor/editor_page.engine.dart:488-525 (_selectTool's draft-cancel contract shows drafts were handled everywhere else); app/lib/editor/palette_page.dart:368-388 (_fromArtwork); crates/engine/src/session.rs:2417-2427 (used_colors reads self.doc)

**Suggested behavior.** Either block/pause: resolve (or prompt to commit/cancel) a pending draft before pushing the palette page, or have _fromArtwork warn when a draft is pending that extraction uses the committed document.

## Playback

Playback auto-pause is a per-call-site convention, not a policy: some routes to the same conceptual action pause first, others don't. And canvas inertness is keyed to the Play *tool* being selected rather than playback *running*, so keyboard-started playback leaves the entire editing surface live under the animation.

### G-20 · Timer-parked playback freezes (up to 1 hour) when Undo empties the timeline mid-playback

**Severity:** medium · **Verdict:** confirmed · **Found by:** timeline-playback

**Disposition (2026-08-26).** Closed by ADR 0012 (playback is a mode). Undo pauses playback like every other structural mutation, so the clock cannot park.

> Severity note: the sweep's verifier downgraded this from high: the freeze is recoverable in one tap (frame step, Esc, or any tool switch all pause), so no work is lost — but the frozen-animation-with-disabled-Pause state is real and visibly broken until then.

**Collision.** The hybrid playback clock's timer-parking (battery R3) vs Undo/Redo, which stay live during playback and can change the frame count

**Current behavior.** The pinned Undo tile does not pause playback (editor_page.toolgrid.dart:50-67 has no _pause(), unlike keyboard duplicate/deleteFrame). AddFrame is an undoable edit_doc record (session.rs:2647-2659). With 2 frames playing, tapping Undo (undoing the AddFrame) drops the doc to 1 frame; the next play poll gets play_status's IDLE_WAIT_US = 3_600_000_000 us (session.rs:1094-1102), and _maybeParkOnTimer (editor_page.engine.dart:946-951) stops the ticker and arms a ONE-HOUR Timer with no upper bound. _playing stays true, the animation freezes, and because engine.frameCount is now 1 the row-1 Play/Pause button becomes DISABLED (editor_page.controls.dart:776: onPressed: n > 1 ? ... : null) - a disabled 'Pause' while stuck playing. Tapping Redo restores the frame but nothing re-arms the ticker or the timer, so playback stays frozen until the hour elapses or the user finds another pause route (Esc, prev/next, a tool switch, or a menu).

**Why this is a gap.** The pause-on-structural-ops rule was applied to the frame sheet and the keyboard duplicate/delete, but Undo/Redo were left un-gated ('a pending move draft makes Undo/Redo live' was the only case considered), and the timer-parking design assumed 'menus/routes pause playback' covers every timeline mutation (playback_clock.dart:48 comment). Nobody specified what a park does when the timeline it parked against is undone out from under it, or that a re-grown timeline should re-arm the clock.

**Repro.** New 1-frame doc -> tap the film-roll + to add a frame -> select the Play tool -> Play -> while it animates, tap the pinned Undo tile. The animation freezes, the Play/Pause button greys out while labeled Pause, and Redo does not resume it.

**Evidence.** editor_page.toolgrid.dart:50-67 (_doToolAction Undo/Redo, no pause); editor_page.engine.dart:946-951 (_maybeParkOnTimer, unbounded nextUs -> Timer); crates/engine/src/session.rs:1094-1102 (IDLE_WAIT_US = 1 h for n<=1); crates/engine/src/session.rs:2647-2659 (add_frame is an undoable edit_doc); editor_page.controls.dart:776 (Pause button disabled at n<=1)

**Verifier correction.** Severity is medium, not high: the state is not truly stuck and no work is lost. Recovery is one tap away on the same row-1 (prev/next frame both _pause() first, engine.dart:1000-1008), Esc (playback.stop is enabled because _playing is still true), any tool switch (_selectTool pauses, engine.dart:481), or Redo followed by the now re-enabled Pause button. The frozen-with-disabled-Pause state is visibly broken but trivially recoverable.

**Suggested behavior.** Undo/Redo (like every other structural control) auto-pause playback; alternatively, any _act during playback re-arms the clock (cancel the pending park timer and restart the ticker), and playback force-pauses when frameCount drops to 1.

### G-21 · Drawing during keyboard-started playback lands invisibly on the active frame (right-click pick guards playback, left-button drawing does not)

**Severity:** medium · **Verdict:** confirmed · **Found by:** canvas-gestures, timeline-playback

**Disposition (2026-08-26).** Closed by ADR 0012. Canvas inertness keys on playback running rather than on the Play tool, and a stroke pauses first.

**Collision.** Vsync playback preview (which owns the displayed image: compositeFrame(playFrame)) vs. the canvas draw path, reachable because keyboard playback.toggle starts playback WITHOUT switching to the Play tool

**Current behavior.** Selecting the Play tool makes the canvas inert, and _selectTool pauses playback on any tool change — but pressing Enter (playback.toggle) with e.g. Pencil active starts playback while the canvas stays live: _beginDraw has no _playing guard, so drags send PointerDown/PointerMove that paint the engine's ACTIVE frame while _present shows the animating playFrame composite — the user paints blind (marks flash only when playback passes the active frame). A left-click Eyedropper likewise samples the active frame's composite, not the frame on screen. Meanwhile _secondaryPick explicitly refuses during playback ('the vsync clock owns the engine'), so the two pick routes disagree, and the engine tick handler itself carries a TEMPORARY note that edit-during-playback is still legal.

**Why this is a gap.** The 'canvas is inert during playback' invariant was implemented as a property of the Play TOOL (_isInertCanvasTool), then the keyboard feature added a way to start playback without entering that tool; the right-click path (newer) added its own _playing guard but the original left-button path was never revisited.

**Repro.** Open a multi-frame drawing, keep Pencil selected, press Enter to start playback, then drag on the canvas. Nothing appears to happen (or marks flicker), but pausing reveals a full stroke painted across the active frame. Right-clicking during the same playback correctly does nothing.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/keyboard/editor_page.keyboard.dart:176-179 (_togglePlay does not change tool) [file: editor_page.keyboard.dart]; C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.dart:437-441 (inertness keyed to the Play tool); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.canvas.dart:196-204 (_beginDraw: no _playing guard) vs :375-376 (_secondaryPick: guarded on _playing); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.engine.dart:285-295 (playing branch displays compositeFrame(playFrame)) and :913-921 (TEMPORARY edits-during-playback note)

**Suggested behavior.** Make _beginDraw auto-pause playback (matching every other interaction: menus, tool switches, sheets) or refuse strokes while _playing, matching _secondaryPick.

> Also found independently by the timeline-playback reviewer as “Keyboard-started playback leaves the whole editing surface live: painting lands invisibly on the active frame” — merged here.

### G-22 · Ctrl+V during playback (CopyPaste tool active) creates an invisible paste draft and silently reassigns Enter/Esc

**Severity:** medium · **Verdict:** confirmed · **Found by:** keyboard-dialogs

**Disposition (2026-08-26).** Closed by ADR 0012. Paste pauses playback, so the Draft is created in the paused editing view where its preview and commit menu are visible.

**Collision.** edit.paste vs. running playback, and the draft pair's registry priority over the playback pair on the shared Enter/Esc chords

**Current behavior.** pasteFromKeyboard only pauses playback indirectly, via _selectTool, and only when the tool is not already CopyPaste (editor_page.keyboard.dart:57-62). With the CopyPaste tool selected and playback running (Enter starts playback without changing tool — _togglePlay, editor_page.keyboard.dart:176-179), Ctrl+V sends PasteDraft() into the playing engine without pausing. The paste preview lives only in the editing display, but while _playing the presenter composites engine.compositeFrame(playFrame) instead (editor_page.engine.dart:285-295), so the draft is completely invisible. hasAnyDraft is now true, which flips the shared bindings: Enter resolves to draft.commit and Esc to draft.cancel ahead of playback.toggle/playback.stop (registry order, commands.dart:64-96; bindings default_bindings.dart:24-27). The user watching their animation presses Enter to stop it — instead an unseen paste is committed onto the (stationary) active frame while playback keeps running; Esc silently discards a paste they never saw.

**Why this is a gap.** Both rules are individually sensible — 'paste switches to CopyPaste first' (which happens to pause via _selectTool) and 'draft commands outrank playback on Enter/Esc' — but the already-on-CopyPaste path skips the tool switch and with it the only pause, creating a draft in a state (playback) where drafts are invisible and the shared chords change meaning without any visible cue.

**Repro.** Select the Copy & Paste tool, copy a selection, press Enter to start playback, then Ctrl+V, then Enter again. Playback keeps running, nothing visibly changed, but a paste was silently committed to the active frame (visible after pausing).

**Evidence.** editor_page.keyboard.dart:57-62 (pause only via the conditional _selectTool); editor_page.engine.dart:285-295 (playback composite hides the editing display's paste preview); commands.dart:64-96 (draft.commit/cancel precede playback.toggle/stop); default_bindings.dart:24-27 (Enter/Esc shared)

**Suggested behavior.** pasteFromKeyboard should pause playback unconditionally (matching duplicateFrame/deleteFrame/save in the same host), so the draft is created in the paused editing view where its preview and the commit-menu are visible.

### G-23 · Overscan view + playback: the animating canvas renders displaced by the gutter offset

**Severity:** medium · **Verdict:** confirmed · **Found by:** timeline-playback

**Disposition (2026-08-26).** Point fix. A rendering bug wearing a playback costume: position the canvas-sized composite at vOff while playing.

**Collision.** The overscan display view (storage-sized image, painted at a gutter-shifted origin) vs the playback presenter (canvas-sized composite, painted at the same origin)

**Current behavior.** While playing, _present decodes engine.compositeFrame(playFrame) at (_canvasW,_canvasH) (editor_page.engine.dart:286-295), but build() always positions the image at vImgOff = _imageOffset(vScale, vOff) (editor_page.canvas.dart:171-173, 257), which subtracts the gutter derived from _dispW/_dispH (editor_page.engine.dart:838-842). With Overscan on, display_size is storage = canvas + 2*gutter (session.rs:436-443, document.rs:326-330), so _dispW > _canvasW and vImgOff sits up-left of the canvas position. CanvasPainter draws the image at exactly that offset sized by its own dimensions (widgets/painters.dart:45-54). Net: press Play with Overscan enabled and the whole animation (checker backdrop included) jumps up-left by gutter*scale, the gutter area vanishes, and everything snaps back on pause. The grid overlay (drawn at vOff) stays put, so the artwork visibly slides out from under the grid.

**Why this is a gap.** The overscan view and the playback compositing path were built at different times; the playing branch of _present changes the image's SIZE but the offset math in build() was only ever parameterized for the editing display's size. No one specified what the overscan view means during playback (show the gutter? hide it but keep the canvas anchored?).

**Repro.** Any multi-frame doc -> menu -> View -> Overscan: on -> select Play tool -> Play. The canvas shifts toward the top-left by the gutter size (visible against the grid overlay / canvas backdrop); Pause snaps it back.

**Evidence.** editor_page.engine.dart:286-295 (playing branch decodes canvas-sized), editor_page.engine.dart:838-842 (_imageOffset uses _dispW/_dispH), editor_page.canvas.dart:171-173 + 257 (vImgOff applied unconditionally), crates/engine/src/session.rs:436-443 (display = storage under overscan), app/lib/editor/widgets/painters.dart:45-54

**Suggested behavior.** While _playing, position the canvas-sized composite at vOff (not vImgOff) - e.g. have _present record whether the published image is canvas- or storage-sized and pick the offset accordingly.

### G-24 · The 'structural ops auto-pause playback' rule is applied inconsistently across equivalent routes

**Severity:** medium · **Verdict:** confirmed · **Found by:** timeline-playback

**Disposition (2026-08-26).** Closed by ADR 0012. One rule at the _act funnel replaces the per-call-site convention.

**Collision.** Playback's auto-pause contract ('menus/sheets/structural actions pause the preview') vs the direct-action buttons and keyboard commands that bypass it

**Current behavior.** The SAME conceptual action pauses or doesn't depending on route: adding a frame via the film-roll long-press menu pauses (timeline.dart:155-157), but the strip's + button doesn't (timeline.dart:111-118: _act('AddFrame()') with no pause) and neither does keyboard frame.add (keyboard.dart:67-70) - while keyboard frame.duplicate and frame.delete DO pause (keyboard.dart:73-85). Add layer (+ button, timeline.dart:467-476, and keyboard layer.add/layer.up/down, keyboard.dart:88-98) never pauses; Undo/Redo/Onion tiles never pause (toolgrid.dart:50-72). Consequence of the un-paused AddFrame during playback: the engine appends a blank 100 ms frame and makes it ACTIVE (session.rs:2647-2659), so the loop suddenly includes a blank flash and the editing focus has silently moved to the new frame - while the strip menu route would have paused first and landed you calmly on the new frame.

**Why this is a gap.** Pause guards were added per-surface (sheets, menus, dialogs, tool switches, prev/next/goto) rather than per-operation, so bare-button and keyboard fast paths to the same operations never inherited the rule; the keyboard file even splits within one category (duplicate/delete pause, add doesn't).

**Repro.** Play a 2-frame animation, tap the film-roll's + button: playback keeps running, a blank frame starts flashing in the loop, and the active frame has changed under you. Long-press the empty strip area and pick 'Add animation frame' instead: playback pauses first.

**Evidence.** editor_page.timeline.dart:111-118 vs 155-157 (same AddFrame, only one pauses); editor_page.keyboard.dart:67-70 vs 73-85; editor_page.timeline.dart:467-476 (Add layer, no pause); editor_page.toolgrid.dart:50-72 (Undo/Redo/Onion, no pause); crates/engine/src/session.rs:2647-2659 (new blank frame becomes active and joins the play loop)

**Suggested behavior.** One rule: every structural mutation of the timeline/layer stack (add/duplicate/delete/reorder/undo/redo), from any route, auto-pauses playback - i.e. add the _playing pause to the + buttons, keyboard addFrame/addLayer/moveLayer, and _doToolAction Undo/Redo.

### G-25 · Keyboard frame.add ignores playback while frame.duplicate/delete pause it; several other keyboard mutations run un-paused too

**Severity:** low · **Verdict:** confirmed · **Found by:** keyboard-dialogs

**Disposition (2026-08-26).** Closed by ADR 0012. The keyboard catalog inherits the funnel rule; frame.add and layer.add pause like the rest.

**Collision.** The keyboard Frames/Layers/Edit Commands vs. running playback — inconsistent auto-pause within one catalog

**Current behavior.** In the same host file, duplicateFrame and deleteFrame pause playback first (editor_page.keyboard.dart:73-85) but addFrame does not (editor_page.keyboard.dart:66-70): Shift+N during playback appends a blank frame into the running animation with no pause, so the loop suddenly shows a blank flash and continues. addLayer (editor_page.keyboard.dart:87-91), moveLayer, selectAll, and deselect likewise mutate the document mid-playback without pausing, while every sheet/menu route and the frame-stepping Commands do pause. The on-screen film-strip '+' also doesn't pause (editor_page.timeline.dart:113-117), but its Duplicate equivalent lives only inside the frame sheet, whose opening pauses — the keyboard is the first surface to put paused and un-paused structural verbs side by side under adjacent shortcuts.

**Why this is a gap.** The pause-on-structural-change rule was applied per-Command by hand when the keyboard host was written; Duplicate and Delete got it (with comments), Add did not — no stated reason distinguishes them (all three change which frame is active or the frame list under the play head).

**Repro.** Play a multi-frame animation and press Shift+N: a blank frame is appended and playback keeps running through it. Press Shift+D instead: playback pauses first.

**Evidence.** editor_page.keyboard.dart:66-70 (addFrame, no pause) vs. 73-85 (duplicateFrame/deleteFrame pause); editor_page.keyboard.dart:87-98 (addLayer/moveLayer, no pause); editor_page.timeline.dart:113-117 (on-screen AddFrame also un-paused)

**Suggested behavior.** Pick one rule for the keyboard catalog — most consistent with the rest of the host: pause playback before any structural frame/layer mutation, including frame.add and layer.add.

### G-26 · Frame-navigation routes disagree about auto-pausing playback

**Severity:** low · **Verdict:** confirmed · **Found by:** tools-controls

**Disposition (2026-08-26).** Closed by ADR 0012. Film-roll taps and the + button pause first.

**Collision.** Running playback vs. the several routes to the same conceptual actions 'go to frame' and 'add frame': the Play tool's row-1 controls and keyboard steps auto-pause; film-roll taps and the + button do not.

**Current behavior.** The Play tool's prev/next/Go-to auto-pause as an explicit contract (engine.dart:998-1008, 1012-1014), and keyboard frame.prev/next inherit it via _stepFrame. But tapping a frame thumbnail during playback (timeline.dart:68-72) changes the active frame WITHOUT pausing: the canvas keeps animating (playback composites playFrame), so the tap appears to do nothing except move the blue border - and the row-1 'Frame X / N' label. Similarly the film-roll + button (timeline.dart:111-118) and keyboard frame.add (keyboard.dart:67-70) add a frame into a running animation without pausing, while the long-press 'Add animation frame' sheet (timeline.dart:155-157) and keyboard duplicate/delete (keyboard.dart:72-85) all pause first.

**Why this is a gap.** 'Opening any menu stops the animation preview (the Play tool's contract)' was applied menu-by-menu and control-by-control; direct taps on the film roll and the + button predate or escaped that sweep, so the same conceptual action pauses or not depending on which surface you use.

**Repro.** Select the Play tool, press Play, then tap frame thumbnails in the film roll: playback keeps running and the taps seem inert (only the border/label move); pressing the row-1 prev/next instead pauses immediately. Press the + button during playback: a frame is appended into the running animation without pausing, unlike the long-press menu's identical action.

**Evidence.** app/lib/editor/editor_page.engine.dart:998-1014; app/lib/editor/editor_page.timeline.dart:68-72, 111-118, 155-157, 196-199; app/lib/editor/editor_page.keyboard.dart:66-85

**Suggested behavior.** Apply the Play-tool contract uniformly: film-roll taps and the + button pause playback first (or at minimum the tap seeks playback to the tapped frame).

> Same inconsistency as the two findings above, enumerated from the tools-controls side; kept separate because the route lists differ.

### G-27 · Tapping a film-roll frame during playback silently retargets the active frame with zero visible feedback

**Severity:** low · **Verdict:** confirmed · **Found by:** timeline-playback

**Disposition (2026-08-26).** Closed by ADR 0012 with ADR 0013. A tap is explicit activation: playback pauses, then the tapped frame becomes the Active target.

**Collision.** The film-roll tile tap (SetActiveFrame, no pause) vs the Play tool's prev/next/Go-to (which pause first) - two routes for 'go to frame' during playback

**Current behavior.** A film-roll tile tap runs _act('SetActiveFrame(i)') with no pause (editor_page.timeline.dart:68-72). During playback the presenter composites the PLAY frame (editor_page.engine.dart:286-295), so the canvas keeps animating unchanged; only the tile border moves. The tap nonetheless changes real state: pause will land on the tapped frame, the layer strip switches to its stack, the move-group is cleared, and the NEXT Play will start from it (session.rs:3426-3431 seeds the clock from active_frame). The Play tool's prev/next/Go-to controls for the same conceptual action pause first and scroll the strip (editor_page.engine.dart:1000-1008, 1012-1039), giving immediate visible confirmation.

**Why this is a gap.** The strip tap predates the Play-tool controls' 'auto-pause is the Play tool's contract' rule; nobody decided whether a strip tap during playback should pause-and-show (like prev/next), be ignored, or silently retarget as it does now.

**Repro.** Play an animation, tap frame 3 in the film roll: the canvas keeps animating as if nothing happened, but pausing later drops you on frame 3 (and the layer strip already switched).

**Evidence.** editor_page.timeline.dart:68-72; editor_page.engine.dart:286-295 (playing presenter ignores activeFrame), 1000-1008 (_stepFrame pauses), 1012-1014 (_gotoFrameDialog pauses); crates/engine/src/session.rs:3426-3431 (play starts from active_frame), 2724-2729 (set_active_frame doesn't touch the play clock)

**Suggested behavior.** Match the Play tool's contract: a film-roll tap during playback pauses first, then activates the tapped frame (giving the immediate visual jump the user expects).

### G-28 · Onion skin toggled during playback lights the tile but changes nothing until pause

**Severity:** low · **Verdict:** confirmed · **Found by:** timeline-playback

**Disposition (2026-08-26).** Closed by ADR 0012. Toggling onion skin is an editing intent and pauses playback.

**Collision.** The Onion action tile / O shortcut (a display-mode toggle, not pause-gated) vs the playback presenter, whose composite path has no onion parameter

**Current behavior.** The Onion tile and its keyboard command flip _onion and _redraw() with no _playing pause (editor_page.toolgrid.dart:68-71, keyboard/commands.dart:149). While playing, _present uses engine.compositeFrame(playFrame) - onion is only passed to engine.display(onion: _onion, ...) on the non-playing branch (editor_page.engine.dart:286-295). So during playback the tile lights amber (a full-tree setState via _doToolAction -> _redraw), the animation is visually unchanged, and the onion ghosting only materializes whenever playback later pauses - an effect detached in time from its cause.

**Why this is a gap.** Onion was specified as an editing-view aid and playback as a clean preview, but the toggle was left reachable during playback without deciding whether it should pause (like tool selection does), be disabled, or apply; the current half-state (state flips, visual doesn't) is the accidental residue.

**Repro.** Play an animation, tap the Onion tile: it lights amber, nothing on the canvas changes. Pause: the onion ghosts suddenly appear.

**Evidence.** editor_page.toolgrid.dart:39, 68-71 (toggle + amber active state, no pause); editor_page.engine.dart:286-295 (onion only on the display branch); keyboard/commands.dart:143-150 (toggleOnion always enabled)

**Suggested behavior.** Have the Onion toggle auto-pause playback (consistent with tool selection and the 'editing view' nature of onion skin), or grey the tile out while _playing.

### G-29 · The color picker dialog does not auto-pause playback, unlike every other palette surface

**Severity:** low · **Verdict:** confirmed · **Found by:** palette-color

**Disposition (2026-08-26).** Closed by ADR 0012. The color picker pauses playback like every other palette surface.

**Collision.** The menus/sheets-auto-pause-playback convention x the primary/gradient swatch tap opening a dialog instead of a sheet

**Current behavior.** _addColorMenu and _paletteSwatchMenu both start with `if (_playing) _pause()` (editor_page.controls.dart:906, 941), as does _openPalettePage (927). But tapping the primary swatch (controls.dart:821-822) or a gradient stop swatch (432-438) calls _pickColor directly with no pause, so the ColorPickerDialog opens over a running animation. Because a dialog route is not opaque, the play ticker is NOT muted (the muting relies on opaque routes — editor_page.engine.dart:908-913 comment), so AdvanceClock sends and composite decodes continue behind the barrier for as long as the dialog is up. Playback is reachable here via the PlayPause tool row or the Space shortcut while any tool is active.

**Why this is a gap.** The menu-autopause feature was specified for 'menus/sheets'; the picker is a dialog launched from the same strip, and whether it counts was never decided — so two taps an inch apart on row-2 (swatch tap-to-pick vs swatch long-press menu) behave differently with respect to playback.

**Repro.** Multi-frame document, start playback (Space or the Play button), tap the primary color swatch. The picker opens while the animation keeps playing (and decoding) behind the dialog barrier; long-pressing the strip instead pauses it.

**Evidence.** app/lib/editor/editor_page.controls.dart:821-822 and 432-438 (no pause) vs 906, 927, 941 (pause); app/lib/editor/editor_page.fileio.dart:733-736 (_pickColor has no pause); app/lib/editor/editor_page.engine.dart:908-913 (ticker muted only by opaque routes)

**Suggested behavior.** Pause playback in _pickColor (or at the primary/gradient swatch call sites), matching the strip's sheet behavior.

## Sheets, layers, and the move-group

The stay-open sheets let structural operations chain on arbitrary (non-active) items, but the engine's structural verbs still unconditionally re-activate their result, and the shell's move-group is a set of indices into the active frame's stack. The combination produces stale badges, silent retargeting, and undo-history floods.

### G-30 · Opacity slider drag records one undo step per drag tick, evicting the frame's undo history

**Severity:** high · **Verdict:** confirmed · **Found by:** sheets-layers

**Disposition (2026-08-26).** Point fix, engine-additive. Needs a non-recording opacity preview verb plus one SetLayerOpacity undo step at drag end. The last high-severity finding not closed by a policy.

**Collision.** Continuous Slider.onChanged (fires per pointer move) + the engine's SetLayerOpacity being a full undoable edit per call (edit_frame pushes a Record each time) + the 128-record per-frame history cap that drops the oldest records

**Current behavior.** The layer sheet's opacity slider sends `_send('SetLayerOpacity($cur, ${v.round()})')` on every onChanged tick. Engine-side, set_layer_opacity wraps edit_frame, which clones the frame and pushes one history Record per call with no coalescing. A slow 2-3 s drag emits ~100+ records; past PER_FRAME_CAP (128) the oldest content edits for that frame are silently dropped. Afterwards Undo steps back through every intermediate opacity value, and the user's earlier strokes on that frame may no longer be undoable at all. The typed-entry path right next to it (`_editSliderValue` -> one `_act('SetLayerOpacity...')`) records exactly one step for the same conceptual action, and the sibling blend control was explicitly engineered to avoid this (PreviewLayerBlend = no undo record, one SetLayerBlend commit on close) - the opacity slider never got that treatment.

**Why this is a gap.** The blend picker's design comments (sheets.dart:474-478, session.rs preview_layer_blend doc) show the team specified 'continuous preview must not spam undo' for blend, but nobody specified what a continuous opacity drag should be as an undo unit; the slider just reuses the discrete verb per tick.

**Repro.** Open the layer sheet (long-press a layer tile), drag the Opacity slider slowly end to end for a few seconds, close the sheet, press Undo repeatedly: it crawls through intermediate opacities, and edits made before the drag on that frame have been evicted from history.

**Evidence.** app/lib/editor/editor_page.sheets.dart:346-360 (onChanged sends per tick; onChangeEnd only refreshes), 366-370 (typed path is one _act); crates/engine/src/session.rs:3229-3233 (set_layer_opacity -> edit_frame), 1232-1250 (edit_frame records per call); crates/engine/src/history.rs:15 (PER_FRAME_CAP=128), 192 (oldest dropped past cap); contrast crates/engine/src/session.rs:3245-3260 (blend preview/commit design)

**Suggested behavior.** Mirror the blend picker: preview opacity via a non-recording verb (or defer the engine write to onChangeEnd) and commit one SetLayerOpacity undo step when the drag ends, matching the typed-entry granularity.

### G-31 · Frame sheet 'Move left/right' on a non-active frame activates it and leaves the move-group pointing into the wrong frame's layer stack

**Severity:** medium · **Verdict:** confirmed · **Found by:** sheets-layers, timeline-playback

**Disposition (2026-08-26).** Closed by ADR 0013 (explicit activation). Reordering another frame does not activate it, and the move-group is held by layer id.

**Collision.** The stay-open frame sheet targeting a non-active frame (`cur` != activeFrame) + engine reorder_frame's unconditional `active_frame = to` + the layer move-group, which is a set of indices into the active frame's stack

**Current behavior.** reorder_frame is the only structural frame verb that neither resets nor sanitizes layer_sel (duplicate_frame, add_frame_at, remove_frame, set_active_frame all do), and it unconditionally makes the moved frame active. The shell mirrors the omission: the sheet's Move left/right buttons are the only structural actions in either sheet that don't call _clearLayerGroup(). So with layers grouped on frame A, long-pressing frame B and tapping Move left (1) silently switches the canvas/active frame to B and (2) keeps both the engine's layer_sel and the shell's _selLayers holding frame-A indices, now decorating and move-dragging frame B's layers at those indices.

**Why this is a gap.** Every sibling operation carries an explicit 'the move-group indexed the previous frame's stack' comment and a reset; reorder_frame simply lacks the line, and the shell's frame sheet matches the omission - a missed case, not a decision (the engine's own doc comment at the move-group section says every active-frame change must resync).

**Repro.** On frame 1 (active), open the layer sheet and add layers 2 and 3 to the Move group. Long-press frame 3's tile, tap 'Move left', close the sheet: the canvas is now showing frame 3, its layer strip shows amber badges at indices 2-3, and a Move-tool drag moves those layers of frame 3.

**Evidence.** app/lib/editor/editor_page.sheets.dart:563-575 (no _clearLayerGroup, unlike Duplicate at 580 / New at 590 / Delete at 601); crates/engine/src/session.rs:2712-2723 (reorder_frame: active_frame = to, no reset_layer_sel) vs 2658, 2674-2675, 2691, 2704-2710, 2727-2730 (all siblings reset/sanitize)

**Suggested behavior.** reorder_frame should reset_layer_sel when the reorder changes which frame is active (and arguably keep the previously active frame active when reordering another frame); the shell's Move buttons should _clearLayerGroup() when cur != activeFrame, matching the sheet's other structural actions.

> Also found independently by the timeline-playback reviewer as “Frame sheet's Move left/right silently changes the active frame and leaves the move-group pointing into the wrong frame's layer stack” — merged here.

### G-32 · Deleting a later frame from the frame sheet clears the move-group badges but the engine keeps the group - the next Move drag moves un-badged layers

**Severity:** medium · **Verdict:** confirmed · **Found by:** sheets-layers

**Disposition (2026-08-26).** Closed by ADR 0013. The move-group is an id set, so a deleted frame cannot leave it pointing into the wrong stack.

**Collision.** The frame sheet's unconditional shell-side _clearLayerGroup() on Delete + the engine's smarter id-guarded policy (keep/sanitize layer_sel when the active frame survived the removal) + the canvas Move drag reading the engine's layer_sel directly without a resync

**Current behavior.** remove_frame only resets layer_sel when the active frame's id changed; deleting a frame AFTER the active one leaves the engine group intact (sanitized). The sheet's Delete button, however, always calls _clearLayerGroup(), wiping the amber badges from the UI. The canvas Move drag path sends MoveDraftBegin() without pushing _syncLayerSel first, so the engine lifts its still-populated layer_sel: multiple layers move together while the layer strip shows no group at all. (The nudge buttons do call _syncLayerSel first, so nudge and drag disagree too.)

**Why this is a gap.** Shell and engine each implemented a defensible policy for 'what happens to the group on frame delete' but nobody specified they must match; for cur > activeFrame they diverge, and the divergence is invisible until the next Move gesture.

**Repro.** On frame 1 of 3, group layers 1+2 via the layer sheet chips. Long-press frame 3, Delete frame, close the sheet: no amber badges remain, but a Move-tool drag on the canvas still moves layers 1 and 2 together.

**Evidence.** app/lib/editor/editor_page.sheets.dart:599-605 (unconditional _clearLayerGroup before RemoveFrame); crates/engine/src/session.rs:2694-2711 (id-guarded reset vs sanitize); app/lib/editor/editor_page.canvas.dart:563-571 (MoveDraftBegin sent with no _syncLayerSel); app/lib/editor/editor_page.timeline.dart:405-419 (_nudgeMove DOES _syncLayerSel first)

**Suggested behavior.** Either mirror the engine's keep-when-active-survives policy in the shell (clear only when cur <= activeFrame), or have the shell push its cleared state to the engine (send the collapse) whenever it clears locally.

### G-33 · A single-member 'Move group' shows the amber badge but the Move tool moves the active layer instead

**Severity:** medium · **Verdict:** confirmed · **Found by:** sheets-layers

**Disposition (2026-08-26).** Dissolved by ADR 0013. With the move-group held as an id set, a one-member group is simply real.

**Collision.** The layer sheet's per-layer Move-group chip (which can produce a group of exactly one, on a non-active layer) + _syncLayerSel's rule that only groups of 2+ are pushed as SetMoveGroup (a group of <=1 re-sends SetActiveLayer of the CURRENT active layer)

**Current behavior.** Checking 'Move group' on a retargeted/long-pressed non-active layer puts that layer in _selLayers (amber border + open_with badge appear on it), but _syncLayerSel sees length==1 and sends SetActiveLayer(_activeLayerIndex()) - referencing the active layer, not the badged one - which sets the engine's layer_sel to [active]. A Move-tool drag or nudge then moves the active layer while the amber-badged layer stays put. The same lying state is reachable by unchecking a 3-layer group down to one remaining member.

**Why this is a gap.** Move-group semantics were specified for 2+ members ('layers that translate together'); the 1-member state was left to fall through to 'just the active layer', but the chip and badges render it as if it were a real group on that specific layer.

**Repro.** With layer 1 active, long-press layer 3's tile, check 'Move group', close the sheet. Layer 3 shows the amber move-group badge; drag with the Move tool: layer 1 moves, layer 3 does not.

**Evidence.** app/lib/editor/editor_page.sheets.dart:323-340 (chip adds cur, calls _syncLayerSel), app/lib/editor/editor_page.timeline.dart:393-401 (length<=1 branch sends SetActiveLayer(_activeLayerIndex()), ignoring the member), crates/engine/src/session.rs:2861-2866 (set_active_layer collapses layer_sel to [i]); badges: sheets.dart:180/192, timeline.dart:544-554

**Suggested behavior.** Either make a 1-member group real (send SetMoveGroup for any non-empty set - the engine supports it without changing the active layer), or refuse the state (checking the chip on a lone layer makes it active / shows no badge).

### G-34 · Structural actions on a retargeted layer sheet silently steal the active drawing target, contradicting the mini-stack's no-side-effect contract

**Severity:** medium · **Verdict:** confirmed · **Found by:** sheets-layers

**Disposition (2026-08-26).** Closed by ADR 0013. Structural actions preserve the Active target by identity; the sheet is a remote control.

**Collision.** The mini-stack's tap-to-retarget design ('the engine's active layer stays put, so no side effect survives the sheet') + every structural engine verb unconditionally activating its result (reorder_layer: active_layer = to; duplicate_layer/add_layer_at: the copy/new layer; merge_down: i-1; Copy-to-all-frames: an explicit never-restored SetActiveLayer(cur))

**Current behavior.** Tapping a mini-stack tile only retargets the sheet, as promised. But then pressing Up/Down/Duplicate/New/Merge on that retargeted layer changes the engine's active layer to the acted-on layer's result - even though the user never 'selected' it. E.g. active layer 0, sheet retargeted to layer 3, tap 'Up': layer 3 moves to 4 AND becomes the active layer; after closing the sheet the next stroke lands on former-layer-3 instead of layer 0. 'Copy to all frames' does it explicitly (SetActiveLayer(cur)) and pops, leaving the user's brush retargeted with no visual cue beyond the strip border. The same applies frame-side: Duplicate/New/Move on a non-active frame in the frame sheet switches the canvas to that frame under the sheet.

**Why this is a gap.** Activate-the-result is sensible when the sheet targets the active layer (the pre-retarget world); the mini-stack retarget feature (5175ccd) added a way to act on non-active layers but never specified whether the active target should follow, and the code comment promises the opposite of what the arrange/create buttons do.

**Repro.** Active layer 0; long-press layer 0's tile, tap mini-stack tile 3 (active stays 0), tap 'Up' twice, close the sheet, draw: the stroke lands on the reordered layer (now active), not layer 0.

**Evidence.** app/lib/editor/editor_page.sheets.dart:181-184 (retarget promise), 402-415 (Up/Down), 416-424 (Merge), 428-445 (Duplicate/New), 448-457 (SetActiveLayer(cur) never restored); crates/engine/src/session.rs:2848-2859 (reorder_layer sets active_layer=to unconditionally), 2796-2811, 2821-2846; frame side: sheets.dart:579-594 + session.rs:2661-2692

**Suggested behavior.** Decide and apply one rule: either arranging/duplicating from a retargeted sheet preserves the pre-existing active layer (engine restores it when the acted index differs), or retargeting the sheet is defined to also set the active layer (making the strip's blue border and the sheet agree).

### G-35 · Deleting an item below/before the active one shifts the active frame/layer onto the next item

**Severity:** medium · **Verdict:** confirmed · **Found by:** sheets-layers

**Disposition (2026-08-26).** Closed by ADR 0013. Identity, not index: removing an item below the active one leaves the same frame or layer active.

**Collision.** The sheets' new ability to delete non-active frames/layers (delete-delete chains on arbitrary indices) + the engine's index-preserving active clamp (`active = active.min(len-1)`), which never decrements when the removed index is below the active one

**Current behavior.** remove_frame keeps the active INDEX, so deleting frame 2 while working on frame 5 makes the active slot point at former frame 6 - the canvas under the sheet silently switches to a different frame's content (the engine's id check notices and resets the move-group, confirming the frame identity changed). remove_layer has the identical drift: with layer 3 active, deleting layer 1 from a retargeted sheet makes former layer 4 the drawing target. Only the sheets can reach this (keyboard and strip delete only the active item).

**Why this is a gap.** The clamp was written for deleting the active/last item; deleting an earlier item became reachable when the sheets gained arbitrary-index delete, and 'which frame/layer stays active' for that case was never specified - most editors keep the same identity active by decrementing the index.

**Repro.** Make frame 5 active, long-press frame 2's tile, Delete frame, close the sheet: the canvas now shows what was frame 6. Layer variant: layer 3 active, layer sheet retargeted to layer 1, Delete layer, draw: the stroke lands on what was layer 4.

**Evidence.** crates/engine/src/session.rs:2694-2701 (remove_frame: `active_frame.min(len-1)`, no decrement for i < active; the id-changed branch at 2705-2710 fires exactly in this case), 2783-2794 (remove_layer: same pattern); reachable via app/lib/editor/editor_page.sheets.dart:599-605 (frame Delete) and 461-468 (layer Delete on a retargeted cur)

**Suggested behavior.** When removing index i < active, decrement the stored active index so the same frame/layer identity stays active (and drop the then-unneeded group reset for that case).

### G-36 · 'Edit duration...' permanently switches the active frame even when the dialog is canceled

**Severity:** low · **Verdict:** confirmed · **Found by:** sheets-layers

**Disposition (2026-08-26).** Closed by ADR 0013. Edit duration acts on the named frame without activating it.

**Collision.** The frame sheet targeting a non-active frame + the duration dialog operating only on the ACTIVE frame (so the sheet force-switches before opening it) + dialog cancel having no undo of that switch (SetActiveFrame is not an undoable edit)

**Current behavior.** Tapping 'Edit duration...' on frame 7's sheet while working on frame 2 pops the sheet, sends SetActiveFrame(7) (clearing the move-group), and opens the dialog. Pressing Cancel leaves the user on frame 7 with their group gone - a state change from an action that changed nothing. No other read-modify dialog in the editor moves the working context on cancel.

**Why this is a gap.** _editDuration predates the stay-open/arbitrary-index sheet and only knows the active frame; the sheet bridges the mismatch by switching frames rather than by parameterizing the dialog, and the cancel path was never considered.

**Repro.** Work on frame 2 with a move-group set; long-press frame 7, tap 'Edit duration...', press Cancel: you are now on frame 7 and the group is cleared.

**Evidence.** app/lib/editor/editor_page.sheets.dart:556-561 (pop, conditional _clearLayerGroup, SetActiveFrame(cur), then _editDuration); app/lib/editor/editor_page.fileio.dart:655-661 (_editDuration reads engine.activeFrame only); crates/engine/src/session.rs:2727-2732 (set_active_frame: direct mutation + group reset, no undo record)

**Suggested behavior.** Parameterize _editDuration with the frame index (SetFrameDuration already takes one) so no active-frame switch is needed, or restore the previous active frame on cancel.

## Persistence and document identity

The replace-the-canvas flows (gallery open, external Open, Club edit, startup restore, pillar switch) sequence identity adoption, release, and async load in orders that were never specified against failure or concurrent editing.

### G-37 · Opening a corrupt library drawing adopts its identity anyway and autosaves foreign content into it

**Severity:** medium · **Verdict:** confirmed · **Found by:** persistence-replay

**Disposition (2026-08-26).** Closed by ADR 0014 (load-then-adopt). A failed load never adopts the target identity; the outgoing drawing keeps its own.

**Collision.** The gallery-open flow's release-then-load sequence vs. a load failure, with the always-on autosave and journal attached to the new identity

**Current behavior.** _openExistingDrawing releases the outgoing drawing (keep or discard), then calls _loadDrawingIntoEngine(id); on failure it toasts 'Could not open that drawing' but STILL calls _adopt(id, meta.title, ...) unconditionally (editor_page.persistence.dart:297-301). The engine still holds the previous drawing's content, so: the title bar switches to the target's name while the canvas shows the old drawing; the autosave controller starts serializing the old content under the target's id, so the first user action overwrites the target's doc.mkpx (demoting its possibly-recoverable primary to .bak, destroyed on the second write); and the journal attach re-anchors the TARGET's journal with a chapter base of the OTHER drawing's pixels (attachResume gets _resumeDocBytes == null → reanchorNeeded → cutChapter(engine.saveCompact()) at editor_page.replay.dart:40-49). If the user chose 'Discard' for the outgoing drawing, its 'discarded' content is resurrected under the target's identity.

**Why this is a gap.** The sibling path _open() explicitly refuses to adopt on a failed load ('only adopt a new drawing if the load succeeds, so a corrupt file leaves the current drawing intact', editor_page.fileio.dart:71-74, 88-96); _openExistingDrawing has the same failure mode but no failure branch — the adopt is unconditional. Two flows for the same conceptual action behave differently, and the corrupt-target case was clearly never specified.

**Repro.** Corrupt a library drawing's doc.mkpx and doc.mkpx.bak on disk (or let storage damage them). In the editor, open ☰ → My Drawings and tap that drawing; choose Keep for the current one. The toast says it could not be opened, yet the header now shows the corrupt drawing's title over the previous drawing's canvas, and the next stroke writes the previous drawing's content into the corrupt drawing's folder.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.persistence.dart:292-306 (unconditional _adopt at 301); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.replay.dart:37-50 (re-anchor on engine content); contrast C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.fileio.dart:71-96

**Verifier correction.** One mechanism detail is off: on failure _attachJournal's resume branch does docBytes ??= await store.readDoc(id) WITHOUT a validator (editor_page.replay.dart:42), so the fnv can be non-null and the outcome may be 'continued' rather than reanchorNeeded when a marker matches the corrupt on-disk bytes. Either outcome still leaves the target's journal recording on top of the other drawing's content, so the finding's substance stands.

**Suggested behavior.** Mirror _open(): on load failure, do not adopt — re-attach the journal/autosave to the still-current drawing (resume mode) and keep its identity, leaving the corrupt target untouched.

### G-38 · Discard-then-load-failure resurrects the discarded drawing — differently on each path

**Severity:** medium · **Verdict:** confirmed · **Found by:** persistence-replay

**Disposition (2026-08-26).** Closed by ADR 0014. The discard is deferred until the incoming load succeeds, so there is nothing to resurrect.

**Collision.** The 'Discard it — this cannot be undone' confirmation vs. a subsequent load failure in the three replace-the-canvas flows (external Open, Club edit, gallery open)

**Current behavior.** All three flows release (and on Discard, DELETE) the current drawing BEFORE attempting the incoming load. When the load then fails, each path invents a different recovery: (1) _open() re-attaches journal+autosave under the SAME deleted id (editor_page.fileio.dart:88-96) — the next write recreates the folder, so the drawing the user just confirmed discarding silently reappears in My Drawings, with its replay history replaced by a single re-anchor snapshot; (2) _consumeClubEdit() runs _createFreshDrawing(title: req.sourceTitle, ...) even when ok == false (editor_page.fileio.dart:356-357), creating a NEW library drawing named after the Club post but containing the old canvas (mkpx branch) or a blank canvas (render branch) — and then sets _clubSource unconditionally (365-374), so the publish flow will offer 'Replace' of that Club post against content that is not derived from it; (3) _openExistingDrawing writes the old content into the target's folder (previous finding). Three behaviors for one situation, none of which honors the 'cannot be undone' promise or, in case 2, the provenance/Replace contract.

**Why this is a gap.** Release-before-load is required so the replace-ask can save/discard the real outgoing document, but the failure leg of each load was patched independently (the _open comment even documents its branch as a special case) — the discarded-but-load-failed state was never given one specified outcome, and _consumeClubEdit's _clubSource assignment sits after the failure toast with no ok guard.

**Repro.** Draw something. ☰ → Open, pick a non-.mkpx file renamed to .mkpx, choose 'Discard it' and confirm. The load fails — and the 'permanently discarded' drawing quietly reappears in My Drawings on the next stroke. Variant: on a Club post with a layers file made by a newer app version, tap Edit, discard the current drawing; a new drawing named after the post is created holding your old canvas, and posting it offers 'Replace' of that post.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.fileio.dart:75, 88-96 (open re-attach into deleted folder), 318-377 (club edit: _createFreshDrawing at 357 and unconditional _clubSource at 365-374); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.persistence.dart:197-213 (delete on discard), 220-275 (the two-step Discard confirmation)

**Verifier correction.** The _open() leg is partially deliberate: the comment at fileio.dart:88-92 explicitly names the discard-branch/deleted-folder case and chooses to re-attach and re-anchor there, so the resurrection on that path is a foreseen consequence rather than a blind spot. The genuinely unspecified parts are _consumeClubEdit's unconditional _createFreshDrawing + _clubSource assignment and _openExistingDrawing's unconditional adopt — and the inconsistency across the three paths itself.

**Suggested behavior.** Defer the discard/delete until the incoming load has succeeded (load into the engine first, release after), or specify one uniform failure outcome (e.g. always keep the outgoing drawing and restore its identity, never set _clubSource on failure).

### G-39 · Startup restore clobbers strokes drawn during the async load, leaving unjournaled pixels

**Severity:** medium · **Verdict:** confirmed · **Found by:** persistence-replay

**Disposition (2026-08-26).** Closed by ADR 0014. Canvas input is gated until restore resolves; the boot canvas accepts no stroke it cannot journal.

**Collision.** The immediately-interactive boot canvas vs. the silent async restore of the last drawing (and the not-yet-attached journal)

**Current behavior.** initState creates a live 64×64 engine and the canvas accepts input at once (editor_page.dart:559-577), while _initPersistence resolves the support dir, prefs, keyboard bindings, and then runs engine.load(bytes) inside readDoc's validator (editor_page.persistence.dart:35, 169-184) — replacing the document at an arbitrary moment, including mid-stroke. Strokes drawn before the load are silently discarded; a stroke IN PROGRESS is split: its PointerMove/PointerUp tail lands on the restored drawing (clamped to its size), painting a stray line onto the user's saved artwork, which the next autosave persists. Because _journal is null until _adopt's attach completes, those sends are never recorded — attachResume reconciles against the FNV of the bytes as loaded (stashed pre-mutation, editor_page.persistence.dart:182), returns 'continued', and the stray pixels exist in the document but not in the journal, so the drawing's replay diverges from the artwork permanently (no re-anchor ever heals it). The freshBlank path explicitly handles 'the user outran persistence' (editor_page.replay.dart:19-21, 60-63); the restore path does not.

**Why this is a gap.** The restore was designed to be silent and the boot canvas to be instantly usable; each is sensible alone, but nothing specifies what happens to input delivered in the gap. The fresh-drawing path's outran-persistence fallback shows the gap was seen for one branch and not the other.

**Repro.** On a slow device (or with a large last-open drawing), open the app and immediately start a drag on the canvas. Mid-drag the restored drawing pops in; the remainder of the drag paints a line onto it. The line is autosaved into the drawing but absent from ☰ → Watch replay.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.dart:559-577 (live engine before restore); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.persistence.dart:17-47, 169-184; C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.replay.dart:17-25, 51-64 (the fresh-path fallback that resume lacks); journal null-tap at editor_page.engine.dart:230

**Suggested behavior.** Gate canvas input (or buffer/discard the whole gesture) until _initPersistence resolves, or treat pre-restore edits like the freshBlank fallback: detect a dirtied boot canvas and fork it into its own drawing instead of loading over it.

### G-40 · Post-to-Club builds the publish draft from two different document states

**Severity:** medium · **Verdict:** confirmed · **Found by:** persistence-replay

**Disposition (2026-08-26).** Point fix. Assemble the entire PublishDraft at the same instant as engine.save(), before the first await.

**Collision.** The non-modal WebP encode of Post to Club vs. continued editing (or a drawing switch) in the fully-interactive editor during the encode

**Current behavior.** _postToClub snapshots the document synchronously (docBytes = engine.save(), and w/h/frameCount) and then awaits Engine.encodeInBackground behind only a 'Rendering WebP…' toast — no modal, the editor stays fully interactive (editor_page.fileio.dart:251-257). After the await, the PublishDraft is assembled from the LIVE state: mkpxBytes = engine.saveCompactWithMeta(...) (line 291), totalDurationMs from engine.stateJson() (271-277), source: _clubSource (286) and provenance: _provenance (287). Any edit made during the encode (seconds for a many-frame animation — that is why it was moved off-thread) makes the attached layers file, duration metadata, and provenance describe a NEWER document than the WebP render being published. If the user opens ☰ → My Drawings and switches drawings during the encode, the publish page opens with drawing A's render but drawing B's .mkpx attachment, title context, provenance, and Replace/remix source.

**Why this is a gap.** The encode was deliberately moved off the UI thread to avoid jank [audit F-12], and the draft fields were each individually correct — but nobody specified what the draft means when the document changes between the snapshot and the draft assembly. Every other long export (_encodeWithProgress, _runWithImportSpinner) uses a modal precisely to 'keep the document from changing under' the operation; _postToClub is the one long encode without that guard.

**Repro.** Make a large multi-frame animation. Tap ☰ → Post to Club. While 'Rendering WebP…' is showing, draw a big stroke (or open My Drawings and switch to another drawing). When the publish page opens, tick 'Share the layers (.mkpx) file' and publish: the post's image is the pre-edit render while the attached layers file contains the post-encode document (or an entirely different drawing).

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.fileio.dart:251-296 (snapshot at 253-257, live reads at 271, 286-287, 291); contrast the modal guard rationale at editor_page.fileio.dart:180-183 and the progress dialog used by _encodeWithProgress at 428-441

**Suggested behavior.** Assemble the ENTIRE PublishDraft (mkpxBytes, durations, source, provenance) synchronously at the same instant as engine.save(), before the first await — or run the encode behind the same modal progress dialog the other exports use.

### G-41 · Fast pillar round-trip races the old editor's teardown writes against the new editor's restore

**Severity:** medium · **Verdict:** plausible · **Found by:** persistence-replay

**Disposition (2026-08-26).** Closed by ADR 0014. One writer per drawing folder, so teardown and the next mount cannot interleave.

**Collision.** The dispose-time fire-and-forget autosave/journal writes of the unmounting editor vs. the freshly-mounted editor's _initPersistence reading and reconciling the same files

**Current behavior.** Nothing serializes the old instance's async teardown against the new instance's startup: dispose starts flushNow's write and detachSoon's journal drain without awaiting (editor_page.dart:625-631), and the new mount immediately runs _initPersistence → readDoc(curId) (editor_page.persistence.dart:34-35) and attachResume, which may truncate/append the SAME journal file (journal_recorder.dart:106-163) the old drain is appending to. writeDoc's non-atomic window (rename doc→bak, then tmp→doc, drawing_store.dart:51-54) means the new reader can find doc.mkpx absent and silently fall back to doc.mkpx.bak — the PREVIOUS save — restoring the drawing without the user's last edits; the new session's first autosave then demotes the newest bytes to .bak and the second write destroys them. On Windows the new reader holding the file open can instead make the old flush's rename throw, which is swallowed (the unmounted _onAutosaveError only debugPrints), silently dropping the final save. Concurrent journal append + truncate can interleave into a malformed line the scanner then treats as a foreign tail.

**Why this is a gap.** The app shell's mount-one-pillar-at-a-time design plus the crash-safe on-disk handoff each work alone; the handoff was specified for crash/kill (where the old process is gone) but not for the live-in-process case where two AutosaveController/JournalRecorder instances briefly own the same folder. The window is real for large documents, whose multi-MB final flush takes long enough to overlap the remount's reads.

**Repro.** With a large (multi-MB, many-frame) drawing, draw a stroke and immediately switch to Club and back (Contribute). If the remount's readDoc lands inside the old flush's rename window, the editor reopens showing the drawing WITHOUT the stroke; drawing anything then permanently discards the newer save.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.dart:616-645 (un-awaited teardown); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.persistence.dart:17-47 (immediate remount restore); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/persistence/drawing_store.dart:43-55, 86-100 (rename window and silent .bak fallback); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/replay/journal_recorder.dart:106-163, 303-330 (truncate vs append on the same file)

**Suggested behavior.** Hand the in-flight teardown future to the next mount (e.g. a static per-drawing write lock or a completion future the new _initPersistence awaits before readDoc/attachResume), so exactly one instance touches a drawing's folder at a time.

### G-42 · Editor dispose defeats the journal's write-ahead marker, so every session end re-anchors

**Severity:** low · **Verdict:** confirmed · **Found by:** persistence-replay

**Disposition (2026-08-26).** Point fix. Write the marker before teardown - stash the recorder for the in-flight preWrite, or detach after the flush drains.

**Collision.** The synchronous dispose teardown (pillar switch to Club) vs. the autosave's async write-ahead journal marker

**Current behavior.** dispose() calls _autosave?.flushNow() un-awaited, then _journal?.detachSoon() (which sets _attached = false immediately) and _journal = null, all synchronously (editor_page.dart:616-645). The flush's drain reaches preWrite only after an await ('await _journalAttaching', editor_page.persistence.dart:94-97), i.e. on a later microtask — by then _journal is null AND the recorder is detached, and markerBeforeSave no-ops on !_attached (journal_recorder.dart:264-268). So whenever there are edits newer than the last periodic autosave, the final document write lands WITHOUT its journal marker, despite the dispose comment claiming 'the flushNow above already routed the final marker through preWrite'. On the next mount, attachResume finds no marker matching the doc's FNV → reanchorNeeded → a full-document chapter base is cut (editor_page.replay.dart:44-49). Net effect: every pillar switch (or app close) after recent edits appends a redundant document-sized chapter-XXXX.mkpx and the journal never 'continues' cleanly across sessions, only across in-session switches.

**Why this is a gap.** The write-ahead ordering was specified for the awaited paths (_releaseOutgoing awaits flushNow with the journal still attached, editor_page.persistence.dart:197-206) and for lifecycle flushes (journal untouched); dispose combined a fire-and-forget flush with an immediate detach and null-out, and the interleaving across the first await was never accounted for — the in-code comment asserts the opposite of what executes.

**Repro.** Draw a stroke, then within 5 seconds switch to the Club pillar and back. Inspect the drawing's folder: the journal has no marker for the current doc.mkpx and a new reason=reanchor chapter (plus a full chapter base file) appears on every such round trip.

**Evidence.** C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.dart:625-631 (flushNow, stop, detachSoon, _journal = null with the incorrect comment); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/editor_page.persistence.dart:94-97 (preWrite reads _journal at execution time); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/persistence/autosave_controller.dart:122-135 (drain awaits preWrite before writeDoc); C:/Users/fab/F/Estudo/Tecnologia/makapix-app/app/lib/editor/replay/journal_recorder.dart:264-268, 343-346

**Suggested behavior.** Write the marker before tearing down: e.g. have dispose stash the journal reference for the in-flight preWrite (capture the recorder in the closure at _startAutosave time) and let detach happen after the flush's drain, or move the detach into the flush future's completion.

## Keyboard and focus

Modifier-hold behaviors interact with OS focus changes, chords, and input modes in ways the hold machinery never specified.

### G-43 · Bare Alt keydown springs the Eyedropper: pauses playback, kills a precision pen line, fires on Alt+Tab and Alt chords

**Severity:** medium · **Verdict:** confirmed · **Found by:** keyboard-dialogs

**Disposition (2026-08-26).** Point fix. Bare-Alt check plus the secondary-pick guards; the pen-down half is additionally covered by the ADR 0010 in-flight predicate.

**Collision.** The hold-Alt temporary Eyedropper vs. playback, precision pen-down (Hold) mode, Alt-based chords (layer.up/down = Alt+]/Alt+[), and OS-level Alt shortcuts (Alt+Tab)

**Current behavior.** The Alt hold has no modifier, playback, or pen-down guard — only drafts and pointerActive (dispatcher.dart:189-195), unlike Space, which refuses when any other modifier is down (dispatcher.dart:177-181). beginHoldPick calls _selectTool('Eyedropper') (editor_page.keyboard.dart:155-160), which pauses playback (editor_page.engine.dart:482) and sends CursorPenUp() ending an open precision pen line (editor_page.engine.dart:483-486), then journals SelectTool(Eyedropper) plus the full _pushToolSettings barrage; endHoldPick journals the round trip back. Consequences: (1) pressing Alt+] to move a layer up transiently switches the active tool to Eyedropper (row-1 rebuilds to Eyedropper options) and back on release; (2) Alt+Tab away from the app springs the Eyedropper, pauses any running playback, and writes two SelectTool round-trips into the always-on Journal (visible later in Watch-replay/timelapse) — every single time; (3) with precision Hold (pen-down) active, a stray Alt press silently ends the pen line. By contrast the right-click pick — the same conceptual action — explicitly guards _penDown and _playing (editor_page.canvas.dart:375-376: 'if (_drawPointer != null || _pinching || _hasAnyDraft || _penDown || _playing) return'). Additionally, endHoldPick's restore check ('_tool == Eyedropper') means a user who deliberately taps the Eyedropper tile WHILE Alt is held gets their explicit choice reverted on Alt release (editor_page.keyboard.dart:163-169).

**Why this is a gap.** Alt is simultaneously a hold binding, a chord modifier for layer.up/down, and the OS window-switch prefix; the spring was specified to fire on bare Alt keydown without waiting to see whether a chord or Alt+Tab follows. The Space hold got a modifier check; Alt did not. The right-click pick's guard list shows what the intended invariants for a temporary pick are — the keyboard route implements only two of the five.

**Repro.** Start playback and press Alt (or Alt+Tab away): playback pauses and the toolbar flashes Eyedropper. Or: enable Pencil Precision with Hold (pen down), press Alt momentarily — the pen line is committed/ended. Or: press Alt+] and watch the tool strip and row-1 flash Eyedropper while the layer moves.

**Evidence.** dispatcher.dart:151-196 (Alt path lacks the modifier check Space has at 177-181); editor_page.keyboard.dart:155-169; editor_page.engine.dart:482-486 (pause + CursorPenUp inside _selectTool); editor_page.engine.dart:571-585 (_pushToolSettings journal traffic per switch); editor_page.canvas.dart:374-376 (right-click pick guards _penDown and _playing); default_bindings.dart:69-70 (layer.up/down are Alt chords)

**Suggested behavior.** Mirror the Space hold's modifier check (bare Alt only), and mirror _secondaryPick's guards: refuse the spring while _penDown or _playing (or at least make it not pause playback). Ideally defer the spring until Alt has been held briefly with no chord key following, so Alt chords and Alt+Tab don't transiently switch tools.

### G-44 · Hold bindings do not re-arm when focus returns with the key still down — and each hold recovers differently

**Severity:** low · **Verdict:** confirmed · **Found by:** keyboard-dialogs

**Disposition (2026-08-26).** Point fix. Re-derive hold states from HardwareKeyboard on focus regain.

**Collision.** The forced release of holds on focus loss (dialog/sheet opens) vs. the physical key still being held when focus returns

**Current behavior.** Opening any route force-releases all holds via onFocusChange (dispatcher.dart:250-254, releaseAllHolds 94-108) — correct, since keyUps stop arriving. But nothing re-reads HardwareKeyboard state on focus regain, so a key held across the dialog behaves three different ways afterward: Shift-constrain self-heals on the next Shift auto-repeat because _trackConstrain is level-triggered on every event (dispatcher.dart:139-147) — on Windows within ~0.5 s, but never on platforms whose modifiers don't auto-repeat (macOS/iPad hardware keyboards); Space-pan can NOT recover: the repeat branch only sustains an existing hold ('(isSpace && _spaceHeld)' at dispatcher.dart:170-175 returns ignored when the hold was cleared) and the arming branch (176-187) requires a fresh KeyDownEvent, so hold-Space silently stops panning until the user fully releases and re-presses Space; hold-Alt likewise never re-springs from repeats (same branch). Meanwhile chord matching still sees the physically-held modifiers via HardwareKeyboard (chords.dart:26-35), so chords behave as if Shift/Alt are held while the constrain/pick effects say they aren't.

**Why this is a gap.** The stuck-state recovery design (DESIGN.md 2.3 per the comments) specified the release half — 'a held mode can never survive its key' — but not the resume half: what a hold means when its key was never released across a focus round-trip. The three holds ended up with three accidental answers.

**Repro.** Hold Space and pan; with Space still held, click a frame tile's long-press menu open and close it (or T then Esc); keep holding Space and drag on the canvas — it draws instead of panning until Space is released and re-pressed. Do the same with Shift while dragging a shape endpoint: on Windows constrain comes back by itself, on an iPad hardware keyboard it doesn't.

**Evidence.** dispatcher.dart:94-108, 139-147, 170-187, 250-254; chords.dart:26-35 (chords read live modifier state, diverging from the cleared hold flags)

**Suggested behavior.** On focus regain (onFocusChange(true) or _rearmOnTap), re-derive the three hold states from HardwareKeyboard.instance (Space cannot be read there, but Shift/Alt can; for Space, let a KeyRepeatEvent re-arm the hold when it is not currently held and not gated).

### G-45 · Crop dialog: Reset/aspect-lock taps during an active rect drag are silently overridden by the drag's snapshot

**Severity:** low · **Verdict:** confirmed · **Found by:** keyboard-dialogs

**Disposition (2026-08-26).** Point fix. Reset and the aspect-lock toggle clear the active drag state.

**Collision.** CropPage's AppBar Reset (and aspect-lock) buttons vs. an in-progress one-finger drag of the crop rectangle

**Current behavior.** A rect-move drag snapshots _startX/_startY at pan-start and every update calls _geo.setOrigin(_startX + dx, _startY + dy) (crop_dialog.dart:246-281). The AppBar buttons remain tappable with a second finger during the drag; Reset rewrites _geo's fields (crop_dialog.dart:342-355), but the very next _onPanUpdate from the still-active drag restores the origin from the pre-reset snapshot, so the Reset visibly takes effect for one frame and is then undone (the w/h reset survives, x/y do not — a half-applied reset). Toggling the aspect lock mid-corner-drag similarly reshapes the rect from the next update using the stale drag anchor.

**Why this is a gap.** The drag snapshot design assumed geometry is only mutated by the drag itself while a drag is live; the always-enabled AppBar actions were specified independently and nobody defined which wins when both mutate the same CropGeometry concurrently. Touch-only (needs a second finger), which is why it survives desktop testing.

**Repro.** On a touch device open Import image -> Crop -> Select crop area, drag the rect with one finger and, while still dragging, tap Reset with another: the rect snaps to default then jumps back under the continuing drag, leaving a mixed state.

**Evidence.** crop_dialog.dart:151-157 (drag snapshot fields), 274-281 (_onPanUpdate writes from snapshot), 342-355 (Reset rewrites _geo with no drag-state invalidation; _dragCorner/_dragMove are not cleared)

**Verifier correction.** The aspect-lock half is milder than described: dragCorner (crop_dialog.dart:49-74) reads live geometry each update rather than a stale snapshot, so toggling the lock mid-corner-drag reshapes from the CURRENT (just-toggled) rect — the fixed-corner anchor shifts once, but there is no persistent snapshot override like the move-drag/Reset case. The crisp defect is the Reset x/y revert during a move drag.

**Suggested behavior.** Have Reset (and the aspect-lock toggle) clear the active drag state (_dragCorner = null, _dragMove = false) so a live gesture cannot resurrect pre-reset geometry.

## Palette and color

Smaller inconsistencies where two color surfaces disagree about state.

### G-46 · Color picker: a typed hex value is silently discarded when OK is pressed without Enter

**Severity:** medium · **Verdict:** confirmed · **Found by:** palette-color

**Disposition (2026-08-26).** Point fix. Apply a valid hex on OK and on focus loss.

**Collision.** The hex field's apply-on-submit contract x the dialog's OK button committing the internal h/s/v/a state

**Current behavior.** The RGB, HSV, and alpha text fields apply live on every keystroke (onChanged, color_picker_dialog.dart:225, 345), but the hex field applies only on onSubmitted (line 363 — there is no onChanged and no apply-on-focus-loss). OK pops with _color, which is built purely from h/s/v/a (lines 121, 374-377). So typing a full hex code and tapping OK (or, on mobile, tapping OK because the number-row keyboard's Done was never pressed) returns the previous color; the typed text is visible in the field at the moment OK is tapped but has no effect. The translucent tap-to-unfocus wrapper (line 550-552) also does not apply the hex — it just dismisses the keyboard.

**Why this is a gap.** onSubmitted-only was presumably chosen because partial hex strings are ambiguous mid-typing (unlike the clamped numeric fields), but the interaction of that choice with the OK button — the state the user SEES vs the state the dialog commits — was never specified. The three numeric field groups and the hex field end up with different commit semantics for the same conceptual action.

**Repro.** Open Pick color from the primary swatch, click into the hex field, type FF0000 over the old value, click OK without pressing Enter. The primary color is unchanged (still the old color) despite the field showing FF0000.

**Evidence.** app/lib/editor/dialogs/color_picker_dialog.dart:351-367 (_buildHexRow, onSubmitted only), 204-228 (_numField uses onChanged), 320-349 (alpha field uses onChanged), 369-378 (OK pops _color from h/s/v/a), 121 (_color getter)

**Verifier correction.** Not entirely 'silent': the live result swatch in the dialog header (line 389) does not turn to the typed hex, giving visible (if subtle) feedback that the value was never applied. The discard-on-OK behavior itself is exactly as claimed.

**Suggested behavior.** Apply the hex field's content on OK (and/or on focus loss) when it parses as a valid 6/8-digit hex, matching the live-apply behavior of every other field; keep ignoring unparseable text.

### G-47 · Right-click eyedropper pick leaves the engine's gradient stops stale while the Gradient tool is active

**Severity:** medium · **Verdict:** confirmed · **Found by:** palette-color

**Disposition (2026-08-26).** Point fix. Route engine-side picks through the primary setter, or resend gradient stops while the Gradient tool is active.

**Collision.** Desktop right-click color pick (uncommitted mouse-affordances work) x the Gradient tool's rule that the primary color IS the first gradient stop

**Current behavior.** _secondaryPick is reachable with Gradient active (its guard only blocks strokes/pinch/drafts/pen-down/playback). It swaps the engine to Eyedropper, picks, restores SelectTool(Gradient), and calls _syncPickedPrimary(), which only does setState(() => _primary = c). Unlike _setPrimary (editor_page.engine.dart:755-769), it never calls _sendGradientStops(), and SetGradientStops embeds explicit hex values (engine.dart:774-779), so the engine keeps the OLD first stop. Row-1's first gradient swatch renders _primary (editor_page.controls.dart:432), so the UI shows the picked color while the next gradient drag draws starting from the old color. Every other pick route is consistent: tapping a swatch goes through _setPrimary (re-pushes stops), the hold-Alt spring restores via _selectTool which re-sends the stops on Gradient entry (engine.dart:560-563).

**Why this is a gap.** The right-click pick was designed as a tool-preserving convenience ('without changing the active shell tool') and mirrors the pick into the swatch, but nobody specified what happens to derived color state (the gradient's first stop) that _setPrimary normally refreshes. The guard list in _secondaryPick shows the interactions that WERE considered; gradient stops are absent.

**Repro.** Windows build, select the Gradient tool, note the first color swatch (e.g. red). Right-click a blue pixel on the canvas — the row-1 first swatch turns blue. Drag a gradient: it renders starting from red, not the blue shown in the UI.

**Evidence.** app/lib/editor/editor_page.canvas.dart:375-394 (_secondaryPick, guard at 376, _syncPickedPrimary at 390); app/lib/editor/editor_page.engine.dart:446-449 (_syncPickedPrimary sets only _primary), 755-769 (_setPrimary re-pushes stops for Gradient), 774-784 (_gradStopsDsl embeds hex; _sendGradientStops call sites are only _setPrimary, count/extra-color changes, and _selectTool entry at 560-563); app/lib/editor/editor_page.controls.dart:426-439 (row-1 swatch renders _primary)

**Suggested behavior.** _secondaryPick (and Eyedropper-tool drag picks generally) should route the picked color through _setPrimary, or at minimum call _sendGradientStops() when _tool == 'Gradient', so the engine's stops always match the displayed first swatch.

### G-48 · Eyedropper picks never update _previousPrimary, so the X (swap-with-previous) command restores a stale color

**Severity:** low · **Verdict:** confirmed · **Found by:** palette-color

**Disposition (2026-08-26).** Point fix. Record the outgoing primary into the previous-primary slot when a picked color differs.

**Collision.** Keyboard shortcut 'swap with previous color' x the eyedropper's engine-side primary update path

**Current behavior.** _previousPrimary is recorded only inside _setPrimary (editor_page.engine.dart:758). All eyedropper pick routes — canvas tap/drag picks (editor_page.canvas.dart:505, 609), the precision Pick button (controls.dart:53 via EyedropCursor + _refreshState), and the right-click pick (canvas.dart:390) — update _primary via _syncPickedPrimary/_refreshState without touching _previousPrimary. So: primary red -> tap swatch blue (previous=red) -> eyedrop green -> press X: primary becomes red, not the blue the user had immediately before the pick. Two input routes for 'change the current color' feed the swap history differently.

**Why this is a gap.** The X command's contract is 'swap with the previous color'; _previousPrimary was wired into the one Dart-side setter, and the eyedropper paths (which set the color engine-side and mirror it back) were never included. Nothing documents that eyedropper picks are excluded from the swap history.

**Repro.** Set primary to blue via a swatch tap, eyedrop green from the canvas, press X. Primary becomes whatever was set by _setPrimary before blue (or white on a fresh session), not blue.

**Evidence.** app/lib/editor/editor_page.engine.dart:446-449 (_syncPickedPrimary), 755-758 (_previousPrimary only here); app/lib/editor/editor_page.keyboard.dart:117 (swapWithPreviousColor uses _previousPrimary); app/lib/editor/editor_page.canvas.dart:390, 505, 609 (pick routes bypassing _setPrimary); app/lib/editor/editor_page.dart:169 (initial value)

**Suggested behavior.** Treat an engine-side pick as a primary change for swap purposes: in _syncPickedPrimary, record the outgoing _primary into _previousPrimary when the picked color differs.

### G-49 · Palette swatch move-arrow sheet captures the strip orientation; rotating the device while it is open mis-maps the arrows

**Severity:** low · **Verdict:** confirmed · **Found by:** palette-color

**Disposition (2026-08-26).** Point fix. Read orientation inside the sheet builder instead of capturing it.

**Collision.** The orientation-transposing row-2 palette strip x the long-lived swatch bottom sheet whose arrows are remapped per orientation

**Current behavior.** _paletteSwatchMenu(i, c, vertical: vertical) captures `vertical` from the _buildPalette invocation at sheet-open time (editor_page.controls.dart:887-888, 940-952). paletteMoveTargets deliberately transposes the arrow mapping per orientation (palette_io.dart:121-130: portrait left/right = +-2, up/down = lane swap; landscape swaps them). If the device rotates while the sheet is open, the editor underneath rebuilds into the transposed strip, but the sheet keeps the stale `vertical`, so 'Move left' now performs the movement that is visually up/down on the strip behind it, and the follow-the-swatch feature moves it a direction different from the arrow pressed.

**Why this is a gap.** The arrow remapping exists precisely so arrows 'always point the way the swatch visually travels' (comment at controls.dart:942-944) — an orientation change mid-sheet defeats the feature's own stated invariant, and no code path refreshes the captured flag.

**Repro.** On a tablet/phone allowing rotation: portrait, long-press a palette swatch to open the menu, rotate to landscape (sheet stays open), press 'Move left'. The swatch moves along what is now the vertical axis instead of left.

**Evidence.** app/lib/editor/editor_page.controls.dart:887-888 (capture), 940-952 (sheet uses captured vertical), app/lib/editor/palette_io.dart:121-130 (transposed mapping)

**Suggested behavior.** Read the orientation inside the sheet builder (MediaQuery/editorUsesLandscape) instead of capturing it, or dismiss the sheet on orientation change like other geometry-dependent overlays.

## Appendix: refuted findings

Three findings were killed by the adversarial verification pass. They are kept here because each documents a *deliberate* design the next reader might otherwise re-flag as a gap.

### Palette .gpl export/re-import silently drops alpha and color names, and writes the hex where GPL expects the name

**Claimed.** Translucent palette colors + the color-names feature x the GPL export/import round trip

**Why refuted.** The mechanics are accurate (encodeGpl at palette_io.dart:90-96 writes hexRgba as the 4th column; the parser at :77-84 reads only R/G/B with alpha forced 255; buildImportScript at :148-154 carries no names) — but this is a documented, deliberate design, not an unspecified collision. The doc comment on encodeGpl (palette_io.dart:89) states outright: 'alpha is kept in a 4th hex column, ignored on re-import', and the parser's own doc (:51) says 'GPL rows are R G B [hex [label]]; alpha stays 255' — the author knew the GPL format has no alpha, knew labels exist in the column, and chose the lossy round trip explicitly. The remaining half (per-entry display names never exported/imported) is a feature that was simply never built onto the older export path, which the task scopes out ('missing features that were clearly just not built'). GIMP showing the hex string as the name is the direct consequence of the documented 4th-column alpha stash, not an unconsidered state.

**Still worth considering.** Write the display name (when present) as the GPL label and parse labels back into names on import; either honor the exported hex column's alpha on re-import of the app's own files, or state the loss in the export confirmation.

### Which controls close the sheet is inconsistent: Rename/Copy-to-all-frames close, while the opacity text dialog and blend picker stack on top

**Claimed.** The stay-open contract ('every action keeps the sheet open so taps chain') + three different secondary-surface patterns inside the same sheet: Rename pops the sheet then shows a text dialog; opacity tap-to-type shows a text dialog OVER the open sheet; blend shows a second bottom sheet OVER it

**Why refuted.** The described behavior is accurate (Rename pops at sheets.dart:298-300, Copy-to-all pops at 449, opacity dialog stacks at 366-370, blend picker stacks at 385-388/479-518), but it is a deliberate, documented design choice, not an unspecified collision: the sheet's own contract comment (sheets.dart:212-213) explicitly carves out 'Everything except rename and Copy to all frames keeps the sheet open' — the author enumerated exactly which controls close, and the feature's project notes track 'Rename + Copy-to-all-frames still close' as the accepted shipped state. A documented, intentional exception fails the verification bar even if the underlying rationale is debatable.

**Still worth considering.** Pick one rule - keep the sheet under all secondary surfaces (rename dialog over the sheet, like opacity) - and reserve closing for actions that navigate away; that also removes the cancel-loses-the-sheet wrinkle.

### Watch replay can read the journal while a just-started attach is still reconciling it

**Claimed.** The Watch-replay flow's direct file read vs. an in-flight attachResume (truncate + re-anchor append) right after a drawing switch

**Why refuted.** The claimed short-circuit cannot fire right after a drawing switch: _adopt → _startAutosave constructs a FRESH AutosaveController (persistence.dart:83) whose _hasSaved starts false (the old one was nulled at persistence.dart:200), and flushNow's byte-identical skip requires _hasSaved (autosave_controller.dart:91). So _watchReplay's 'await _autosave?.flushNow()' (editor_page.replay.dart:104) always enqueues a write after a switch, and its drain's preWrite awaits _journalAttaching (persistence.dart:94-96) before the doc write completes and flushNow resolves — serializing the subsequent File.readAsString behind the attach's truncation/re-anchor. The stated repro (open a drawing, draw nothing, immediately tap Watch replay) is exactly the case that IS serialized. Reaching the short-circuit with an attach still in flight would require a completed prior save through the same controller instance, whose own preWrite already awaited that same attach — self-contradictory except for far-fetched multi-second attach stalls combined with drawing activity, which the finding's scenario excludes.

**Still worth considering.** Have _watchReplay (and any other direct journal reader) 'await _journalAttaching' before flushing and reading the files.
