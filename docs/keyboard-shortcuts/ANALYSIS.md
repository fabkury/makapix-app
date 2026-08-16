# Physical keyboard shortcuts in the Makapix Editor — analysis

**Date:** 2026-08-16 · **Status:** exploratory survey — pros, cons, costs, and risks only.
This document draws **no go/no-go conclusion** and is not an implementation commitment.

**Question analyzed:** the Makapix Editor is smartphone-first, but what would it cost, and what
would it risk, to support physical keyboards — specifically (a) *extensive* keyboard-shortcut
coverage of editor actions and (b) *every* shortcut being user-configurable? Per the framing
decisions taken for this analysis: the platforms that matter are **iPad + attached keyboard** and
**Android + attached keyboard** (tablets, ChromeOS, foldables, DeX); Windows desktop is dev-only and
counted only as an incidental beneficiary; scope is the **editor pillar only** (Club/shell shortcuts
are a future-extension note); and fixed default shortcuts vs. the configurability layer are **costed
separately**, because they turn out to have very different price tags.

---

## 1. Three different things hide inside "keyboard shortcuts"

They are separable, and each has its own cost curve:

- **Discrete shortcuts** — press a combo, an action fires once: Undo, select the Pencil, next
  frame, toggle play, save. Maps cleanly onto Flutter's `Shortcuts`/`Actions`/`Intent` machinery.
- **Momentary (held) keys** — hold Space to pan, hold a key to temporarily eyedrop, release to
  return to the previous tool. This is a keyDown/keyUp state machine, *not* the `Shortcuts` table,
  and it is where desktop art programs get their fluency. Also where the stuck-state bugs live
  (§7.3).
- **Configurability** — a user-editable binding table with capture UI, conflict handling,
  persistence, per-platform defaults, and forward migration. A multiplier on everything above.

"Extensive coverage" needs a fourth ingredient: a **command registry**. Today no such thing exists —
editor actions are private methods on one `State` class spread across nine part files. The registry
(a first-class, enumerable catalog of command id → invocation) is the real architectural work; the
key bindings themselves are just a table pointing into it.

## 2. Where the codebase stands (the load-bearing facts)

Verified against the tree on 2026-08-16:

1. **Zero keyboard handling exists in the editor.** No `Shortcuts`, `Actions`, `Focus`,
   `KeyEvent`, or `HardwareKeyboard` usage anywhere under `app/lib/editor/`. (The only keyboard
   code in the app is incidental text-field focus in two Club pages.) This is a green field — no
   legacy to fight, but also no scaffolding to lean on.
2. **The dispatch architecture is favorable.** Every editor action already funnels through shell
   methods on `_EditorPageState` — `_selectTool()`, `_act()`, `_send()`
   (`editor_page.engine.dart`) — and those methods carry all the bookkeeping that makes an action
   safe: pausing playback, canceling pending shape/selection/paste/move/rotate/resize drafts,
   clearing the Select Layer overlay, re-pushing tool settings
   (`editor_page.engine.dart:477-567`). A shortcut layer that *calls these existing methods* gets
   all of that for free. A shortcut layer that bypasses them and sends raw DSL would corrupt shell
   state — this is the one implementation rule that must be load-bearing from day one.
3. **The replay Journal is automatically compatible.** `_send()` taps `JournalRecorder.record()`
   verbatim before running the DSL (`editor_page.engine.dart:230`). A shortcut-invoked Undo is
   byte-identical in the journal to a button-invoked Undo. **No new engine verbs, no FFI changes,
   no `.mkpx` or journal format impact whatsoever.** This is a pure-shell feature; the engine and
   `crates/` are untouched.
4. **Modality is everywhere.** Whether a given action is legal depends on tool, draft state,
   playback state, and which sheet/dialog is open. `_selectTool` alone handles seven distinct
   pending-draft cancellations. Shortcuts inherit this modality: Enter/Esc mean commit/cancel only
   while a draft exists; frame-step keys should be inert (or act on the preview) during playback;
   everything must be inert while a `TextField` has focus (rename dialog, color-picker hex field,
   crop dialog, palette page — all real, all present today).
5. **Testability is good.** The Dart test suite runs engine-free by policy, widget tests for
   editor chrome already exist (`app/test/editor_chrome_test.dart`), and `flutter_test` can inject
   key events (`tester.sendKeyEvent`). If the binding table and command registry are pure data,
   they unit-test trivially; the focus-scoping behavior tests as widget tests.
6. **Persistence precedent exists.** The editor already owns an on-disk store
   (`editor/persistence/`), and settings-like state survives pillar switches via autosave. A
   bindings file (JSON in the app-support dir) follows an established pattern; nothing new
   infrastructurally.

## 3. Platform reality: iPad and Android keyboards

- **iPad is the strong case.** iPad + Apple Pencil + Magic/Smart Keyboard is a real, growing
  pro-artist configuration, and the canonical workflow — left hand on keys (undo, tool taps,
  bracket-key brush size), right hand drawing — is exactly what shortcuts enable. Procreate,
  which historically compensated with QuickMenu, now ships extensive keyboard support; it is a
  table-stakes feature for "serious iPad art app" positioning.
