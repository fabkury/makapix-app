# Fuzzing for Makapix — analysis and recommended approach

**Date:** 2026-08-16
**Status:** FULLY IMPLEMENTED 2026-08-25 — all four §3.2 targets live in `fuzz/` with
day/night run scripts in `tools/fuzz/` (operations: `fuzz/README.md`; findings and run
log: `docs/fuzzing/FINDINGS.md`). Targets 1–2 found three real engine bugs (FZ-1/FZ-2/
FZ-3, all fixed with regressions); targets 3–4 came up clean on first contact. The
differential uses libwebp (the C reference) as the independent decoder, per §2.3.
The analysis below is preserved as written.

**Verdict up front:** fuzzing is not merely "useful" here — the Makapix engine is unusually
*pre-adapted* to it (deterministic, zero-dep, headless, DSL-driven, oracle-rich) while
simultaneously having unusually *high stakes* for it (hand-written binary parsing of adversarial
user files inside a `panic = "abort"` process on memory-walled Android devices). The repo already
contains a hand-rolled 1988-style fuzzer (`crates/engine/tests/fuzz_inputs.rs`); the
recommendation is to give that instinct 2014's engine: coverage-guided fuzzing via `cargo-fuzz`.

---

## 1. Fuzzing primer

### 1.1 Origin and the core idea

Fuzzing began with Barton Miller (University of Wisconsin, 1988): line noise over a stormy modem
connection kept crashing mature Unix utilities, so he wrote a program named `fuzz` that fed random
bytes to every utility and recorded crashes. Result: 25–33% of utilities on every Unix flavor
tested crashed or hung on random input.

Every fuzzer since has the same two components:

1. **A generator** — produces inputs the developer never thought of.
2. **An oracle** — decides *automatically* whether the program misbehaved on a given input.

The key insight: a crash is a *self-evident* failure. You can test a program against inputs you
don't understand, as long as failure announces itself. No specification of correct output needed.

### 1.2 Taxonomy

Two mostly-independent axes:

**How inputs are constructed:**

- **Mutational** — start from a *seed corpus* of valid inputs and mutate (bit flips, splices,
  chunk duplication, truncation). Mutants of valid files pass magic-number and header checks, so
  they reach deep into the parser before turning hostile.
- **Generational / grammar-based** — construct inputs from a specification of the format. Reaches
  states mutation essentially never stumbles into (e.g., exactly 1024 frames × 64 layers), but you
  must write the grammar.

**How much the fuzzer sees inside the program:**

- **Black-box ("dumb")** — run blind, watch for crashes. This is what `fuzz_inputs.rs` does today.
- **White-box** — symbolic execution (e.g., Microsoft SAGE); solves for inputs reaching specific
  branches. Precise but expensive; mostly research/big-vendor territory.
- **Grey-box, coverage-guided** — the modern sweet spot (AFL 2013, libFuzzer; Rust's `cargo-fuzz`
  wraps libFuzzer). See below.

### 1.3 Coverage guidance — why it was the breakthrough

Dumb random fuzzing dies at the first check: random bytes have a 1-in-4-billion chance of passing
a 4-byte magic-number comparison, so blind fuzzing tests the error path forever.

Coverage-guided fuzzers close a feedback loop:

1. Instrument every branch at compile time.
2. Run an input; if it exercised *any new branch*, keep it in the corpus; otherwise discard.
3. Mutate the kept inputs; repeat millions of times per minute.

It is a genetic algorithm whose fitness function is "discovered new code," and it climbs discrete
cliffs incrementally — some mutation produces `M` in byte 0 (new branch, kept), then `MK`, then
`MKP`… Within minutes it synthesizes valid headers and finds the deep interior of a parser.
Researchers have watched AFL invent valid JPEGs starting from the seed `"hello"`. This machinery
is why Google's OSS-Fuzz has reported tens of thousands of bugs and why every serious format
parser (SQLite, libpng, Chrome codecs) runs under continuous fuzzing.

The evolved corpus is an asset: after a night of fuzzing you hold a distilled input set that
collectively exercises the whole parser. Minimize it (`cargo fuzz cmin`) and check it in so future
runs start deep.

