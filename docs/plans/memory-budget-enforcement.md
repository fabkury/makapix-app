# Engine — Memory budget enforcement (post-memlab)

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done. Update this file as work lands.

## Goal

Turn the measured memory limits (`docs/memlab/REPORT.md`, 2026-07-16) into **enforced budgets** so
adversarial or runaway content degrades gracefully — advisory warning, then refusal with a clear
message — instead of what happens today on Android: a SIGABRT native crash (`panic = "abort"` on a
failed 4 KiB tile allocation) with **no LMK involvement and no way for the user to save work**.

This delivers the §8.2 "hard guard" that SPEC.md has promised since v1 but was never built.

## The numbers this plan is designed against (measured, not estimated)

| Fact | Value |
|---|---|
| Android scudo ~4 KiB class ceiling (tiles 4,112 B + history tables 4,608 B) | **~1.0 GiB**, then SIGABRT |
| Resting doc overhead over raw tile payload | 1.10× (Win) / 1.23× (Android) |
| `.mkpx` save transient (tile-dict double clone + output buffer) | **6.2× / 7.3× doc bytes** |
| Structural-undo retention (AddFrame chains) | `4608 × layers × frames²` (quadratic) |
| Per-frame churn cap (works today) | 128 records ≈ 33.5 MB/frame |

Post-plan invariant to hold: **worst-case ~4 KiB-class usage stays under ~500 MiB** (doc budget
320 + history budget 96 + near-zero save transient after M4a), i.e. ~2× margin below the Android
wall.

## Non-goals

- iOS measurement/validation (deferred with the rest of iOS work; the budgets are sized for the
  Android wall, which is the binding constraint — revisit constants when iOS is measured).
- §8.1's "inactive-frame zstd compression" and disk spill — superseded by budgets for v1.
- Catching OOM in general: `set_alloc_error_hook` is still unstable and `panic=abort` ships.
  Prevention (budgets) is the strategy; M5 only hardens the few giant `Vec` growth sites.

## Work items (recommended order — M1 first, others build on its census semantics)

### M1 — Arc the tile-slot table (kills the quadratic constant)  `[x]` shipped 2026-07-16 (9c84d6d)

`RgbaBuffer.tiles: Vec<Option<Arc<Tile>>>` → `Arc<Vec<Option<Arc<Tile>>>>` with `Arc::make_mut`
in the mutators (`set`, `put_tile_bytes`, `set_tile`, `clear`, `compact`, `apply_before/after`,
`restore_snapshot` — which becomes "replace the whole Arc", simpler than today).

- Frame/Layer clones (undo snapshots, `DuplicateFrame`, `edit_frame`) stop re-allocating the
  4.6 KiB table per layer: a `DocStructure` record's retention drops from `4608·L·F²` to
  `~150·L·F²` (the remaining Frame/Layer struct + name-String clones — still quadratic, which is
  why M2 exists, but ~30× smaller and no longer in the fatal ~4 KiB size class).
- `snapshot()` (per-stroke `begin_edit`) becomes an Arc bump instead of a table copy — a small
  perf win on every stroke.
- **Census follow-through:** `probe::mem_report.history_table_bytes` must switch to Arc-pointer
  dedup for tables (like tiles), otherwise it double-counts shared tables. Keep the field; its
  meaning becomes "unique table bytes retained only by history".
- Audit sites: `buffer.rs` (all), `io.rs` load (`set_tile` path), `diff_from` (read-only, fine).
  Goldens must not change (`cargo test` + `assert.roundtrip` on `examples/*`).
- New scenario test: after `AddFrame`×N on a noisy doc, census history table bytes stay O(N·L·8),
  not O(N²·L·4608).

### M2 — History byte budget  `[x]` shipped 2026-07-16 (3880c00)

`history.rs`: alongside the existing caps (`PER_FRAME_CAP=128`, `TOTAL_CAP=8192`), add
`HISTORY_BYTE_BUDGET` (default **96 MiB**) enforced in `push()`:

- Each `Record` gets an approximate byte weight computed once at push (Pixels: changed tiles ×
  2 × 4096; FrameContent/DocStructure: per-layer struct constant after M1; Selection: mask
  bytes). Maintain a rolling sum; evict oldest records past the budget, but always keep a
  minimum floor (e.g. 8 records) so undo never silently vanishes entirely.
- Weights are approximations (shared tiles overcounted); the `mem` probe stays the precise
  audit. That's fine — the budget is a guard rail, not an accountant.
- `pub` setter (or const-generic default + test override) so tests and the stress lab can vary
  it; no DSL surface needed yet.
- Scenario test: churn + AddFrame chains stay under budget; undo still works after eviction.

### M3 — Document budget at the growth edges  `[x]` shipped 2026-07-16 (1150188)

> **As-built deviations (both strengthen the plan):** (1) enforcement covers **pixel edits too** —
> `commit_edit` rolls back any edit that would cross the hard cap (a `mem_slack` upper bound keeps
> the census walk off the hot path under the soft budget), so the "accepted creep" gap below no
> longer exists and the invariant is strict: *a session is never over the hard budget*. (2)
> Decision on over-budget files flipped to **refuse at load** (user choice 2026-07-16) — the
> loader checks `dict tiles × 4096` against the budget before materializing anything. Uniform
> budgets, no desktop FFI override (user choice); `SetMemBudget` DSL action for tests/lab.

Budget on **unique tile payload** (Arc-deduped, what actually occupies RAM), *not* multiplicity —
a 1024-frame animation of a duplicated static background is a legitimate document that COW makes
nearly free, and multiplicity would forbid it. Divergence (editing the copies) grows unique
payload gradually and is caught by the same checks.

- Session constants: **soft 256 MiB / hard 320 MiB** of unique tile payload (mobile-safe
  defaults; the shell may raise them on desktop via a new FFI `mkpx_set_mem_budget(soft, hard)` —
  default stays mobile-safe per the prod-default principle).
- **Hard enforcement** (engine, authoritative): the structural growth actions —
  `add_frame(_at)`, `duplicate_frame`, `add_layer(_at)`, `duplicate_layer`,
  `duplicate_layer_to_frames`, `paste_commit`/`paste_to_frame`, `import`, `resize_canvas` —
  no-op when the post-action census would exceed the hard cap, matching the existing convention
  (`add_frame` already silently no-ops at `MAX_FRAMES`). The census walk is O(present tiles)
  with a pointer HashSet — ~ms at budget scale, acceptable per structural action (not per
  stroke).
- **Signal surface:** add `mem_soft_exceeded` / `mem_hard_exceeded` booleans + the unique-payload
  figure to `state_json` (and keep the full detail in `mem_json`). Engine actions stay
  infallible-by-convention; the shell reads the flags.
- **Shell (Dart):** after mutating actions (the editor already refreshes state), surface a
  dismissible advisory banner at soft (ClubSizeRules-style wording) and an explanatory snackbar
  when a structural action was refused at hard. Strings TBD with the user during implementation.
- Known accepted gap: pure stroke-painting can creep past hard by ≤256 KiB per stroke (checked
  only at structural actions + banner polling); the wall is 3× away, so creep is harmless.
- Tests: scenario (structural action refused at cap; flags set); Dart widget test for the banner.

### M4 — Save/export: kill the transient, guard the rest  `[x]` shipped 2026-07-16 (7fbe180)

> **As-built:** output verified byte-identical (SHA-256 + fingerprint pre/post). Measured save
> peak on a 256 MiB noise doc: 6.2× → **3.2×** (1.66 GB → 852 MB), fatal-class transient zero.
> Shell-side pre-save guards intentionally skipped: the M3 invariant makes an over-budget save
> unreachable, so `save_estimate` ships as FFI + Dart binding (telemetry) without per-site checks.