- **The iPadOS shortcut HUD does not work for Flutter apps.** The hold-⌘ discoverability overlay
  is populated from `UIKeyCommand`, which Flutter's key handling bypasses; Flutter shortcuts are
  invisible to it (long-standing open Flutter issue). Discoverability must therefore be built
  in-app: a cheat-sheet overlay (e.g., hold ⌘ to show our own panel, or a "?"-key sheet). That is
  a real, not-optional cost line on iPad — an undiscoverable shortcut system serves nobody.
- **iPadOS reserves combos** (⌘H, ⌘Tab, Globe-key combos, ⌘Space) that the app never sees or
  must not steal. The configurability layer needs a per-platform blocklist so users can't bind
  something the OS will eat.
- **Android is broad but shallow.** Hardware key events are well supported (physical keyboards,
  ChromeOS laptops running the Play build, DeX, foldable covers). ChromeOS is plausibly where most
  Android-keyboard users of a Play-store app actually are. Fewer reserved combos than iPadOS, but
  Meta-key combos belong to the system on ChromeOS.
- **Modifier conventions diverge:** ⌘ on iPad, Ctrl on Android/ChromeOS. Defaults must be
  expressed per-platform (or as an abstract "primary modifier"), and the bindings store must not
  hard-code one platform's modifier.
- **International layouts.** Flutter distinguishes logical (layout-aware) from physical keys, but
  defaults designed on QWERTY can land awkwardly on AZERTY/QWERTZ (the classic `[`/`]` brush-size
  keys don't exist as unshifted keys on many layouts). Notably, **user configurability largely
  neutralizes this risk** — the capture UI records whatever the user physically pressed — which is
  the strongest *technical* argument in favor of the configurability layer.
- **Windows rides along free.** The same `Shortcuts` layer works on the dev-only Windows build,
  which makes the developer's own daily loop faster — worth zero in the market analysis, but a
  genuine quality-of-life gain for development and Windows visual passes.

## 4. Pros

1. **Pro-workflow fluency on iPad+Pencil** — the two-handed workflow is the single biggest speed
   multiplier for serious pixel artists, and Makapix's demographic (Aseprite-adjacent) expects it.
2. **Zero engine/format/replay cost.** Pure shell feature; journal compatibility is free (§2.3).
   This is unusually cheap risk-wise compared to most editor features, which touch the engine.
3. **Forcing function for a command registry.** Reifying actions into an enumerable catalog is
   good architecture independent of keyboards: the same registry later serves a command palette,
   stylus/pen-button mapping, Bluetooth page-turner remotes (a niche but real artist accessory),
   Animator-pillar reuse, and macro/scripting ideas.
4. **Accessibility.** External-keyboard operation is an assistive pattern (motor impairments,
   switch access via keyboard emulation). Full configurability compounds this — users with limited
   reach can cluster bindings.
5. **Store positioning.** "Works great with your keyboard" is an App Store featuring criterion for
   iPad apps and part of the desktop-class-iPad narrative; it also matters for ChromeOS listing
   quality.
6. **Configurability neutralizes layout problems** (§3) and ends all default-binding debates —
   opinionated defaults plus remapping is strictly friendlier than either alone.
7. **Dev-loop dividend on Windows** for free.

## 5. Cons

1. **The reachable audience is a sliver.** Phone users — the overwhelming majority of a
   smartphone-first app — get nothing. The feature serves (tablet users) ∩ (keyboard owners) ∩
   (editor users, not just Club browsers). The app has no analytics to size this set, so the value
   side is a judgment call, not a measurement.
2. **"Extensive coverage" is smaller than it sounds.** The engine has ~160 DSL verbs, but most are
   parameterized settings (brush size 1–64, gradient stops, thresholds) that a discrete keystroke
   can't express — realistic shortcut coverage is roughly 40–60 commands (tools, undo/redo,
   frame/layer navigation, playback, zoom/pan, draft commit/cancel, save/export, sheet toggles).
   Fine — but the "every action has a key" vision overstates what's actually expressible.
3. **A permanent per-feature tax.** Every future editor capability must decide: does it get a
   command-registry entry? A default binding? A settings row? Docs? Features that skip the tax
   create drift between what the registry claims and what the editor does.
4. **Discoverability must be hand-built on iPad** (§3) — an extra UI surface to design, localize
   (someday), and maintain.