### 1.4 Oracles — what counts as "misbehaved"

1. **Crash / panic.** Free, always on. In Rust: out-of-bounds indexing, `.unwrap()` on `None`,
   integer overflow (with overflow checks on), explicit asserts.
2. **Sanitizers.** In C/C++, ASan et al. turn silent memory corruption into loud crashes. Largely
   moot for safe Rust — the borrow checker did it at compile time — which changes what fuzzing
   means for Rust (§1.5).
3. **Resource oracles.** Timeouts and memory caps (libFuzzer `-rss_limit_mb`). Catch algorithmic
   complexity and allocation-bomb bugs: the 200-byte input that allocates 4 GB. No unsafety, but a
   denial-of-service on the recipient.
4. **Property oracles** — where fuzzing shades into property-based testing (QuickCheck 2000,
   Rust's `proptest`). Assert a property over the output, not just "didn't crash":
   - **Round-trip:** `save(load(save(doc))) == save(doc)` byte-for-byte.
   - **Differential:** two independent implementations must agree (our WebP muxer vs. libwebp).
   - **Invariant:** internal invariants hold after any action sequence.
   - **Determinism:** same input twice → identical output.

   Property oracles find *logic* bugs — the wrong pixel, the corrupted save — invisible to a
   crash-only oracle.

Property-based testing and fuzzing are converging: PBT = structured inputs + explicit properties +
seconds in CI; fuzzing = coverage-guided byte search + hours offline. `cargo-fuzz` + the
`arbitrary` crate merge them: coverage-guided fuzzing over *structured* values (e.g., a sequence
of typed editor actions). This is **structure-aware fuzzing** — the exact fit for the DSL.

### 1.5 What fuzzing means in Rust specifically

"Rust is memory-safe, so fuzzing is a C-world concern" is wrong here for four reasons, each
sharpened by this codebase:

1. **Panics are crashes for us.** The workspace ships `panic = "abort"` and no panic may cross the
   FFI boundary — a single hostile-index `vec[i]` aborts the entire Flutter app with unsaved work.
   The header of `fuzz_inputs.rs` itself says the panic-free guarantee "rests entirely on test
   coverage." Fuzzing is the technology for that sentence.
2. **Resource exhaustion is a first-class bug for us.** The Android ~1 GiB scudo wall
   (docs/memlab/REPORT.md) means an adversarial file that merely *allocates ambitiously* is a
   remote crash vector. The loader-refusal budgets are the defense; fuzzing with a memory-cap
   oracle adversarially tests that defense.
3. **Logic bugs under property oracles.** Byte-determinism of `.mkpx`, undo invertibility,
   golden-hash stability — the engine's core promises are exactly the properties fuzzers check
   best.
4. **The `unsafe` that remains.** `crates/engine` is `#![forbid(unsafe_code)]`, but `crates/ffi`
   cannot be — raw pointers and C strings are its job. Small surface, but real.

### 1.6 Honest limits

- Fuzzing is a probabilistic search: absence of crashes is evidence, never proof.
- It finds only what the oracle can see — a wrong-but-plausible render passes a crash oracle.
- It struggles past *semantic* walls: checksums and content-addressed hashes (the `.mkpx` tile
  dictionary!) reject deep mutants early, shielding interior code. Standard fixes: a fuzz-only
  build flag that skips verification, or structure-aware generation that recomputes hashes.
- It saturates: the first night finds more than the next month. The professional pattern: fuzz
  hard early, then run continuously at low priority, and convert every finding into a
  deterministic regression test forever.

---

## 2. Applicability to Makapix, ranked by surface

### 2.1 The `.mkpx` loader — highest value; input is genuinely adversarial

Since mkpx-upload shipped, **other users' `.mkpx` files flow through the Club into the engine**
via edit/remix. The input is not merely malformed by accident — it can be *crafted*. A
hand-written binary parser (v10 typed chunks, tile dictionary, RAW/RLE/INDEXED encodings) runs
over hostile bytes, in a `panic = "abort"` process, on devices with a 1 GiB allocator wall.
Structurally this is Android's Stagefright situation (a media parser processing other people's
content on a phone); Rust removes the remote-code-execution tier, leaving the crash-the-app and
exhaust-the-memory tiers — exactly what panic + RSS oracles hunt.

