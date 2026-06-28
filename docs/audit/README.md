# Makapix Club — Fresh-Eyes Code-Quality Audit

**Date:** 2026-06-27 · **Commit:** `f9878e1` · **Scope:** the whole repo (≈7.6k lines Rust engine + ≈7.8k lines Dart app)
**Lens:** *Are bad practices forming (early or widespread)? Where would a refactor buy real robustness / speed / quality?*
**Goal it's measured against:** a production-grade app with a first-class, robust, fast, streamlined animated pixel-art editor inside.

> Line numbers are as of commit `f9878e1`. Every **High**-severity finding in this report was read and confirmed against the source; mediums/lows are cited with file\:line so they can be checked in seconds.

---

## 1. Verdict

The codebase is in **good shape for its age**. The architecture is sound and several pieces are genuinely well-built: the COW tiled buffer, the deterministic primitives, the `.mkpx` reader's bounds discipline, the single-flight token refresh, PKCE/OAuth handling, and the thumbnail cache are all production-quality. The dependency discipline (zero-dep engine, `image` quarantined in `codec`) is real, not aspirational.

But there are **two classes of issue worth nipping now**, before they ossify:

1. **A small number of real robustness holes** where malformed input or a transient failure can crash, hang, or silently corrupt state. These are P0 because the app *ingests untrusted bytes* (downloaded/remixed Club artwork, opened files) and runs on Android where a 5-second stall is an ANR kill.
2. **A widespread set of "forming" bad habits** — two god-objects disguised as file splits, single-source-of-truth drift, swallowed errors, and full-canvas/full-tree work on hot paths — that are individually minor today but compound as the editor grows.

Nothing here requires a rewrite. The good patterns the codebase *already uses in some places* (optimistic-update+rollback, content-hash thumbnail invalidation, the `mod parse` seam, disciplined FFI buffer pairing) are exactly the patterns that fix the problems elsewhere. **The work is mostly "apply the good pattern uniformly," not "invent a new one."**

> ### Decisions recorded with the maintainer (2026-06-27)
> Four questions arising from this audit were resolved with the maintainer; the findings below already reflect them:
> 1. **App stage — private / internal testing.** A handful of testers; production may not exist yet. So the P0 cluster is *"fix before widening the tester pool / before public beta,"* not a live hotfix queue, and its blast radius today is small. This calibrates urgency throughout (especially F-8).
> 2. **Panic policy (F-4) — keep `panic = "abort"`.** Abort is the committed final policy. The "no panic crosses the boundary" guarantee will be delivered by *closing the reachable panics + an adversarial fuzz suite*, **not** by switching to `unwind` + `catch_unwind`.
> 3. **Editor decomposition (F-18) — plain `ChangeNotifier` controllers.** Keep `EditorPage` a self-contained `StatefulWidget`; do **not** pull the editor into Riverpod (the engine already owns document state, and provider indirection on the per-pointer-move hot path is exactly what F-9 removes).
> 4. **Determinism strictness (F-24) — open decision, deferred.** Do the no-regret cleanup now (fix the mislabeled comment; delete-or-wire the dead `Premul8` path); the strict-bit-identical-vs-per-platform-tolerant question is explicitly left for the team, with consequences spelled out in F-24.

---

## 1b. Implementation status (2026-06-27)

All three sprints were executed on branch `audit-hardening-and-refactor` (Rust suite 106 tests + the
new fuzz suite green throughout; `flutter analyze`/`flutter test` clean; Windows app and Android APK
both build). Status by finding:

**Done & verified**
- **Sprint 1 (robustness):** F-1, F-2, F-3, F-4 (fuzz suite added — it immediately caught a real
  `)(` parser panic, now fixed), F-5, F-6, F-7, F-8, F-28, F-29.
- **Sprint 2 (editor perf):** F-9, F-10, F-11, F-12 (export off the UI thread, isolate + sync
  fallback), F-13, F-14, F-15, F-16.
- **Sprint 3 (maintainability):** F-19 (autoDispose), F-20 (tool-behavior table), F-22 (API `guard`
  choke point), F-17 *(started — canvas transforms extracted to `session/canvas.rs`; the remaining
  domains follow the same proven seam)*.

**Deliberately deferred (do with on-device verification, not bundled pre-install)**
- **F-18** (extract editor `ChangeNotifier` controllers): its perf payoff was already delivered by
  F-9/F-10/F-11 in Sprint 2; the remaining work is pure cohesion refactoring of a UI with no
  widget-interaction tests, so it can only be compile-verified, not behavior-verified, in this batch.
- **F-21** (engine-authoritative tool params): a desync-sensitive change to the FFI state contract
  that needs runtime verification.
- **F-17 remainder** (pointer/layers/palette/preview submodules): mechanical, low-risk; continue the
  `session/canvas.rs` pattern.
- Polish items folded into "Continuous" (F-24 docs/dead-code, F-25, F-26, F-30 editor toasts, F-31,
  F-32, F-33) remain as the ongoing queue.

---

## 2. The eight cross-cutting themes

Individual findings are in §4. The synthesis — the patterns that show up across *multiple* subsystems and therefore deserve a deliberate decision — is here.

### T1 — "No panic crosses the FFI boundary" is documented but **false**
`crates/ffi/src/lib.rs` opens with *"No panics cross the boundary (errors are returned as strings / status codes)."* In reality:
- The workspace ships `panic = "abort"` in release (`Cargo.toml:15`), and there is **no `catch_unwind` anywhere** in `crates/` (verified: 0 matches). Under `panic = "abort"`, a panic does not unwind — it `SIGABRT`s the **entire Flutter process**, taking unsaved Club state with it.
- At least three panics are reachable *from FFI input*: a `NaN`/`inf` gradient stop (F-1), an out-of-range `.mkpx` id (F-2), and unchecked-index public getters (F-23).

