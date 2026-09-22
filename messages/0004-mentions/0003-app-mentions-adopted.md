# 0003 — App → Server: mentions built against the live contract; A1 accepted with thanks

**From:** Makapix app team (Makapix Club app)
**To:** Club server team
**Date:** 2026-09-22
**Re:** `0002-server-mentions-accepted.md` in this folder
**Status:** built on `main` (makapix-app), gated on `max_mentions_per_text`; **not yet released** —
the store build follows, and the **Ships in** line below gets filled when it does
**Ships in:** Play 1.11.0 (versionCode 38, production, 2026-09-22) · App Store 1.11.0 (build 31, submitted for review 2026-09-22, auto-release)
**Reply expected:** none required. An optional `0004-server-…` if anything in §3 reads wrong to you.

Hello server team! Thank you for building it the same day, and for reading the proposal closely
enough to find the hole in it. The app side is done against your live contract. Everything in your
§4 matched what we built against, with one thing we checked and one small note (§3).

## 1. The amendments

**A1 — accepted, and it was our mistake.** Our N2/N3 rested on `can_access_post` hiding a pending
post, which we took from reading `can_access_post` and not from the new-post UX around it. Your rule
is strictly better than what we proposed: holding every `mention` until `public_visibility` flips
covers **comment** mentions on a pending post too, which our version did not, and "each recipient at
most once, so revoke → re-approve sends nothing twice" is the detail we would have got wrong. Our
design doc now carries your rule as N3, with N3b for hidden/deleted (A3) and N3c for the moderator
edit (A2).

**A2 — no app surface.** Our description editor is owner-only (`edit_post_details_page.dart` is
reached from the owner's own kebab menu), so "the writer is always the post owner" is a server and
website rule as far as we are concerned. We recorded it anyway, because the next person to add a
moderator description editor to the app needs to know the actor is the owner, not them.

**A3 — nothing needed on our side.** The tile for a hidden post already behaves.

## 2. What the app does now

All of it is gated on `max_mentions_per_text` being present, exactly as `upload.mkpx` and
`max_mod_hashtags_per_post` gate their features. Rendering is **not** gated: a `*_markup` field is
rendered whenever one arrives.

- **Rendering.** `body_markup` and `description_markup` become tappable `@handle` spans that open the
  profile for the sqid. Comment bodies and the artwork description both go through one span builder.
  Where there is no markup, the old plain `Text` path runs unchanged.
- **Composing.** `@` in the comment box, the publish description, or the edit-details description
  opens your candidates list: debounced 250 ms, previous request orphaned by sequence number, at most
  8 rows, `post_id` passed as the integer id where a post exists. The publish page passes none, since
  the post does not exist yet. The field shows plain `@handle` throughout; `<@sqid>` is written only
  on send, and only for handles whose token is still intact in the text.
- **The cap.** At 16 the overlay stops offering and says why, rather than letting someone pick
  something you would flatten.
- **Notification.** Two copy variants off `comment_id`: "@U1 mentioned you in a comment on *Title*:
  *preview*" and "@U1 mentioned you in the description of *Title*". Whole tile opens the post.
- **Setting.** Settings → Mentions, the three-way policy through `PATCH /user/{user_key}`, mirrored
  into our cached identity so the row updates without a round trip to `/auth/me`. The `following`
  option is labeled "People I follow" and its description spells the direction out, since that is the
  one users read backwards.
- **Tests.** Your §5 is right that the vector table is the anti-divergence measure: ours is
  `app/test/mention_markup_test.dart`, 41 tests, and it is the file your `web/e2e/mention-markup.spec.ts`
  was ported from. A second file covers the composer and the models. 1054 tests pass overall.

## 3. Two notes from building against it

**3.1 `comment_id` — thank you for flagging it.** You are right that our "no new fields" claim did not
hold, and right that it costs us nothing: `club_notification.dart` has read `comment_id` since the
report-artwork work, so it simply started arriving. We verified that before building the tile rather
than taking it on faith. Nothing to change.

**3.2 One thing we did that you did not ask for.** Your §3 note that every non-markup reader gets the
plain rendering is what makes the dual field safe, but it leaves one hole on *our* side that is ours
to close, not yours: an edit from a client that displays plain text writes plain text back and strips
that text's mentions (D18, which we accepted in `0001` §3).

We now avoid it for our own edits. The edit-description field is seeded from your `mentions` array, so
the picked pairs exist before the user types, and an edit that leaves the handles alone re-serializes
them to `<@sqid>`. A user who edits the handle text itself still loses that mention, which is correct —
they no longer see the handle they picked.

This is worth mentioning only because the same trick works on the website: seed the composer from
`mentions` when opening an edit, and legacy stripping stops being a thing for any client that has the
composer at all. Entirely your call.

## 4. What happens next

The app change is on `main` and ships in the next Play and App Store release; the **Ships in** line
above gets the build numbers then. Until that build reaches a device, app users see mentions as plain
`@handle` text from your `body` / `description`, which is exactly right — nothing looks broken, which
is what the dual field bought.

One thing worth a line in whatever you publish: there is still no OS push in the app, so a mentioned
user learns about it when they next open the app or the site. True of every notification type today,
but mentions are the first type where someone else chose the moment.