What exists today: `corrupt_mkpx_never_panics` does every truncation of one valid file, 6,000
single-byte flips of it, and 3,000 random garbage buffers. In taxonomy terms: black-box mutational
fuzzing with a corpus of size one, no coverage feedback, a fixed PRNG, a few thousand executions.
An excellent *regression rig*; a weak *explorer*. Coverage-guided fuzzing does billions of
executions overnight, breeds hundreds of structurally-diverse documents, and learns the chunk
grammar from branch feedback — reaching states one-seed bit-flips essentially cannot (tile-dict
indices that cross-reference just wrong; an INDEXED tile whose palette length disagrees with its
data; counts at exact budget boundaries).

### 2.2 The DSL + `Session` state machine — highest value for logic bugs

The bug history is the argument: F-29 (changing the active layer mid-stroke corrupted undo
attribution) is the archetypal fuzzing trophy — a bug in an *unanticipated interleaving* of
actions, not in any single action. Humans don't write "PointerDown, switch layer, PointerMove"
tests; a structure-aware fuzzer generating random sequences of valid actions writes nothing else.

Crucially, **the engine already exposes gold-standard property oracles**: `assert.undo`,
`assert.roundtrip`, frame/layer hashes, byte-determinism — all exist as CLI probes today. An
action-sequence fuzzer with the compound oracle "no panic ∧ undo restores the pre-action hash ∧
save→load→save is byte-identical" turns the determinism doctrine from a promise into a
continuously-attacked theorem.

### 2.3 The codec crate — medium-high value, one jewel

The *import* decoders (GIF/PNG/APNG/JPEG/BMP/WebP via the `image` crate) are heavily fuzzed
upstream by OSS-Fuzz; fuzzing them mostly re-finds upstream bugs. Our own wrapper logic (frame
extraction, size budgets, too-large refusal) merits a modest target.

The jewel is the *export* side: the **hand-muxed animated WebP encoder** is homegrown
binary-format *generation*, and the perfect oracle is differential — already used manually once
("libwebp-verified lossless," 2026-08-09). Fuzz-generate small documents, encode with our muxer,
decode with an independent decoder, demand pixel-exact equality. That mechanizes forever a check
currently trusted from a one-time verification.

### 2.4 The FFI crate — small, targeted value

`crates/ffi` holds the workspace's necessary `unsafe` (C strings in, buffers out). A small target
throwing arbitrary byte strings — including invalid UTF-8 — at the `mkpx_run` internals covers it.
Low effort; closes the one place classic memory-unsafety could theoretically live.

### 2.5 The Dart/Club side — low value; skip deliberately

Club parses JSON from our own server over TLS: a semi-trusted source with a typed contract.
Malformed JSON throws a catchable Dart exception in a memory-safe VM, not a process abort. The
genuinely dangerous inputs Club handles — artwork bytes from other users — are forwarded to the
engine and codec, i.e., to the Rust surfaces above. Dart fuzzing tooling is immature and the
payoff is a handled exception. The dependency-direction rule ("Dart fetches, Rust computes")
concentrates all parse risk on the side where fuzzing tooling is world-class. **Fuzz where the
bytes are parsed, not where they're fetched.** Spend zero fuzzing effort on the Dart side.

---

## 3. Recommended approach

**Strategy in one sentence: two-tier fuzzing** — coverage-guided exploration offline (WSL,
overnight, nightly toolchain), with every finding distilled into the existing deterministic
`fuzz_inputs.rs` suite, which stays fast, stable, and Windows-native in CI forever.

Repo rules already bless this: fuzzers are non-shipping dev-tooling, explicitly "unconstrained and
encouraged" (CLAUDE.md), and a `fuzz/` directory never touches the zero-dependency engine.

### 3.1 Tooling

- **`cargo-fuzz`** (the Rust-standard libFuzzer frontend), run under **WSL2** — it wants a nightly
  toolchain and is happiest on Linux. The engine is platform-independent by construction (that is
  what byte-determinism means), so bugs found in WSL are bugs everywhere.
