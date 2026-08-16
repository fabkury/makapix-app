# Physical keyboard shortcuts in the Makapix Editor — design

**Date:** 2026-08-16 · **Status:** **v1 (6.A) implemented 2026-08-16** — stages: registry +
dispatcher + tap bindings · Hold bindings · broad Shift-constrain · discoverability + stored-
bindings loader. As-built amendments to §4's draft map: **X = swap primary ↔ previous color**
(the editor has no secondary color; a shell-remembered last color, maintained by `_setPrimary`),
**Primary+V switches to the CopyPaste tool** before starting the paste draft, `playback.stop`
exists as its own Esc-bound Command, and `help.keyboard` (?) opens the cheat sheet. Phase 6.B
(the rebinding UI) remains open. Product of the grilling session that followed `ANALYSIS.md`
(same directory); decisions below are settled unless marked draft.
Terminology (Command, Chord, Binding, Hold binding) is canonical in `CONTEXT.md`; the
architectural ground rule is ADR 0009.

**Scope:** the Editor pillar only. The Animator is **explicitly out** — this design must not
grow Animator hooks, and the registry is editor-local. Club/shell shortcuts are out. Windows is
not a target; it benefits incidentally because the same Flutter code runs there.

**Driver:** market positioning — a serious drawing app competing with the major tablet art apps.
Audience: iPad and Android (incl. ChromeOS) keyboard users of the Editor.

---

## 1. Settled decisions (the design tree)

| # | Decision |
| --- | --- |
| 1 | **Go.** V1 = phase **6.A** (fixed default Bindings, whole catalog); **6.B** (full user configurability) is the follow-up release, and 6.A is built 6.B-ready (stable command ids, bindings store present from day one). |
| 2 | **Hold bindings are in v1:** hold-Space = pan, hold-⌥/Alt = temporary Eyedropper. Spring-loading *all* tool keys is deferred (a policy, not a v1 item). |
| 3 | **Shift-constrain is in v1, broad:** every directional drag — Line (0°/45°/90° snap), Rectangle→square, Ellipse→circle, Move (axis lock), Gradient (angle snap), Ruler (angle snap). It is **fixed gesture grammar, not a Binding** — no Command, never rebindable, documented in the cheat sheet. |
| 4 | **Coverage:** the whole expressible catalog (§3), not a curated core. |
| 5 | **Defaults convention:** hybrid — platform system chords (⌘Z/⌘S-family; Primary = ⌘ on iPad, Ctrl on Android/ChromeOS/Windows) plus single-letter tool mnemonics designed for Makapix's own tool grid, leaning Aseprite/Photoshop where they coincide. |
| 6 | **Discoverability, both surfaces in v1:** a hold-Primary overlay and a ☰-menu "Keyboard" help sheet — one registry-driven categorized list widget rendered two ways. (The iPadOS hold-⌘ HUD is unavailable to Flutter apps; ours replaces it.) |
| 7 | **6.B rebind scope:** every Binding, tap and hold alike. The core four Commands (draft-cancel, draft-commit, undo, redo) are rebindable but **never unbindable**. Rebinding UI: editor ☰ → **Keyboard** page (`palette_page` pattern). |
| 8 | **Default map is trusted, not gated:** implemented from the draft in §4 and corrected live on device; no approval loop. |
| 9 | **Verification:** Android + physical keyboard, device-verified (hardware on hand). iPad ships **best-effort** on Android-verified confidence; issues fixed from field feedback. |
| 10 | **Commands route only through shell pathways** (ADR 0009): a Command invokes the same `_EditorPageState` method as its on-screen control — never raw DSL — so draft bookkeeping, playback pause, and the Journal tap (`_send` → `JournalRecorder`) come free. Engine, FFI, and formats are untouched. |

## 2. Architecture

### 2.1 The command registry

A pure-data catalog in `app/lib/editor/keyboard/commands.dart`:

```dart
class CommandDef {
  final String id;          // stable forever; the 6.B bindings-file contract
  final String label;       // cheat-sheet / Keyboard-page display name
  final String category;    // Tools · Edit · Frames · Layers · View · Playback · Color · File
  final bool Function(EditorAccess) enabled;  // modality predicate
  final void Function(EditorAccess) invoke;   // calls a shell method, nothing else
}
```