The guarantee rests entirely on the engine being panic-free on adversarial input — which it currently is **not**. This is the single most important theme. **Decision: keep `panic = "abort"`** (F-4) — so the fix is to *make the engine genuinely panic-free* (validate at the parse/load boundary: F-1/F-2/F-28/F-29) and *prove it with an adversarial fuzz suite in CI*, then correct the doc comment to state the real contract ("the engine is panic-free on all inputs, enforced by fuzzing; a panic aborts the process by design"). See F-1..F-4.

### T2 — Untrusted-input hardening is **inconsistent**
The `.mkpx` *reader* is genuinely defensive (bounds-checked `Reader`, frame/layer/tile caps, RLE run limits). But the same rigor is missing right next door: the codec checks dimensions *after* fully decoding (bomb, F-3), the id generator trusts id *values* (F-2), pointer coords are unclamped (F-6), gradient `t` accepts `NaN`/`inf` (F-1), there are no Dio timeouts (F-7), and a secure-storage read can throw and brick startup (F-5b). **Decide that every trust boundary validates, and close the gaps.**

### T3 — Two **god-objects**, both papered over by cosmetic file-splitting
- `session.rs`: one `impl Session` block, ~1700 non-test lines, spanning eight unrelated domains (input routing, per-tool raster, undo bookkeeping, structural edits, palette CRUD, canvas transforms, preview rendering, IO). CLAUDE.md noted it at ~1700; it's now 2318 total.
- `_EditorPageState`: ~50 mutable fields on one State, split across six `part` files whose extensions each carry `// ignore_for_file: invalid_use_of_protected_member` to reach `setState`. The split is explicitly cosmetic ("keep each file under ~400 lines") — every part can mutate every field; there is no enforced boundary or cohesive invariant.

Splitting a file is not the same as decomposing a responsibility. Both want extraction into **types that own their own invariants** (Rust submodules à la the existing `mod parse`; and for the editor, plain Dart `ChangeNotifier` controllers — *not* Riverpod, by decision; see F-18). See F-17, F-18.

### T4 — **Full-canvas / full-tree work on hot paths** (the "fast editor" tax)
The editor repeatedly does O(canvas) or O(widget-tree) work where it should do O(changed):
- **Dart:** full-tree `setState` + a per-tile FFI `frameHash`/`layerHash` round-trip + an outline FFI refetch + an O(w·h) outline rescan, **on every pointer move** (F-9, F-11); an undisposed `ui.Image` orphaned every 33 ms during playback (F-10); export/import/save/load run **synchronously on the UI thread** (F-12).
- **Rust:** the compositor walks every pixel ignoring absent tiles and re-composites onion neighbors on every refresh (F-13); `gradient_color_at` clones+sorts the stop vector **per pixel** (F-14); `draw_tool_preview` scans the whole canvas on every `display()` (F-15); undo compaction is O(n²) (F-16).

This is the headline *efficiency* opportunity and it maps directly onto "fast, streamlined." See F-9..F-16.

### T5 — **Single-source-of-truth drift** (behavior re-encoded in N places)
The same fact is written down in multiple places that must be hand-synced:
- Per-tool behavior (Pencil→Replace, Brush→Over…) is re-encoded in **3–4** `match self.tool` blocks, and "does this tool commit an undo record?" lives in **two** separately-maintained tool lists (F-20).
- Tool params are mirrored in ~14 Dart fields and **re-pushed to the engine on every tool switch**, while palette/primary-color are read *from* the engine — split ownership that silently desyncs (F-21).
- `DioException → ClubError` try/catch is copy-pasted in ~20 API methods (F-22); bounds-accumulation 3×; the transform-loop skeleton 5×; combine-mode parsing 2×; the FFI copy-out 4×.

Each duplication is a future bug waiting for someone to edit one copy and miss another. **Centralize each into one table/helper.**

