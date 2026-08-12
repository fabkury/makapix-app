# Phase 0 baseline + Phase 1 "after" — measured 2026-08-12

**Device:** Pixel 10 Pro XL (mustang), Android, 120 Hz panel, 1344×2992.
**Build:** profile APK at commit `e2f9eb4` (Phase 0 counters, pre-fix), signed-in session,
player device online (15 s poll active), SSE connected.
**Conditions:** unplugged, Wi-Fi adb, fixed manual brightness (system value 110),
DND priority, 10 min per scenario, same 64×64 document (1 layer; frames per scenario below).
**Method:** fuel-gauge charge-counter delta (`/sys/class/power_supply/battery/charge_counter`)
× mean of before/after voltage → average whole-phone power; app-level `[battery]` counter
lines (5 s windows) from logcat. Raw artifacts: `tools/battery/results/` (git-ignored,
local) — session dirs `20260812-140347-idle-no-selection-v2`,
`20260812-141430-idle-with-selection-v2`, `20260812-142517-playback-2fps-v2`.

## Results

| Scenario | Staged as | avg `fps=` | Whole-phone power | Δ vs A |
|---|---|---|---|---|
| **A** idle, no selection | Pencil active, 1 stroke drawn, hands off | **0.0** | **≈ 899 mW** (37 500 µAh) | — |
| **B** idle, committed selection | Rect selection, ants marching, hands off | **119.8** | **≈ 2 083 mW** (87 500 µAh) | **+1 184 mW** |
| **D** playback, 2 fps animation | 2 frames × 500 ms, playing, hands off | **119.9** | **≈ 1 835 mW** (77 500 µAh) | **+936 mW** |

Counter-line detail (per 5 s window):

- **A:** everything 0 except `http=1` roughly every third window — the 15 s player poll,
  exactly on schedule (~40 requests/10 min while idle in the editor).
- **B:** `fps=119.8`, all engine counters 0 — pure ants repaint churn: the whole cost is
  frame production/rasterization, no FFI involvement.
- **D:** `fps≈120`, `comp=10 dec=10` (decode correctly gated to the 2 fps content),
  `dsl≈600` (≈120 `AdvanceClock` FFI sends/s).

## Reading

- An **idle selection makes the editor burn 2.3× the power** of the identical idle editor
  without one (+1.18 W). This is ASSESSMENT.md §4.1 confirmed on hardware, at the 120 Hz
  worst case; F1+F2's target is to bring scenario B within ~10 % of A.
- **2 fps playback costs ~0.94 W** for content changing twice a second — §4.2 confirmed;
  the cost is frame production + per-vsync FFI, not decode (which is already gated).
- The A floor (~0.9 W) is dominated by the screen at this brightness; deltas, not absolute
  values, are the comparison currency.
- The player poll fires all through an editor session (F8's target: 0 of those ~40
  requests).

## After Phase 1 (same device, document, brightness; commit `f76eed4`)

Session dirs `20260812-150517/151610/152702-*-after`.

| Scenario | avg `fps=` before → after | Power before → after | Δ overhead vs same-day A |
|---|---|---|---|
| **A** idle, no selection | 0.0 → 0.0 | 899 → **823 mW** | — (the floor) |
| **B** idle, committed selection | 119.8 → **5.7** | 2 083 → **938 mW** | +1 184 → **+115 mW** (−90 %) |
| **D** playback, 2 fps | 119.9 → 119.9 | 1 835 → **1 576 mW** | +936 → **+753 mW** |
| HTTP during a 10-min editor session | 42 → **2** requests | | (F8 pillar gate) |

**Checkpoint 1 verdict:**

- **Ants (F1+F2): fixed.** B runs at exactly the 5.7 Hz content rate; the selection's cost
  fell from +1.18 W to +0.12 W. B sits within ~14 % of the A floor (target was ~10 %; the
  remainder IS the ants' real content — 6 small repaints/s — not waste).
- **Radio (F8): fixed.** 42 → 2 requests per editor session; the player poll is silent
  while the bar is unmounted and resumes with an immediate refresh on return.
- **Playback: ~260 mW cheaper** (journal fast path + poll silence + FFI trims) but still
  ~750 mW over the floor because the vsync Ticker still forces 120 fps frame production —
  by design out of Phase 1's scope. **This is Gate A's decision data: R3 (demand-driven
  playback clock) has a measured ~700 mW prize on 120 Hz devices.**

## Caveats

- Fuel-gauge deltas are whole-phone; a Gmail notification landed silently during B (DND
  priority) — negligible. Battery went 65 % → 56 % over the whole exercise.
- The Pixel's raw ODPM rail accumulators are not dumpable on this build (`dumpsys
  powerstats` prints only the channel catalog); per-rail attribution would need Perfetto's
  `android.power` datasource. Not needed at these effect sizes.
- First-pass sessions (non-`-v2` dirs) lack power data (wrong dumpsys service) and A's
  counter log is tail-only (logcat ring eviction, fixed by `logcat -G 16M`); superseded by
  the `-v2` runs.
