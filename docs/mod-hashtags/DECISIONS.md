# Moderator hashtags (app) — Decisions

Product/UX decisions taken with the owner on 2026-07-05, plus engineering
decisions made during planning. Numbered `A*` (app) to avoid colliding with the
server repo's `D1–D22` (which remain authoritative for server behavior and the
wire contract).

## Owner decisions (2026-07-05)

**A1 — Ship the moderator editor in this release.** The app has no moderator UI
surface today; rather than deferring (which the server team offered), the full
feature ships at once: shield-marked display, the `mod_hashtags_updated`
notification, and a moderator-only "Edit mod hashtags" editor. Rationale: the
owner moderates the site himself and wants the phone workflow.

**A2 — Entry point: overflow (kebab) menu on the artwork detail page.** A
moderator-visible overflow menu with "Edit mod hashtags…" as its entry — chosen
over a bare shield icon button because the kebab is the scalable home for
future moderator actions (hide, promote) if they come to the app. The action
opens a modal bottom sheet (the app's mobile idiom), not a full page.

**A3 — Marker style: shield glyph prefix.** For moderators and the post's
artist, mod hashtags render as a small shield icon before the tag text
(`🛡 #nsfw`), same color and tap behavior as regular tags, with
"Added by moderators" on long-press/hover (Tooltip). Matches the website's 🛡️
chips (contract D2). Public users see mod tags as perfectly normal tags.

**A4 — Audit fields: optional note only.** The editor sheet exposes one
optional "Note (for the audit log)" field; `reason_code` is not exposed in v1.
Keeps the mobile flow one-handed; the server treats both fields as optional.

## Engineering decisions

**A5 — Feature discovery = nullable config field.** `ClubServerConfig` gains
`maxModHashtagsPerPost: int?` parsed from `max_mod_hashtags_per_post` with **no
default** — `null` means the server does not have the feature and every
mod-hashtag *editor* affordance stays hidden (contract §2/D19: against an old
server the PUT 404s indistinguishably from "post not found"). Same mechanism as
the mkpx-upload rollout (`upload.mkpx`).

**A6 — The shield marker is NOT config-gated.** Rendering the marker depends
only on `post.modHashtags` being non-empty and the viewer being a moderator or
the post's artist. A server without the feature never sends the field, so the
marker naturally cannot appear; no config check needed. (The *editor* is
config-gated per A5.)

**A7 — One merged overflow menu on the detail page.** The existing owner-only
mkpx layers-file `PopupMenuButton` and the new moderator entry merge into a
single overflow menu builder that aggregates applicable entries. Otherwise a
moderator viewing their own post would see two side-by-side kebab icons.

**A8 — New `ModerationApi` file.** The PUT goes in a new
`app/lib/club/api/moderation_api.dart` rather than `post_api.dart` — it is the
app's first moderator-role endpoint and the natural home for future ones
(hide/promote). Provider added in `state/api_providers.dart` per the existing
pattern.

**A9 — Client-side normalization mirrors the server for preview only.** The
sheet normalizes tags as the user adds them (trim, strip one leading `#`,
lowercase, drop empties, order-preserving dedupe, per-tag ≤64 chars) so the
working set the moderator sees matches what the server will store. The
**response body remains the source of truth** (contract §4) — after a
successful PUT the sheet's result is discarded and the page re-renders from the
returned/refetched Post.

**A10 — Refresh via `ref.invalidate(postDetailProvider)`.** The PUT returns the
full updated Post, but the page idiom everywhere else (mkpx attach/detach) is
invalidate-and-refetch; we follow it rather than introducing a second update
path. One extra GET per save is negligible at moderation frequency.

**A11 — Monitored quick-picks + monitored highlight** (parity with server D22).
The sheet has one-tap `FilterChip`s for the five `kMonitoredHashtags` and
visually highlights any tag in the working set that is monitored — a typo on a
monitored tag (`nswf`) saves fine but leaves the post visible, so the UI must
make "this tag is/isn't monitored" legible at a glance.

**A12 — Owner edit form requirement is N/A in the app (v1).** Contract §5 asks
clients to exclude mod tags from the owner's editable hashtag field. The app
has **no post-metadata edit form** (hashtags are set once at publish;
"Replace original" sends bytes only, no `PATCH /post/{id}` with hashtags
anywhere). Nothing to change; the artist still gets the read-only shield
marker on the detail page (A3), which is what the requirement protects. Noted
explicitly in the `0002` reply so the server team can close the item. If the
app ever grows a metadata editor, it must implement the exclusion.

**A13 — Editing state lives in a pure-Dart controller.** The sheet's working
set (add/remove/toggle/normalize/cap/diff) is a plain class in
`app/lib/club/edit/mod_hashtag_edit.dart`, unit-testable without widgets —
matching the repo's "Dart tests are pure unit tests" constraint.

**A14 — No push work.** The app has no FCM/MQTT client; notifications are a
polled list. The `mod_hashtags_updated` work is one `switch` case in
`notifications_page.dart` (diff read from `comment_preview`, per contract §7).
Unknown-type fallback already exists for older builds.

**A15 — Confirm before exposing** (review 2026-07-05, UX finding 1). Adding a
monitored tag hides a post; removing one re-exposes it publicly — wildly
asymmetric risk for symmetric gestures. When a Save would remove a monitored
tag from the mod set, the sheet interposes a confirmation dialog naming the
affected tags. The fast "add #nsfw" path stays one Save. Precedent:
`_detachMkpx`'s confirm in `artwork_detail_page.dart`.

**A16 — Persistent legend, not just a tooltip** (UX finding 2). When the
viewer is a moderator or the artist and the post has ≥1 mod tag, a small
always-visible caption "🛡 Tagged by a moderator" renders under the hashtag
row. Long-press tooltips are undiscoverable on phones, and the artist's
understanding of "why can't I control this tag" is the feature's whole
artist-facing story. The tooltip stays as a secondary hint.

**A17 — Anonymized moderator presentation** (UX finding 5). The notification
tile for `mod_hashtags_updated` shows a shield avatar and "A moderator changed
the hashtags on …" — never the acting moderator's handle/avatar, even if the
server populates actor fields. Keeps the tile's two halves consistent and
matches the contract's own impersonal framing.