5. **Configurability is a whole feature by itself:** a bindings screen comparable in scope to
   `palette_page.dart` (capture-a-keystroke rows, conflict detection and resolution, reset-to-
   default, search/filter at 40–60 commands), plus persistence and versioned migration of stored
   binding files as command ids evolve. It also creates a support surface ("my keys stopped
   working" ≈ user bound Esc to something and lost cancel).
6. **The three-row touch UI stays primary.** Shortcuts duplicate, not replace, every control;
   nothing gets simpler. There is no offsetting UI simplification to harvest.

## 6. Costs

Split per the framing decision. Sizes are relative to recent shipped features (for calibration:
the layer-sheet mini-stack strip was a small feature; the replay viewer was a large one).

### 6.A Fixed default shortcuts (the base layer) — **medium**

| Work item | Notes |
| --- | --- |
| Command registry | Enumerate ~40–60 commands as data (id, label, category, `isEnabled` predicate, invoke thunk calling the existing shell method). The main design task; touches how `editor_page.*` exposes its private methods. |
| Key plumbing | A `Focus`/`Shortcuts` (or `KeyboardListener`) wrapper at the editor-page root; route through the registry. Small once the registry exists. |
| Modality gating | Inert while any `TextField` has focus / dialog or sheet is open, unless the command is sheet-scoped (Esc closes). Enter/Esc wired to draft commit/cancel. The fiddly part; mostly widget-test-driven. |
| Momentary keys (optional sub-line) | Hold-Space pan, hold-to-eyedrop. A separate keyDown/keyUp state machine with focus-loss recovery. Deferrable; **adds noticeably to the base cost and most of the §7.3 risk** — the base layer is credible without it. |
| iPad cheat-sheet overlay | Hand-built discoverability panel (hold-⌘ or "?"). Small-medium UI work. |
| Tests | Registry unit tests + widget tests injecting key events; runs engine-free like the rest of the Dart suite. |
| Hardware for manual passes | A physical iPad keyboard and a Bluetooth keyboard for the Android device become required test equipment for release passes. Ongoing, cheap, but nonzero. |

### 6.B Full user-configurability — **medium, on top of 6.A**

| Work item | Notes |
| --- | --- |
| Bindings model + persistence | Command id → key chord(s); JSON in app-support storage; per-platform default tables; versioned schema with migration when ids change. |
| Rebinding UI | A settings screen at `palette_page` scope: capture next keystroke, show conflicts, allow unbind/rebind/reset-one/reset-all, filter by category. |
| Conflict + blocklist logic | Reject/warn on duplicate chords; per-platform reserved-combo blocklist (⌘H, ⌘Tab, Globe…, ChromeOS Meta). |
| Guardrails | Decide whether Esc/Enter/Undo are rebindable-but-never-unbindable, or fully free; fully free maximizes the support surface (§5.5). |

Only meaningful *after* 6.A exists and has proven demand; shipping 6.B first inverts the value
order (nobody remaps shortcuts they haven't used).

### 6.C Ongoing

The per-feature tax (§5.3), the manual-pass hardware matrix, and binding-file migration whenever a
command is renamed, split (cf. Airbrush → three modes), or retired — the registry inherits the same
"retired verbs must parse forever" discipline the DSL already has, at shell scope.

## 7. Risks

1. **Focus-system regressions (the top technical risk).** Introducing a page-root `Focus` node
   into a page that never had one can steal focus from dialog text fields, fight the IME, or
   interfere with Android system back handling. Flutter focus bugs are subtle and platform-shaped;
   this is where the widget-test budget should concentrate. (History rhyme: the Windows
   accessibility-bridge crash came from an adjacent subsystem — the a11y/focus tree — so treat
   focus-tree changes as visual-pass-worthy on all platforms.)
2. **Shell-state corruption via bypass.** Any shortcut wired to raw DSL instead of the shell
   method silently skips draft cancellation/playback pause (§2.2) and desyncs shell from engine.
   Mitigation is structural: the registry only ever calls shell methods; raw `_send` is not a
   registry primitive.
3. **Stuck momentary state.** If momentary keys are built: app backgrounded mid-hold never
   delivers keyUp → editor stuck in pan/eyedrop mode. Needs an explicit reset on focus/lifecycle
   loss. This risk is confined to the momentary sub-feature and is an argument for deferring it.
4. **Binding-file compat debt.** User bindings are a persistent contract; renaming a command id
   without migration silently drops a user's customization. Same failure class as journal verbs,
   lower stakes.
5. **OS-reserved and OEM-intercepted keys.** A user binds a combo the OS consumes and concludes
   the feature is broken. Blocklist plus a "this key may be reserved by your system" warning in
   the capture UI.
6. **Scope creep toward a generic command system.** "Every action configurable" gravitationally
   pulls toward command palettes, macros, and a refactor of all nine `editor_page` part files. The
   registry should stay a thin index over existing methods, not become a rewrite driver.
7. **Opportunity cost.** Medium + medium effort against a sliver audience (§5.1) competes with
   phone-majority features. The phased split (6.A first, 6.B on demand) is the hedge, not a fix.

## 8. Open questions

1. Is there any signal on how many users run the editor on iPad/tablet at all (store-listing
   device breakdowns may be the only proxy, absent analytics)?
2. Should the command registry be designed Animator-aware from the start (the `animator` branch
   would want the same layer), or strictly editor-local first?
3. Momentary keys in or out of the first credible version? (This analysis leans: out — most of the
   §7.3 risk, minority of the value.)
4. Does the iPad cheat-sheet overlay double as phone-facing documentation of gestures someday, or
   stay keyboard-only?