`EditorAccess` is a narrow interface implemented by `_EditorPageState` exposing exactly the
existing shell entry points (`selectTool`, `act`, `undo`, `nextFrame`, …) — the registry is a
thin index over methods that already exist, not a refactor driver. **Command ids are a
persistent contract** (ADR 0009): renaming or splitting a Command requires a bindings-file
migration entry, the same discipline the DSL applies to retired verbs.

### 2.2 Key plumbing

- A single `Focus` node at the editor page root with an `onKeyEvent` handler (the
  `HardwareKeyboard` path — **not** the `Shortcuts` widget, which cannot express Hold bindings
  or ordered modality checks). One dispatcher: resolve Chord → Binding → Command, check
  `enabled`, invoke.
- **Modality gating, in order:** (1) any `TextField` focused or dialog open → only Esc (close)
  is handled, everything else falls through to the field/IME; (2) a sheet is open → Esc closes
  it, sheet-scoped commands allowed, canvas commands inert; (3) a draft exists → Enter commits,
  Esc cancels; (4) playback running → Enter/Esc toggle/stop, frame-step commands act on the
  preview position, paint-tool commands pause first (mirroring `_selectTool`); (5) otherwise the
  full catalog.
- **Chords are matched on logical keys** with per-platform Primary resolution; the bindings
  store records what was pressed, which is also what makes 6.B layout-proof on AZERTY/QWERTZ.
- **Android:** Esc arrives as it does on ChromeOS keyboards; the handler consumes it before the
  system back mapping when a draft/sheet/dialog is open, and lets it fall through otherwise.
  iPadOS reserved combos (⌘H, ⌘Tab, Globe) are never bound and are blocklisted in 6.B.

### 2.3 Hold bindings

A keyDown/keyUp state machine beside the dispatcher, v1 entries:

- **hold-Space → pan**: canvas drags pan the view while held; release restores the active tool's
  gestures. No engine traffic at all (pan is shell view state).
- **hold-⌥/Alt → Eyedropper**: on press, remember the current tool and `selectTool('Eyedropper')`
  via the normal pathway (journal-visible, correct — replays reproduce the pick); on release,
  restore the remembered tool. Tapping `I` remains the sticky tool switch.

**Stuck-state recovery is a v1 requirement:** on `AppLifecycleState` pause/inactive, on page
focus loss, and on editor dispose, all held states force-release (restore tool, end pan). A held
key whose keyUp never arrives must never survive backgrounding.

### 2.4 Shift-constrain (broad)

A single `constrainHeld` flag set by the key handler and read by the drag pathways in
`editor_page.canvas.dart`. Per-tool semantics: Line/Ruler/Gradient snap the drag vector to
0°/45°/90°; Rectangle/Ellipse equalize the axes; Move locks to the dominant axis. The constraint
transforms **pointer coordinates before they become DSL cursor traffic**, so the engine and the
Journal see only ordinary coordinates — replays are automatically faithful and the engine is
untouched. Mid-drag press/release re-evaluates on the next pointer event (industry behavior).
This is the largest cost item after the registry: each tool's drag handler is its own small
surgery with its own widget-test rows.

### 2.5 Discoverability

One widget (`keyboard/cheat_sheet.dart`) renders the registry grouped by category with resolved
chords. Surface A: hold Primary ~600 ms with no other key → overlay; release dismisses.
Surface B: ☰ → "Keyboard" opens the same list as a page (in 6.B this page grows the rebinding
controls; in 6.A it is read-only). Shift-constrain and the Hold bindings appear in a fixed
"Held keys" section.

### 2.6 The bindings store (6.B-ready from day one)

`keyboard_bindings.json` in the app-support directory (same home as the drawing store):
`{ "version": 1, "bindings": { "<commandId>": "<chord>" | null } }` — absent id = platform
default; `null` = deliberately unbound (illegal for the core four). V1 ships the loader and the
defaults tables; only the editing UI is 6.B. Migration table keyed by version, DSL-style
"old ids parse forever".

## 3. The catalog (v1 command ids)

