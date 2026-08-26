# Editor semantics fixes fork pre-existing Replays; the Journal marks the epoch but nothing branches on it

**Decided 2026-08-25 during the UI specification-gap grilling** (survey: `docs/ui-gaps/REPORT.md`;
Replay design: ADR 0003, ADR 0004; format: `app/lib/editor/replay/journal_format.dart`).

A Journal records DSL verbatim and a Replay re-executes it through *today's* engine. So changing
what an existing verb means retroactively changes how every already-recorded Journal replays. That
is not a hypothetical for the fixes in ADRs 0011–0013: preserving the active target's identity
across delete and reorder changes verbs that appear in **ordinary** Journals, and a replayed frame
delete that leaves a different frame active sends every subsequent stroke in that Replay somewhere
else. Timelapses are published artifacts, so some of the affected Replays are already posted.

The decision: **fix the engine properly and accept the fork.** The Journal's version header bumps
from `#mkpxj 1` to `#mkpxj 2` so the bytes record which semantics produced them, a Replay of a pre-2
Journal carries a subtle badge, and **nothing branches on the epoch** — there is one engine
behavior, the correct one.

Alternatives rejected:

- **Epoch-gated engine semantics** (the shell tells the engine which epoch it is replaying via an
  additive verb; the engine keeps both behaviors): preserves the deterministic-replay promise
  byte-for-byte and was the recommended option. Rejected because it installs permanent dual code
  paths on exactly the verbs being fixed, plus a two-epoch golden matrix, to keep faithfulness to
  behavior that was a bug — a maintenance tax paid forever against a shrinking population of old
  Journals.
- **Re-anchoring old Journals on open** (cut a fresh chapter on current bytes, discard the earlier
  history as an unreplayable base image): no dual code and future Replays stay correct, but it
  destroys the making-of history that Replay exists to preserve — a worse loss than a divergent
  render.
- **No header bump at all**: least work, but the fork becomes invisible in the artifact, and nothing
  downstream can ever tell which semantics a Journal was recorded under.

Consequences: the marker is deliberately inert — a future maintainer will find a version bump that
nothing reads and must not "clean it up"; it exists so the *next* fork has a boundary to point at.
Rust goldens that encode active-frame-after-delete or reorder behavior were expected to move, and by
repo doctrine a moved pin is normally *the bug* — such re-pins would have been the documented
exception. **In the event, none moved:** implementing ADR 0013 (commit `66675fe`) left
`aa_off_pins` and `replay_checkpoint` untouched and the whole workspace suite green, because no
golden encodes which frame is active after a delete or reorder. The exception was never needed —
but the reasoning stands for the next fork.

One implementation hazard is worth recording because it is invisible until it destroys data:
`parseJournal` and `JournalRecorder.attachResume` both gated on **exact** equality with the
version-header constant, and attachResume renames a header it cannot recognize aside. Bumping the
constant alone would therefore have set aside every existing user's entire replay history on first
open. Header recognition must always accept every past epoch; there is a test pinning that.
