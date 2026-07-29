# Dev/test-only scaffolding — a removal guide

This inventories everything in the tree that exists **only** to enable testing, measurement, or
memory stress work — with exact pointers — so that if we ever decide to strip it out, nothing is
missed and nothing shipped is removed by mistake. It is a map, not a to-do: none of this is
scheduled for removal. Last verified 2026-07-29.

Three categories:

- **A — removable lab scaffolding.** Pure measurement/stress plumbing. No shipped UI or product
  code path depends on it (verified: the only consumer of the memory-census surface is the adb-only
  lab). Removing all of A is a clean, self-contained change.
- **B — tests that depend on A.** Regression tests that would have to be deleted or rewritten if A
  is removed, because they call the A-only DSL verbs. They guard the *shipped* budget enforcement,
  so losing them has a real cost — weigh that before removing A.
- **C — DO NOT REMOVE.** Code the memlab study produced that is now **product** (budget
  enforcement, COW tiles, the save-transient fix). It reads as "memlab" in comments but shipping
  behavior depends on it. Listed here specifically so a future cleanup doesn't over-reach.

A removal PR would touch A (+ B), leave C entirely alone, and keep `cargo test` / `flutter
analyze` green after B is pruned.

---

## A — Removable lab scaffolding

### A1 · The in-app memory stress lab (adb-only, no UI entry)

| What | Where | Notes |
|---|---|---|
| The lab page + ladder + rung grammar | `app/lib/dev/memlab.dart` (whole file) | Reachable only via a launch-intent extra; no UI entry point. Includes the `+export` publish-peak rung added 2026-07-29. |
| The gate that mounts it | `app/lib/app.dart:5` (`import 'dev/memlab.dart'`), `:55` (`home: const MemLabGate(child: AppShell())`) | Restore to `home: const AppShell()` and drop the import. |
| The Android intent bridge | `app/android/app/src/main/kotlin/club/makapix/app/MainActivity.kt:10-19` (the `club.makapix.app/memlab` `MethodChannel`) | Without this the Dart `memLabPlan()` always returns null, so A1 is inert even if left in. |

Self-contained: removing all three leaves the app booting straight into `AppShell`.

### A2 · The `tools/memlab/` directory

| What | Where |
|---|---|
| Windows / device matrix + ladder drivers | `tools/memlab/run_matrix.ps1`, `run_matrix_device.ps1`, `run_ladder.ps1` |
| Synthetic GIF generator (import-audit, 2026-07-29) | `tools/memlab/make_gif.py` (full / noise / bomb modes) |
| Captured result CSVs | `tools/memlab/results/*.csv` (incl. `*_pre_enforcement.csv`) |

Pure tooling + data; nothing imports it. (`tools/memlab/__pycache__/` is already covered by
`.gitignore:77` and must never be committed.)

### A3 · The `mkpx` CLI lab commands and probes

All in `crates/cli/`:

| What | Where | Depends on |
|---|---|---|
| `mkpx gen` (build a full-noise doc directly) | `crates/cli/src/main.rs` — `"gen"` dispatch (`:88`) + `gen_noise_doc()` | `tool::noise_fill` (A5) |
| `mkpx import` (drive `codec::decode` + `import_decoded`; added 2026-07-29 for the audit) | `crates/cli/src/main.rs` — `"import"` dispatch (`:123`) | the `makapix-codec` dev-dep just below |
| `makapix-codec` dependency of the CLI | `crates/cli/Cargo.toml` (the `makapix-codec = { path = "../codec" }` block) | only `mkpx import` needs it |
| `mem` / `mem.os` probes | `crates/cli/src/main.rs` — `"mem"` (`:237`), `"mem.os"` (`:238`) + the whole file `crates/cli/src/mem.rs` (OS RSS/HWM reader) | `Session::mem_json` (A4) |

Keep in mind `mkpx load` and the non-`mem` probes (`ascii`, `hash`, `stats`, `render`, …) are the
general Tier-1 harness — **not** lab-only. Only `gen`, `import`, `mem`, `mem.os` and `mem.rs` are A.

### A4 · The engine-census FFI + Dart binding

| What | Where |
|---|---|
| `mkpx_mem_json` C export | `crates/ffi/src/lib.rs:250-257` |
| Dart binding `memJson()` + lookup | `app/lib/engine_ffi.dart:128` (`_memJson`), `:218-225` (`memJson()`) |