- **Tools (26):** `tool.pencil`, `tool.brush`, `tool.airbrush`, `tool.eraser`, `tool.fill`,
  `tool.gradient`, `tool.line`, `tool.shape`, `tool.ruler`, `tool.dodge`, `tool.burn`,
  `tool.pick`, `tool.move`, `tool.copyPaste`, `tool.select`, `tool.selectColor`,
  `tool.selectLayer`, `tool.hsv`, `tool.brightness`, `tool.levels`, `tool.flip`, `tool.rotate`,
  `tool.resize`, `tool.invert`, `tool.play`, `tool.onion`
- **Edit:** `edit.undo`, `edit.redo`, `edit.copy`, `edit.paste`, `edit.selectAll`,
  `edit.deselect`
- **Draft:** `draft.commit`, `draft.cancel` (the core four are these two + undo/redo)
- **Frames:** `frame.prev`, `frame.next`, `frame.add`, `frame.duplicate`, `frame.delete`
- **Layers:** `layer.up`, `layer.down`, `layer.add`
- **View:** `view.zoomIn`, `view.zoomOut`, `view.zoomFit`, `view.zoom100`
- **Playback:** `playback.toggle`
- **Color:** `color.swap`, `brush.sizeUp`, `brush.sizeDown`
- **File:** `doc.save`, `doc.export`
- **Sheets/help:** `sheet.timeline`, `sheet.layers`, `help.keyboard`
- **Holds (bindable in 6.B):** `hold.pan`, `hold.pick`

## 4. Draft default chord map (decision #8: trusted, corrected live)

Primary = ⌘ (iPad) / Ctrl (elsewhere). Letters are unmodified logical keys.

| Category | Command → Chord |
| --- | --- |
| Tools | Pencil **P** · Brush **B** · Airbrush **A** · Eraser **E** · Fill **G** · Gradient **⇧G** · Line **L** · Shape **U** · Ruler **K** · Dodge **O** · Burn **⇧O** · Pick **I** · Move **V** · Copy **C** · Select **M** · Sel Color **W** · Sel Lyr **⇧W** · HSV **H** · Bright **⇧H** · Levels **⇧L** · Flip **F** · Rotate **R** · Resize **⇧R** · Invert **Primary+I** · Play tool **⇧P** · Onion **N** |
| Edit | Undo **Primary+Z** · Redo **⇧Primary+Z** (alias **Primary+Y**) · Copy **Primary+C** · Paste **Primary+V** · Select all **Primary+A** · Deselect **Primary+D** |
| Draft | Commit **Enter** · Cancel **Esc** |
| Frames | Prev **,** · Next **.** · Add **⇧N** · Duplicate **⇧D** · Delete **Primary+Backspace** |
| Layers | Up **⌥]** · Down **⌥[** · Add **⇧Primary+N** |
| View | Zoom in **Primary+=** · out **Primary+-** · fit **Primary+0** · 100% **Primary+1** |
| Playback | Toggle **Enter** (only when no draft; **Esc** stops) |
| Color | Swap **X** · Size up **]** · Size down **[** |
| File | Save **Primary+S** · Export **⇧Primary+E** |
| Sheets/help | Timeline **T** · Layers **Y** · Keyboard sheet **⇧/** (?) |
| Held | Pan **Space** · Pick **⌥/Alt** · Constrain **⇧** (fixed grammar) |

Arrow keys are deliberately **reserved unbound** in v1 (future precision-cursor nudge).

## 5. Testing and verification

- **Unit:** registry integrity (unique ids, unique default chords per platform, every id has a
  label/category), bindings-store round-trip and migration, chord parsing.
- **Widget** (engine-free, `tester.sendKeyEvent`): modality gating rows (text field, sheet,
  draft, playback), Enter/Esc duality, hold press/release/lifecycle-interrupt, Shift-constrain
  per drag pathway, cheat-sheet render.
- **Device:** Android + physical keyboard is the verified platform (release-pass checklist row).
  iPad: best-effort, no device gate (decision #9). Windows dev build: incidental smoke.

## 6. Out of scope (recorded so they are not silently assumed)

Animator (entirely, by instruction) · Club/shell shortcuts · spring-loading all tool keys ·
remappable Shift-constrain · arrow-key bindings · the 6.B rebinding UI (follow-up release, but
its store, ids, and screen location — editor ☰ → Keyboard — are already decided).