- **(a) Dict without clones** (biggest win, do first): `io.rs::save_to_bytes` currently clones
  every distinct tile's 4,096 B *twice* (`dict_order: Vec<Vec<u8>>` + `HashMap<Vec<u8>,u32>`
  keys). Re-key on the tile **content hash** (`util::Hash` = u128) with byte-equality
  verification on hit (store `Arc<Tile>` in the dict entry; compare on hash match, handle the
  ~never collision case with a bucket), and serialize dict entries straight from the `Arc`s at
  write time. First-appearance order is preserved → **byte-identical output** (goldens prove
  it). Expected effect: save transient drops from ~6–7× to ~2× (output buffer + file bytes),
  and — critically — from ~3× to ~0× extra in the fatal Android size class.
- **(b) `save_estimate()`**: exact payload prediction (unique tiles × 4096 + headers, ~+0.1%
  measured for noise) exposed on Session + FFI. The shell checks it before `mkpx_save` /
  publish/export flows and refuses above a platform cap (tied to M3's hard budget — a doc at
  320 MiB must still be able to save, which M4a's ~2× transient permits) with a user-facing
  message instead of a crash.
- **(c) GIF/PNG/WebP export estimates**: frames × canvas × 4 transient in `crates/codec`; same
  refuse-with-message pattern. Lower priority — measured to be far smaller than save.
- Re-run `assert.roundtrip` goldens + a Windows matrix `gen` spot-check to confirm the new peak
  ratio; record it in REPORT.md.

### M5 — Best-effort allocation hardening  `[x]` shipped 2026-07-16 (7fbe180, folded into M4)

`try_reserve` on the few unbounded `Vec` growth sites that can still see tens/hundreds of MB
(io writer buffer, codec encode buffers), mapping failure to `IoError::TooLarge` instead of
abort. No pretense of general OOM safety — budgets are the real defense.

> **As-built deviation:** implemented as exact pre-reservation of the two big writer buffers
> (removes doubling overshoot deterministically — part of the 3.2× figure) rather than
> `try_reserve`-with-Result plumbing: the FFI/Dart `save()` path treats a null return as fatal,
> and the M3 invariant makes save-allocation failure unreachable, so a fallible signature would
> have been dead code with real breakage risk.

### M6 — Validation + docs  `[x]` completed 2026-07-16 — **acceptance met: zero SIGABRTs**

> All suites green (250 Rust + 249 Dart, clippy at baseline), `.mkpx` output byte-identical.
> Device re-run on the Pixel: the full in-app ladder survived **all 11 rungs in one launch**
> (previously 6 kills); headless 2 GiB DSL build exits 0 capped at 320 MiB; the 512-frame edit
> that died at frame 448 now runs at 342 MB RSS with history retention down 302 MB → 719 KB.
> Addendum tables in `docs/memlab/REPORT.md`; SPEC §8.2b/§10.3 and STATUS.md updated.

- Full suites green; clippy; goldens unchanged.
- **Device proof:** re-run `tools/memlab/run_ladder.ps1` on the Pixel. Acceptance: **zero
  SIGABRTs** — every previously-killed rung now ends in a refused action (flags set, app alive)
  or a survived rung. Append an addendum table to `docs/memlab/REPORT.md`.
- Update SPEC.md §8.2/§8.2b + §10 (history byte budget), STATUS.md, and the memlab memory note.

## Open questions (defaults chosen above; flag disagreement before M3)

1. **Budget constants** — 256 MiB soft / 320 MiB hard unique payload, 96 MiB history: sized for
   ~2× margin under the Android wall. Desktop override via FFI or keep uniform?
2. **Refusal UX** — silent no-op + banner/snackbar (matches `MAX_FRAMES` convention) vs. modal.
3. **`ClearHistory` as a user-visible "Free memory" action** in the editor ☰ menu — cheap to add
   once M2 lands; include or skip?

**Total estimate: ~4–5 dev-days.** M1+M2+M4a alone remove every measured crash mode; M3/M4b add
the user-facing guarantees.
