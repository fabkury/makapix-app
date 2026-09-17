# 0001 — App → Server: the app now promotes to `frontpage` only (FYI)

**From:** Makapix app team (Makapix Club app)
**To:** Club server team
**Date:** 2026-09-17
**Re:** `POST /post/{id}/promote` — the `category` field
**Status:** on `main` — commit `a25bc458` (makapix-app); ships in the next Play/App Store release
**Reply expected:** none required — an optional `0002-server-…` in this folder if you decide to
prune or finish the categories

Hello server team! Pure FYI, nothing to change on your side unless you want to.

## What changed in the app

The moderator **Promote** dialog on the artwork page used to offer the four slugs the endpoint
accepts (`frontpage` · `editor-pick` · `weekly-pack` · `daily's-best`). It is now a plain
"Promote this post?" confirmation and the app always sends `{"category": "frontpage"}` — the
same body the website's detail page and mod dashboard hard-code.

Posts already carrying one of the other three slugs still render by name in the app's
moderator-only status chip ("Promoted · Weekly Pack") and in the demote confirmation. Nothing
else in the app reads the category.

## Why

We traced what the server does with `promoted_category` (checkout at `9489af9`):

- `POST /post/{id}/promote` stores the slug and uses it once, as the display name in the
  owner's `post_promoted` notification preview.
- `GET /feed/promoted`, `GET /post?promoted=true`, the players' `promoted` channel, the
  own-profile visibility rule, and the detail-page "approved-or-promoted" gate all filter on the
  `promoted` boolean only. No query touches `promoted_category`.
- The `/category/{name}/follow` router and `category_follows` table exist, but nothing publishes
  to followers (the promote handler still carries `TODO: Publish MQTT notification`), and
  neither client offers a follow-category control. The only reader of the table is
  account-deletion cleanup.

So from a moderator's chair the four choices were indistinguishable except for one word in the
artist's notification (which the app's notification list elides anyway). Offering a choice with
no effect read as a bug, hence the removal.

## Anything to do?

No. Two optional thoughts, entirely your call:

1. If categories are not coming back, the `Literal[...]` on `PromotePostRequest.category` could
   shrink to `frontpage`, and the category-follow router could retire with the MQTT plan.
2. If they are, the feed side needs a per-category surface (a `category=` filter on
   `/feed/promoted` or a `/feed/category/{name}`) before either client can meaningfully offer the
   choice again — tell us and we will wire the dialog back up.
