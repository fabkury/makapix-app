# Moderator hashtags — app-side implementation

App-side plan for **moderator hashtags**: hashtags on a post that only moderators
can add or remove, otherwise behaving exactly like regular hashtags (including
monitored-hashtag filtering). Headline use case: an artist posts an artwork that
should carry a monitored tag (e.g. `#nsfw`) and didn't add it; a moderator adds
it and the artist cannot remove it.

The server + website side is being built in parallel on `develop`
(development.makapix.club). The **frozen API contract v1 (2026-07-05)** lives in
the server repo: `reference/makapix-club/docs/mod-hashtags/API-CONTRACT.md`.
Kickoff message: `reference/makapix-club/message/0001-server-mod-hashtags-kickoff.md`.

| File | Purpose |
|------|---------|
| `PLAN.md` | The implementation plan — file-by-file changes, tests, rollout |
| `DECISIONS.md` | Product/UX decisions taken with the owner + engineering decisions |

Status: plan reviewed by two independent agents (2026-07-05 — no blockers;
should-fixes incorporated, see PLAN.md "Review round") and committed;
implementation starts on the owner's go-ahead. The reply to the server team (`0002-app-…`) is drafted in `PLAN.md`
appendix A and gets committed to the server repo when implementation starts.