- **`arbitrary`** crate for structure-aware targets.
- `proptest` for CI-speed property tests is optional; the LCG suite already occupies that niche
  adequately — skip initially.
- OSS-Fuzz enrollment is possible if the repo qualifies as open source, but it is a heavy process;
  not the first move.

### 3.2 Targets, in priority order

1. **`fuzz_load_mkpx`** — raw bytes → `load_bytes` + `load_bytes_tolerant`, then the existing
   `poke_reads` pattern (composite, state_json, pixel, hashes, save), then on successful load a
   resave→reload round-trip. Seed corpus: a handful of small real saves. Run with
   **`-rss_limit_mb=512`** so the *Android allocator wall becomes an oracle on the workstation* —
   the single most Makapix-specific trick in this document: a Linux fuzzer finds the allocation
   bomb that would SIGABRT a Pixel.
2. **`fuzz_session_actions`** — structure-aware: derive `Arbitrary` for a small enum mirroring
   interesting actions, render each sequence to DSL text, run it, assert the compound oracle
   (no panic; undo restores pre-action hash; save→load→save byte equality). This is the target the
   F-29 history says will pay.
3. **`fuzz_webp_differential`** — small arbitrary documents → our muxer → independent decode
   (`image`/libwebp) → pixel-exact compare (lossless means exact equality).
4. **`fuzz_codec_import`** — image bytes → our import wrapper; seeds from `examples/`; cheapest,
   last.

### 3.3 Process discipline

- **First move:** run target 1 overnight. The first night against a never-coverage-fuzzed
  hand-written parser is when trophies drop; finding *zero* would itself be meaningful evidence
  for the budgets-and-refusal design.
- **Every crash:** `cargo fuzz tmin` to a minimal reproducer, then **commit it as a new literal
  entry in `fuzz_inputs.rs`** (or a checked-in corpus file) so it is guarded on every platform,
  every CI run, no nightly required. This continues the file's existing pattern (each entry is a
  regression for a specific finding).
- **Corpus:** periodically `cargo fuzz cmin` and check in the minimized corpus so future sessions
  start deep instead of from scratch.
- **Fuzz profile:** enable `overflow-checks = true` — for an engine whose creed is integer
  exactness, a silent wraparound is a correctness bug; the flag turns it into a caught panic.
- **Knobs:** `-max_len` (keep inputs small; canvas ≤256×256 anyway), `-timeout`,
  `-rss_limit_mb=512`.
- **Watch item:** if coverage plateaus suspiciously early on the loader, suspect the
  content-addressed tile hashes are walling off deep code (§1.6); consider a fuzz-only feature
  flag that skips hash verification, or structure-aware generation that recomputes hashes.

### 3.4 Cost of entry

Target 1 is on the order of thirty lines plus one WSL toolchain setup — an afternoon — with the
steepest part of the payoff curve immediately behind it.

---

## Appendix: existing state inventory (as of 2026-08-16)

- `crates/engine/tests/fuzz_inputs.rs` — deterministic adversarial suite: known-hostile DSL
  scripts (regressions for audit findings F-1/F-2/F-3/F-4/F-6/F-28/F-29), 6,000 random DSL lines
  from a fixed LCG, `.mkpx` truncation/bit-flip/garbage corruption, id-collision check. Runs in
  plain `cargo test` on stable, Windows-native.
- No `cargo-fuzz`, libFuzzer, AFL, or `proptest` anywhere in the workspace (no `fuzz` mentions in
  any `Cargo.toml`).
- CLI probes usable as oracles: `assert.undo`, `assert.roundtrip`, `assert.gradient:TOL`, `hash`,
  `stats`, `state` (see `crates/cli/src/main.rs`).
- Relevant constraints: engine is zero-dep + `#![forbid(unsafe_code)]`; workspace ships
  `panic = "abort"` in release; Android ~1 GiB scudo wall with shipped budget enforcement
  (docs/memlab/REPORT.md); `.mkpx` v10 spec in docs/mkpx-format/.