Its only caller is `app/lib/dev/memlab.dart:222` (A1). Verified 2026-07-29: no shipped code calls
`memJson`. (Contrast `mkpx_used_colors_json` right beside it — that one **is** shipped, powering the
palette used-colors query. Don't remove it.)

### A5 · Engine-side lab hooks

| What | Where | Removable? |
|---|---|---|
| `Session::mem_json` | `crates/engine/src/session.rs:2218` | Yes — only feeds A4. |
| `probe::mem_report` + `MemReport` + `to_json` | `crates/engine/src/probe.rs:296` (struct), `:349` (`to_json`), `:379` (`mem_report`) | Yes — only feeds `mem_json`. **Note:** `probe::state_json` (same file) is shipped; only the `mem_report`/`MemReport` census is A. |
| `Session::fill_noise` + `FillNoise` DSL verb | `session.rs:2204`; `parse.rs:114` (variant), `:297` (dispatch), `:669` (parse) | Yes — but referenced by B tests. |
| `tool::noise_fill` | `crates/engine/src/tool.rs:569` | Yes — used by `fill_noise` (A5) and `gen_noise_doc` (A3). |
| `SetMemBudget` DSL verb + budget override | `parse.rs:171` (variant), `:356` (dispatch), `:736` (parse); `session.rs:321` (`mem_budget_override` field), `:1009` (`set_mem_budgets`), `:1003` (`mem_budgets` reads it) | Partial — the *override* is test-only; the **default** `MEM_*_BUDGET` enforcement it overrides is shipped (category C). Removing the override means `mem_budgets()` just returns the constants. |
| History byte-budget override | `crates/engine/src/history.rs:91` (`byte_budget` field), `:155` (`byte_budget()`), `:160` (`set_byte_budget`) | Partial — same shape: the override is test-only, the default `HISTORY_BYTE_BUDGET` is shipped (C). |

The `SetMemBudget` / `set_byte_budget` overrides exist so tests can shrink the budgets to tiny
values and exercise the refusal path fast. Removing them is more invasive than the rest of A (they
thread through `Session` and `History`), and they're cheap to keep — lowest-value removal in A.

---

## B — Tests that depend on A (would break if A5 is removed)

- `crates/engine/tests/scenarios.rs:336-490` — the "FillNoise + mem probe" block: determinism of
  `FillNoise`, COW sharing, the history-quadratic regression guard, and the **budget-enforcement
  regression tests** (they call `SetMemBudget(...)` + `FillNoise(...)` to force refusals at a tiny
  budget). These validate shipped behavior (M1–M5) via the A-only verbs, so removing A5 means either
  deleting them or rewriting them against a non-DSL test API. **This is the real cost of removing A**
  — the shipped enforcement loses its cheapest regression coverage.

(No new import/export tests were added for the 2026-07-29 audit; the `mkpx import` path is exercised
only manually via the addendum recipes in `docs/memory-audit/REPORT.md`.)

---

## C — DO NOT REMOVE (memlab-derived, but shipped product)

These carry "memlab" in their comments but shipping behavior depends on them. A cleanup that greps
for "memlab" and deletes matches would break the app.

- **Document budget enforcement** — `document.rs` `MEM_SOFT_BUDGET`/`MEM_HARD_BUDGET`,
  `unique_payload_bytes`; the `Session` chokepoints (`commit_edit`, `edit_frame`, `edit_doc`) and
  `mem_slack`/`mem_exact`/`mem_recalibrate`/`mem_refusals`. The shipped memory banner + refusal
  snackbar (`editor_page.engine.dart` `_syncMemBudgetUi`) read these via `state_json`.
- **History byte budget** — `history.rs` `HISTORY_BYTE_BUDGET`, `weight_of`, `enforce_byte_budget`.
- **COW tile tables** — `buffer.rs` `Arc<TileTable>` (memlab M1); the save-transient dictionary fix
  (`io.rs` `tile_arc`, M4a) and the `reserve_exact` sizing (M5); the loader's up-front budget refusal
  (`io.rs` `load_from_bytes_budgeted`).
- **`tile_table_bytes` accounting** — `buffer.rs` / `probe.rs` (the field is also what audit
  proposal #7 would start enforcing).

The distinguishing test: *does removing it change what a normal user's session does?* For A, no
(only measurements disappear). For C, yes.

---

## Related

- `docs/memlab/REPORT.md` — the study these enablers were built for, and the enforcement (C) it drove.
- `docs/memory-audit/REPORT.md` — the 2026-07-29 audit + device addendum; its `mkpx import` /
  `make_gif.py` / `+export` additions are A3/A2/A1 above.
