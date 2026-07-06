# UGC safety (app side)

The store-compliance safety features — **content reporting** (posts,
comments, users; works logged-out), **user blocking** (block/unblock,
blocked-users management, `403 blocked` handling), the **published moderation
contact** (`acme@makapix.club`), and the **first-run community-rules gate**
(Apple 1.2 "agreed-to rules") — implemented against the server team's frozen
contract v1 (2026-07-06).

| Doc | What |
|---|---|
| `PLAN.md` | The implementation plan: file-by-file changes, tests, manual verification matrix, rollout, and the draft `0002` reply (Appendix A) |
| `DECISIONS.md` | App-side decisions A1–A18 (owner + engineering) |
| `PROGRESS.md` | Created during implementation; tracks the checklist |

Server-side authority (read-only from here, checkout of the server repo):

- Contract: `reference/makapix-club/docs/ugc-safety/API-CONTRACT.md` (frozen v1)
- Server decisions D1–D26: `reference/makapix-club/docs/ugc-safety/DECISIONS.md`
- Kickoff message: `reference/makapix-club/message/0001-server-ugc-safety-kickoff.md`

Feature gate: `GET /api/v1/config` → presence of the `moderation` block
(dev key = dev go signal; prod key = launch signal — same mechanism as
mkpx-upload and mod-hashtags).