### T6 — **Errors are swallowed**, so the app degrades invisibly
Failures vanish instead of surfacing: editor DSL errors go to `debugPrint` (invisible in release), state-parse is wrapped in empty `catch (_) {}`, `engine.load()` return is ignored in `initState` (silent loss of the user's work to a blank canvas); comment like/delete is `catch (_) {}`; OAuth maps *every* failure to "cancelled"; `serverConfig`/`licenses` cache the failure path forever; and the forced-logout path (F-4b) never tells the auth controller. The user sees a frozen spinner or a silently-reverted action, never a cause. See F-4b, F-5, F-24, F-25.

### T7 — The **determinism invariant** has an undocumented float dependence and a dead premultiply path
SPEC says "integer-exact, premultiplied internally." In fact `lerp_srgb` is float math *and is mislabeled* `/// Integer-exact`; ellipse/circle/polygon rasterizers use `f32`; and the `Premul8`/`to_premul`/`from_premul` type is **dead code** — the compositor blends in straight-alpha space. Cross-platform golden stability currently holds only because Rust emits non-contracted IEEE ops; a future `mul_add`/fast-math flag could silently fork goldens. **Make the docs match reality now** (fix the mislabeled `/// Integer-exact` comment; delete-or-wire the dead `Premul8` path) — those are no-regret. Whether to go further and pin/convert the float ops (no FMA/transcendentals, or fixed-point) **depends on an open team decision** on strict-vs-tolerant goldens. See F-24.

### T8 — Resource & lifecycle discipline is **excellent in places, absent in others**
The codebase already demonstrates the right patterns — they're just not applied uniformly. Thumbnails are disposed meticulously; the main canvas image isn't (F-10). The `.mkpx` FFI buffers are perfectly paired with frees; the codec isn't limit-guarded (F-3). Riverpod optimistic-update+rollback is textbook in reactions/follows; comments do blanking reloads with swallowed errors (F-25) and **nothing** auto-disposes (F-19). The fix for the weak spots is to copy the strong spots.

---

## 3. Priority table

Severity: **High** = can crash / hang / lose data / leak in normal-ish use · **Medium** = real perf or maintainability cost · **Low** = polish / latent.
✓ = personally verified against source during this audit.

> **Stage calibration:** the app is in **private / internal testing**, so "P0" here means *"before widening the tester pool / before public beta,"* not "live-production hotfix." The items are still worth doing now — they're cheap and they protect current testers from crashes and lost work.

| # | Finding | Sev | Where |
|---|---------|-----|-------|
| **P0 — Robustness (crash / DoS / data-loss / security)** ||||
| F-1 ✓ | `NaN`/`inf` gradient stop → `partial_cmp().unwrap()` → **process abort** | High | `tool.rs:253`, `parse.rs:287` |
| F-2 ✓ | Untrusted `.mkpx` frame/layer id → `0..=id` loop (≤4.3B iters) → ANR/DoS | High | `io.rs:295-300` |
| F-3 ✓ | Codec decodes full image / **all** frames *before* the size check; no frame-count cap → decompression bomb | High | `codec/src/lib.rs:60-91` |
| F-4 ✓ | "No panic crosses the boundary" false: `panic=abort` + no `catch_unwind` | High | `Cargo.toml:15`, `ffi/src/lib.rs:1-3` |
| F-4b ✓ | Failed refresh wipes tokens but never signals `AuthController` → **zombie signed-in** UI | High | `club_api_client.dart:42`, `auth_controller.dart:71-85` |
| F-5 | Secure-storage read can throw in fire-and-forget `init()` → app stuck on spinner forever | Med-High | `auth_controller.dart:62-69`, `token_store.dart:14-20` |
| F-7 | No Dio timeouts anywhere → requests hang indefinitely; `isTimeout` branch is dead | Med | `club_api_client.dart:14`, `club_session.dart:23` |
| F-8 | Release build hard-coded to the **dev** server | Med | `club_config.dart:12-13` |
| **P1 — Performance (jank / leak on hot paths)** ||||
| F-9 ✓ | Full-tree `setState` + per-tile FFI hash calls on **every pointer move** | High | `engine.dart:171`, `canvas.dart:198`, `timeline.dart:52` |
| F-10 ✓ | Composited canvas `ui.Image` never disposed (30 fps churn + pause-race leak) | High | `engine.dart:170,180`; `dispose` `editor_page.dart:223` |
| F-11 | Selection outline FFI-refetched + O(w·h) rescanned every redraw | Med | `engine.dart:160-172` |
| F-12 | Export/import/save/load run **synchronously on the UI thread** | Med | `fileio.dart:95,118` |
| F-13 | Compositor walks every pixel ignoring absent tiles; re-composites onion neighbors each refresh | Med | `render.rs:11-29,49-96` |
| F-14 | `gradient_color_at` clones + sorts the stop vector **per pixel** | Med | `tool.rs:252-253` |
| F-15 | `draw_tool_preview` scans the whole canvas on every `display()` | Med | `session.rs:273-314` |
| F-16 | Undo compaction is O(n²) (full stack scan per edit); `Vec::remove(0)` is O(n) | Med | `history.rs:69-91` |
| **P2 — Maintainability (bad habits forming)** ||||
| F-17 | `session.rs` god-file: one ~1700-line impl across 8 domains | Med | `session.rs` |
| F-18 | `_EditorPageState` god-object: ~50 fields, 6 part-extensions suppress the protected lint | Med | `editor_page.dart:57-139` |
| F-19 ✓ | **Zero** `autoDispose`/`keepAlive` in the app → unbounded provider growth (esp. per-query search) | High | `feed/profile/post/search providers` |
| F-20 | Per-tool behavior duplicated 3–4× + 2 hand-synced undo-commit lists | Med | `session.rs:480-512,600-645,728-730` |
| F-21 | Tool params double-sourced (Dart mirror vs engine) → desync; duplicate sel-mode fields | Med | `engine.dart:247-255` |
| F-22 | `DioException→ClubError` try/catch copy-pasted ~20× | Low | `api/*.dart` |
| F-25 | Pagination races: `refresh`/`loadInitial` skip the in-flight guard; no generation token; no dedup | Med | `paged.dart:50-83` |
| F-24 | Determinism: `lerp_srgb` mislabeled "integer-exact" + float shapes + dead `Premul8` path | Med | `color.rs:67-141`, `tool.rs`, `raster.rs` |
| **P3 — Polish / latent** ||||
| F-26 | `content_hash` is sensitive to present-but-transparent tiles → breaks bytes round-trip | Med | `buffer.rs:168-185,371-401` |
| F-27 | Data-owning constructors (`Document::new`, `RgbaBuffer::new`) don't enforce size invariants | Low | `document.rs:136`, `buffer.rs:53` |
| F-28 | Unchecked indexing in public read API (`pixel`, `layer_hash`) | Low | `session.rs:374-379` |
| F-29 | Mid-stroke `SetActiveLayer`/`SetActiveFrame` can record an undo patch on the wrong layer | Med | `session.rs:415-426,454,616` |
| F-30 | Swallowed errors throughout (debugPrint / empty catch / all-OAuth→"cancelled" / cached failure) | Med | editor + club, see §4 |
| F-31 | Marching-ants `AnimationController` repaints forever even with no selection | Low | `editor_page.dart:175`, `painters.dart:63` |
| F-32 | Deprecated `Color.red/.green/.blue/.alpha` on SDK 3.12 + duplicated hex helpers | Low | `engine.dart:144`, `controls.dart:494`, `color_picker_dialog.dart:38` |
| F-33 | Misc: magic numbers/dead tooltips, `ok_or` eager alloc, inconsistent null-param idioms, `isExpired` dead, `state_json` under-escaping | Low | see §4 |

---

## 4. Detailed findings

Each finding: **what**, **evidence**, **why it matters**, **recommendation**.

### Rust engine & boundary

#### F-1 (High) — `NaN`/`inf` gradient stop panics across the FFI boundary
`gradient_color_at` sorts stops with `s.sort_by(|a, b| a.t.partial_cmp(&b.t).unwrap())` (`tool.rs:253`). The DSL parser reads each stop's `t` with `t.trim().parse::<f32>()` (`parse.rs:287`), and Rust's `f32::FromStr` **accepts `"NaN"`, `"inf"`, `"-inf"`**; `Stop::new`'s `t.clamp(0.0,1.0)` returns `NaN` unchanged. A parseable line like `SetGradientStops(#000000FF@NaN,#FFFFFFFF@1.0)` followed by any gradient render (or even the live preview `gradient_eval` in `draw_tool_preview`) makes `NaN.partial_cmp(..) == None` → `unwrap()` → **panic → `SIGABRT` of the whole app** (T1). The same unguarded `f32a` parser feeds HSV and durations.
**Recommendation:** reject non-finite `t` in `parse_stops`/`Stop::new` (`if !t.is_finite()`), make the sort total (`sort_by(|a,b| a.t.total_cmp(&b.t))`), and apply `is_finite` to the other `f32a` args. ~5 lines; closes a whole panic class.

#### F-2 (High) — Untrusted `.mkpx` id drives an unbounded `0..=id` loop (DoS)
After reading frames, the loader rebuilds the id generators with `for _ in 0..=max_frame_id { frame_ids.alloc(); }` (and the same for layers) at `io.rs:295-300`, where `max_frame_id` is the **max of the raw `r.u32()` id values**. Frame/layer *counts* are capped (`MAX_FRAMES`/`MAX_LAYERS`) but the id *value* is not. A ~30-byte crafted file with one frame whose id = `0xFFFFFFFF` forces ~4.3 billion `alloc()` iterations — a multi-second hang (Android ANR) reachable straight from `mkpx_load`.
**Recommendation:** don't loop to rebuild generators — seed them directly, e.g. add `IdGen::starting_at(max_frame_id.saturating_add(1))`, or reject ids above a sane bound.

#### F-3 (High) — Codec checks size *after* decoding; no frame cap (decompression bomb)
`decode_static` does `image::load_from_memory(bytes)?.to_rgba8()` and *then* `if w > MAX_DIM || h > MAX_DIM` (`codec/src/lib.rs:60-65`) — the allocation already happened, so the guard never prevents the bomb. `decode_animated` is worse: `into_frames().collect_frames()` eagerly decodes **all** frames into memory before any check, with **no frame-count cap** (`:70-79`). Reachable via `mkpx_import` on downloaded/remixed Club artwork.
**Recommendation:** use `image`'s `Limits` API (`set_limits` with `max_image_width/height` + `max_alloc`) on a configured decoder so over-limit input fails *during* decode; read header dimensions before materializing pixels; add an explicit frame-count cap before/within `collect_frames`.

#### F-4 (High) — The panic-safety guarantee is unenforceable as built
`panic = "abort"` (`Cargo.toml:15`) + zero `catch_unwind` (verified) means the FFI doc's promise ("no panics cross the boundary") cannot hold: a panic aborts the process. The FFI crate's *own* code is panic-clean (all `unwrap` are `#[cfg(test)]`), so the guarantee depends entirely on the engine never panicking on any input — which F-1/F-2/F-28/F-29 violate.
**Decision: keep `panic = "abort"`** as the committed policy. **Recommendation:** deliver the guarantee by (1) closing every reachable panic — F-1 (gradient), F-2 (id loop), F-28 (unchecked getters), F-29 (stroke target) — and (2) adding an adversarial fuzz/regression suite that drives `mkpx_run`/`mkpx_load`/`mkpx_import` with malformed input to *prove* panic-freedom in CI. Then fix the doc comment to state the real contract: *"the engine is panic-free on all inputs (enforced by fuzzing); a panic aborts the process by design."* (Switching to `panic = "unwind"` + `catch_unwind` was considered and **declined** — `abort` keeps the binary small and the failure mode honest; the cost is that the guarantee rests on fuzz coverage rather than a runtime net, so the fuzz suite is not optional.)

#### F-13 (Med) — Compositor ignores the COW structure it sits on
`composite_frame` (`render.rs:11-29`) calls `layer.pixels.get(x,y)` + `out.get/set` per layer per pixel — each recomputing the tile index (two divs + two mods + bounds check). A mostly-empty layer (the common pixel-art case) still pays a full `get` for every pixel of every *absent* tile. `render_display` compounds it by re-running `composite_frame` inside `blit_onion` for each neighbor on every refresh.
**Recommendation:** iterate tile-by-tile, skip `None` source tiles wholesale, and composite within a present tile via direct slice indexing. Cache onion-neighbor composites keyed by frame content-hash. This is the biggest engine-side perf win and aligns with the existing COW design.

#### F-14 (Med) — Per-pixel allocation in the gradient fill
`gradient_color_at` runs `let mut s = stops.to_vec(); s.sort_by(...)` *inside* the per-pixel function (`tool.rs:252-253`). A 256×256 gradient does 65,536 vector clones + sorts of identical data — and the live preview does it every frame.
**Recommendation:** pre-sort once in the `apply_gradient`/`gradient_eval` callers and have `gradient_color_at` assume sorted input.

#### F-15 (Med) — Full-canvas preview scan on every display refresh
With the `SelectLayer` or mid-stroke `Gradient` tool active, `display_bytes` runs a full `for y { for x { ... } }` tiled scan (`session.rs:273-314`) every UI frame (~60/s) purely to tint the overlay.
**Recommendation:** restrict the scan to `layer.pixels.opaque_bounds()` (SelectLayer) / the affected rect (Gradient), or cache the overlay mask and invalidate on edit.

#### F-16 (Med) — O(n²) undo compaction
`frame_depth` (`history.rs:69-71`) is `self.undo.iter().filter(...).count()` — a linear scan of the whole undo vector (cap 8192) — and it's evaluated as the `while` condition on **every** recorded edit, even far below cap. N edits ≈ O(N·undo.len()). The global-cap path also uses `Vec::remove(0)` (O(n) shift).
**Recommendation:** keep a `HashMap<frame_id, count>` updated incrementally (O(1) cap check); switch the undo stack to `VecDeque` for O(1) front-pop.

#### F-17 (Med) — `session.rs` god-file
One `impl Session` owns pointer routing (454-733), per-tool raster helpers (833-894), precision mode (896-987), selection/clipboard (989-1132), frame/layer ops (1134-1448), canvas transforms (1450-1595), palette CRUD (1597-1642), and preview/thumbnails (219-372).
**Recommendation:** `mod parse` already proves the seam is frictionless (`impl Session` in its own file). Split into `session/pointer.rs`, `session/layers.rs`, `session/canvas.rs`, `session/palette.rs`, `session/preview.rs`; keep the struct, `new`, and undo helpers in `session.rs`. Low-risk, high-readability.

#### F-20 (Med) — Per-tool behavior duplicated; two hand-synced commit lists
The "Pencil→Replace, Brush→Over, Eraser→Erase…" mapping is re-encoded in three pointer handlers plus `cursor_paint`, and "does this stroke commit an undo record?" is decided by **two** separate manually-synced lists (`is_pixel_tool` at 636-645 and the `matches!(…Gradient|Line|…)` at 728-730). Adding a pixel tool requires editing all of these in lockstep; missing one silently bakes an un-undoable edit.
**Recommendation:** centralize on `ToolKind` (`fn paint_mode(self) -> Option<PaintMode>`, `fn writes_pixels(self) -> bool`). Better: make `record_pixels` skip empty patches, then always `commit_edit` after a stroke and delete both lists.

#### F-24 (Med) — Determinism docs vs. reality
`lerp_srgb` (`color.rs:133`) carries `/// Integer-exact` above a float body; shapes use `f32`; `Premul8`/`to_premul`/`from_premul` (`color.rs:67-96`) are **dead** (referenced only in their own unit test) while the compositor blends straight-alpha. The "premultiplied internally / integer-exact" invariant is partly fiction; golden stability is currently luck-of-codegen.
**Recommendation (no-regret, do now):** fix the mislabeled `/// Integer-exact` comment on `lerp_srgb`, and either delete the dead `Premul8` path or wire the compositor through it. **Open decision (deferred to the team):** whether goldens must be strictly bit-identical across Windows/Android/iOS. *If strict* → pin the f32 ops ("no FMA/transcendentals, determinism depends on it") or convert the simple ones (e.g. `lerp_srgb`) to fixed-point. *If per-platform tolerance is acceptable* → no code change needed, just document the tolerance. The latent risk (a future `mul_add`/fast-math flag silently forking goldens) exists **only under the strict interpretation** — so make the call explicitly rather than leaving it implicit, as SPEC §25 currently asserts strictness while the code does not deliver it.

#### F-26 (Med) — `content_hash` reflects materialization state, not visible pixels
`content_hash` (`buffer.rs:168-185`) hashes every *present* tile with no all-transparent check, so a tile drawn-then-erased (present until `compact()`) hashes differently from a fresh-empty buffer. Concretely `from_rgba_bytes(to_rgba_bytes(b))` does **not** round-trip the hash when `b` holds a present-but-transparent tile (`to_rgba_bytes` emits all pixels; `from_rgba_bytes` only `set`s `a != 0`). The engine leans on this hash for `assert.roundtrip`/`hash` oracles and Dart leans on it for thumbnail-cache invalidation.
**Recommendation:** treat an all-transparent present tile as absent in `content_hash` (reuse the existing `Tile::is_all_transparent`).

#### F-27 / F-28 / F-29 (Low–Med) — Invariants live in callers, not types
`Document::new`/`RgbaBuffer::new` accept any dimensions and never consult the existing `Size::in_range` (8..=256) — the 8×8–256×256 invariant is enforced only by convention (F-27). `pixel()`/`layer_hash()` use unchecked `frames[f].layers[l]` indexing in the **public** read API (F-28) — a stale index over FFI panics across the boundary. `begin_edit`/`commit_edit` snapshot and diff `active_frame().active_layer()` without pinning the layer, so a DSL `…PointerDown; SetActiveLayer(1); PointerUp` records the diff against the *wrong* layer (F-29).
**Recommendation:** clamp/validate in the data-owning constructors; make the public getters bounds-safe (clamp or `Option`); capture `(fid,lid)` in `begin_edit` and resolve against those ids in `commit_edit` (the `frame_index_by_id`/`layer_index_by_id` helpers already exist), and reject/auto-finalize active-target changes mid-stroke.

#### F-33 (Low) — Small Rust hygiene
`ok_or(format!(...))` allocates on the parser *success* path (use `ok_or_else`, `parse.rs:313-338`); combine-mode parsing duplicated (`parse.rs:395-416`); bounds-accumulation copy-pasted 3× (`buffer.rs:202-271`, `selection.rs:105-122`); the transform-loop skeleton 5× (flip/rotate/resize/crop in `session.rs`); `state_json` escapes only `"` so a layer name with `\` yields invalid JSON (`probe.rs:72,98`); the unused `#[allow(dead_code)] borrow_str` in `ffi/lib.rs:353`; FFI copy-out duplicated 4× (extract `copy_out(bytes,out,cap)`); `mkpx_load`/`mkpx_import` collapse rich `IoError`/`CodecError` to `-1`.

### Flutter editor

#### F-9 (High) — Full-tree rebuild + per-tile FFI on every pointer move
`_redraw()` ends with `setState(() {})` (`engine.dart:171`) and is called from `_continueDraw` on **every** `PointerMove` (`canvas.dart:198`). That re-runs the whole `build()` Column, and inside it the film-roll `itemBuilder` calls `engine.frameHash(i)` per visible frame and `_buildLayers` calls `engine.layerHash(frame,i)` per layer — an FFI round-trip *per tile, per move*, plus an active-frame thumbnail regen. This is the dominant draw-time jank source.
**Recommendation:** drive the four overlays (outline / reticle / shape handles / ruler) off their own `ValueListenable` + dedicated `CustomPaint` (the canvas image already does exactly this), and drop the per-move `setState`. The film-roll and layer strip must not rebuild mid-stroke.

#### F-10 (High) — Canvas `ui.Image` leaks
`_imageVN.value = img` (`engine.dart:170`) replaces the previous GPU-backed `ui.Image` **without `.dispose()`** — ~30 orphaned images/sec during playback. In `_advancePlayFrame` (`:176-181`), if playback paused/unmounted during the `await _decode`, the freshly decoded `img` is neither assigned nor disposed (a guaranteed per-pause leak). `dispose()` frees the notifier, not the image it holds (`editor_page.dart:223`). (Thumbnails, by contrast, are disposed carefully — the pattern to copy.)
**Recommendation:** capture and `oldImage?.dispose()` before each assignment; dispose `img` when not assigned in `_advancePlayFrame`; dispose `_imageVN.value` in `dispose()`. Same gap for the import preview `srcImg` and the `_decodeBytes` codec.

#### F-11 / F-12 (Med) — Outline rebuilt every paint; heavy ops block the UI thread
Every `_redraw` calls `_updateOutline()` → `engine.outlineMask()` (`malloc(w*h)` + FFI + copy) and, when a selection exists, an O(w·h) rescan building a fresh `List<List<int>>` (`engine.dart:160-172`) — even while just drawing with the Pencil (F-11). `engine.exportGif()/importImage()/save()/load()` are blocking FFI on the platform thread (`fileio.dart:95,118`); a multi-frame 256² GIF export will jank/ANR (F-12).
**Recommendation:** refetch the outline only when the selection version/hash changes, not every move. Move one-shot heavy ops off the UI thread (`Isolate.run` with a transferable byte buffer) and show progress; at minimum gate the buttons during the op.

#### F-18 (High-as-refactor) — `_EditorPageState` god-object
~50 loose fields (shape draft, ruler, playback, view transform, palette, thumbnails, touch state, tool params, Club provenance) on one State, reached from six `part`-file extensions that each suppress `invalid_use_of_protected_member` to call `setState` (`editor_page.dart:57-139`). No encapsulation; the split is cosmetic.
**Recommendation:** extract cohesive controllers with their own invariants + change-notification — `ShapeDraft`, `RulerState`, `ViewTransform`, `PlaybackController`, `ThumbnailCache` — as plain **`ChangeNotifier`s**, with `EditorPage` staying a self-contained `StatefulWidget`. **Deliberately not Riverpod** (decided): the engine already owns document state, and provider indirection on the per-pointer-move path is exactly the overhead F-9 removes; `ChangeNotifier` + `ValueListenableBuilder` gives the same targeted-rebuild win with a far smaller blast radius and keeps the editor's hot loop self-contained. This is the highest-leverage editor refactor and it *unlocks* the targeted-rebuild fix (F-9).

#### F-21 (Med) — Tool params are a second source of truth
`_selectTool` re-pushes ~14 Dart fields (`_brushSize`, `_threshold`, `_contiguous`, `_intensity`, …) to the engine on every tool switch (`engine.dart:247-255`), treating Dart as authoritative; meanwhile `_refreshState` reads palette/primary-color *from* the engine. Any engine-side DSL path that changes one of these silently desyncs the mirror. There are also two near-identical selection-mode fields (`_selMode`, `_selLyrMode`).
**Recommendation:** pick one owner — cleanest is engine-authoritative: expose tool params in `state_json` and read them back, dropping the Dart mirrors/re-push. Collapse the duplicate sel-mode fields.

#### F-30 (Med, editor slice) — Swallowed engine/load errors
`_send` reduces every DSL failure to `debugPrint` (invisible in release, `engine.dart:157`); `_refreshState` wraps its parse in empty `catch (_) {}` (`:201`) so malformed state freezes the UI on stale data; `initState` ignores `engine.load(snap)`'s bool (`editor_page.dart:183`), so a snapshot that fails to restore silently drops the user's work to a blank 64×64 — even though `_open` *does* check the same return.
**Recommendation:** surface engine/DSL/parse failures (toast + telemetry); check `engine.load(snap)` in `initState` and toast on failure.

#### F-31 / F-32 / F-33 (Low, editor) — Polish
The marching-ants `AnimationController` `..repeat()`s for the editor's whole life with `shouldRepaint => true`, repainting at vsync even with no selection/overlay active (F-31) — stop/start it on overlay presence. Deprecated `Color.red/.green/.blue/.alpha` on SDK 3.12 with duplicated hex helpers (F-32) — centralize one `colorToHex`/`hexToColor` using `toARGB32()`. Misc (F-33): drag-state `int` 4-state machines (`_shapeDrag`/`_rulerDrag` `0/1/2/3` — make an `enum DragKind`), `_layerKey => frame*100000+layer` magic multiplier, raw hex panel colors + bar heights duplicated across files (lift to `_EditorTheme` tokens), dead `SelectCircle`/`SelectPoly` tooltips, the `['Replace','Add','Subtract','Intersect']` literal rebuilt 4×, and `_act` triggering two rebuilds (one with the stale image).

### Flutter Club & shell

#### F-4b (High) — "Zombie signed-in" after a failed refresh
When `session.refresh()` fails, `_doRefresh` calls `clear()` (wipes tokens) and the interceptor does `handler.next(e)` surfacing the 401 (`club_api_client.dart:42`). But **only** `AuthController._loadMe` reacts to `e.isAuth` (`auth_controller.dart:76`). A failed refresh triggered while scrolling a feed/opening a post just shows "Failed to load" — `AuthState` stays `signedIn`, so the UI keeps rendering signed-in while every request now fails (no token). It self-heals only on app restart.
**Recommendation:** give `ClubSession.clear()` a "session-invalidated" signal (callback / `ValueNotifier` / `Stream`); have `AuthController` listen and flip to `signedOut`. (The single-flight refresh mechanism itself, `club_session.dart:58-66`, is correct — leave it.)

#### F-5 (Med-High) — Startup can brick on a secure-storage throw
`init()` does `await session.load()` with no try/catch (`auth_controller.dart:62-69`), and it's invoked fire-and-forget (`..init()`). On Android, `flutter_secure_storage` can throw `PlatformException` (Keystore reset after an OS/key change); the unhandled async error leaves `AuthState` stuck at `loading` → `ClubHomePage` shows a spinner **forever**.
**Recommendation:** wrap `load()` (or the `store.read()` loop) in try/catch; on failure treat as signed-out (optionally `clear()` the corrupt entry) so the app degrades to the welcome funnel.

#### F-7 (Med) — No request timeouts
None of the three Dio instances (authed client, grant client, artwork-download client) set `connectTimeout`/`receiveTimeout`/`sendTimeout` (`club_api_client.dart:14`, `club_session.dart:23`, `edit_api.dart:11`). Dio defaults to no timeout, so a stalled connection (captive portal, dead server) hangs forever; the `isTimeout` branch in `club_error.dart` is effectively dead code.
**Recommendation:** set 15–30 s timeouts on all three `BaseOptions`; bound the download response size.

#### F-8 (Med) — Release ships pointing at dev
`static const ClubConfig defaultConfig = ClubConfig(ClubEnvironment.dev)` and `clubConfigProvider` returns it unconditionally (`club_config.dart:12-13`). A release build talks to `development.makapix.club` unless someone edits source.
**Stage note:** in private/internal testing this is intentional (only the dev server is in use), so it is **not urgent now** — but wire it before the prod cutover / public beta so a release can't ship to the wrong server by omission. **Recommendation:** select env from `String.fromEnvironment`/`bool.fromEnvironment` (`--dart-define`), `dev` local-default, `prod` for release.

#### F-19 (High) — Nothing auto-disposes
Global grep for `autoDispose|keepAlive|onDispose` across `app/lib` = **0 matches** (verified). Every `.family` provider keyed by runtime values is kept alive forever: `postDetailProvider`/`reactionsProvider`/`commentsProvider` (per postId), `profileProvider` (per sqid), `hashtagFeedProvider`/`ownerFeedProvider`, and especially the three search `FutureProvider.family<…,String>` — one cached entry **per query string ever typed**.
**Recommendation:** make the transiently-reached families (`detail`, `profile`, `hashtag`, `search`, `comments`, `reactions`) `.autoDispose`; keep the home feeds alive *deliberately and documented* if cross-nav scroll retention is intended.

#### F-25 (Med) — Pagination races & comment-thread thrash
`loadMore` guards `if (state.loading || state.atEnd)`, but `refresh()`/`loadInitial()` don't (`paged.dart:50-83`). Pull-to-refresh during an in-flight `loadMore` runs two concurrent loads; a late `loadMore` appends page-2 items (old cursor) onto the refreshed list → interleaved items + a cursor into the stale sequence. No generation token to discard stale responses; no dedup-by-id on append. Separately, `CommentsController.add/delete/toggleLike` each call `load()` which sets `AsyncValue.loading()` and re-GETs the whole thread — liking one comment blanks the list — and `delete`/`toggleLike` are wrapped in `catch (_) {}` (`post_providers.dart:144-182`).
**Recommendation:** add a monotonic generation counter (ignore stale responses); have `refresh`/`loadInitial` supersede an in-flight `loadMore`; dedup appended items by id. Make comment like/delete optimistic+local with rollback (the reaction/follow controllers already do this) and surface failures.

#### F-30 (Med, club slice) — More swallowed errors
GitHub OAuth maps *all* `authenticate()` exceptions to "cancelled" (`github_oauth.dart:44-46`), masking a missing browser or scheme-registration bug. `serverConfig`/`licenses` are non-autoDispose `FutureProvider`s that `catch (_)` → fallback, so one transient failure caches a degraded result (empty license list → publish page shows none) for the whole session (`publish_providers.dart:15-29`). A refresh response that omits a rotated `refresh_token` throws `parse_error` → forced logout (`auth_tokens.dart:17-25`).
**Recommendation:** distinguish OAuth user-cancel from real errors; make config providers `autoDispose`/retryable; on the refresh path fall back to the existing refresh token when the response omits one.

#### F-22 / F-33 (Low, club) — Boilerplate & inconsistency
`try { … } on DioException catch (e) { throw ClubError.fromDio(e); }` is copy-pasted in ~20 API methods — add one `guard<T>(Future<T> Function())` choke point (or typed `getJson`/`postJson`) on `ClubApiClient`. Four different idioms coexist for "omit null query params" (`feed_api.dart:14`, `profile_api.dart:56`, `notifications_api.dart:14`, `search_api.dart:18`) — standardize on the null-aware-element style. `AuthTokens.isExpired` is defined with a "proactive refresh" doc but never called — wire it into `onRequest` or delete it.

---

## 5. What's already done well (don't "fix" these)

- **COW tiled buffer** (`buffer.rs`): `Arc<Tile>` + lazy alloc + `Arc::make_mut` + `diff_from` via `Arc::ptr_eq || x == y` is a genuinely good design — Arc-cheap snapshots, exact undo diffs. Pinned by `cow_diff_detects_only_changed_tiles`.
- **Deterministic primitives** (`util.rs`, `color.rs`): xoshiro256\*\* seeded through SplitMix64; the round-to-nearest `mul255` (`a*b+128; (t+(t>>8))>>8`); the streaming hasher proven to match the one-shot. Clean, dependency-free, tested.
- **The `.mkpx` reader's bounds discipline** (`io.rs`): every multibyte read is bounds-checked; frame/layer counts capped; `nt == num_tiles()` enforced; RLE runs hard-bounded with `run==0`/overflow rejection. (Just close the id-loop gap, F-2.)
- **FFI memory ownership** (`ffi/lib.rs`): every buffer/string handed to Dart has exactly one matching free; `Box`/`CString` into/from-raw correctly paired; all frees null-check; production paths have no `unwrap`. No leaks/double-frees on the Rust side.
- **Dependency discipline is real:** engine has zero deps and no `build.rs`; `image::` appears only in `codec`; the CLI pulls only `engine`; `image` is pinned `default-features = false` with a minimal pure-Rust format set (Android-friendly).
- **Single-flight token refresh** (`club_session.dart:58-66`): coalesces concurrent callers into one `_refreshing` future with no await between null-check and assignment, cleared via `whenComplete`, using a *separate interceptor-free* Dio so a refresh can't recurse; `__retried` guards the loop.
- **PKCE/OAuth is textbook:** `Random.secure()`, 64-byte verifier, `BASE64URL_NOPAD(SHA256(verifier))`, strict `state` CSRF check. No sensitive logging anywhere in `club/` (verified).
- **Defensive, null-tolerant `fromJson`** throughout `models/`, plus a solid normalized `ClubError` (v1 envelope, FastAPI `detail`, bare strings, transport, `Retry-After`).
- **Thumbnail cache** (`editor_page.timeline.dart`): content-hash invalidation, in-flight de-dup, post-`await` `mounted` checks, bounded eviction with explicit `img.dispose()`. **This is the exact discipline F-10 needs for the main canvas image.**
- **Playback canvas isolation** (`canvas.dart`/`engine.dart`): pushing frames through `ValueNotifier<ui.Image?>` in a `RepaintBoundary` to avoid `setState` on the 30 fps tick is the right call — the *draw* path (F-9) just needs to adopt the same pattern.
- **Architectural keystones hold:** the one-pillar-mounted shell + `.mkpx`-snapshot-on-dispose survival, the race-free Club→editor edit bridge, and the narrow string-and-bytes FFI seam are all correctly implemented and well-commented.

---

## 6. Recommended sequencing

A pragmatic order — robustness first (it's small and protects users now), then the perf wins (they're the "fast editor" promise), then the structural refactors (they prevent the next year of bugs).

**Sprint 1 — Robustness hardening (small, high-value; mostly < 10 lines each).** Given the private/internal-testing stage, this is the *"before widening the tester pool / before public beta"* queue rather than a live hotfix — but the items are cheap and they protect current testers now.
F-1 (NaN gradient) · F-2 (id loop) · F-3 (codec limits + frame cap) · F-4b (zombie auth signal) · F-5 (init try/catch) · F-7 (Dio timeouts) · F-28/F-29 (bounds-safe getters, pin stroke target). F-4 policy is **settled (keep `abort`)**: once the reachable panics are closed, add the adversarial fuzz suite over `mkpx_run`/`load`/`import` to keep them closed in CI — this is the load-bearing part of the guarantee, so don't skip it. F-8 (env via `--dart-define`) is intentional-for-now but wire it before the prod cutover. *Outcome: malformed input and transient failures can no longer crash, hang, or brick the app.*

**Sprint 2 — Editor performance (the "fast, streamlined" promise).**
F-10 (image disposal — do this first, it's a leak) · F-9 (overlays off `setState`, no per-move tile-hash FFI) · F-11 (outline only on selection change) · F-12 (heavy ops off the UI thread). Then the engine-side: F-13 (tile-skipping compositor + onion cache) · F-14 (pre-sort stops) · F-15 (bounded preview scan) · F-16 (O(1) undo cap). *Outcome: smooth drawing and playback at 256², no GPU-image churn, no export ANR.*

**Sprint 3 — Decompose the god-objects & kill SSOT drift.**
F-18 (extract editor **`ChangeNotifier`** controllers, editor stays a `StatefulWidget` — this unlocks F-9 cleanly) · F-17 (split `session.rs` along the `mod parse` seam) · F-20 (one tool-behavior table) · F-21 (single owner for tool params) · F-19 (autoDispose) · F-22 (API `guard` choke point). *Outcome: adding an editor capability or a Club endpoint touches one place, not five.*

**Continuous — Polish & correctness debt.**
F-24 (determinism: do the docs + dead-`Premul8` cleanup now; the strict-vs-tolerant golden decision is deferred to the team) · F-25 (pagination generation token + optimistic comments) · F-26 (content_hash) · F-30 (surface swallowed errors) · F-31/F-32/F-33 (animation idle, deprecated APIs, magic numbers). Fold these into whatever sprint touches the relevant file.

---

*Methodology: five parallel subsystem audits (engine internals · session/DSL · FFI/codec/IO · Flutter editor · Flutter Club/shell), each returning cited findings; every High-severity finding was then re-read and confirmed against source by the synthesizer. Findings are deliberately specific and skip generic "add more tests/docs" advice except where a concrete gap is named.*
