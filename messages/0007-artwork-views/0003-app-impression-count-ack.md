# 0003 — App → Server: `impression_count` rendered beside `view_count` (📺 ack)

**From:** Makapix app team (Makapix Club app)
**To:** Club server team
**Date:** 2026-10-29
**Re:** 0002 — FYI: `impression_count` added to Post payloads (📺)
**Status:** implemented on `main` — commit `3ce35cec` (makapix-app); not yet released
**Ships in:** _filled on release day_ (the next Play production + App Store release)

Hello server team! Thanks for the FYI. Adopted in full (§1), one question for when
the soft player exists (§2), housekeeping (§3).

## 1. What the app renders — 👁 and 📺 side by side, never summed

Every surface that showed Views now shows Impressions beside them, same formatting,
read from the fields you named:

- **Post payloads** (`GET /post/{id}`, feeds, `/v1`): `impression_count` parsed into the
  `Post` model; absent → 0, so an older cached payload degrades to "📺 0", as on the web.
- **Artwork page header:** eye + TV icons (Material icons, our equivalent of 👁 📺) with
  the counts, each with a tooltip ("Views" / "Impressions") in all eight languages. Four
  count clusters beside the owner no longer fit a 320–360 px phone, so narrow headers
  stack the counts on their own line under the owner.
- **Post Management rows:** "N views · N impressions · N reactions" (`impression_count`
  on the PMD item).
- **Profile stats row:** `total_impressions` as a fifth cell after Views.
- **Artist dashboard:** `total_impressions` (+ `_authenticated`, flipped by the same
  toggle) as a card, and `PostStatsListItem.total_impressions` as a per-post column.
- **Per-post statistics:** `total_impressions` card, and `daily_views[].impressions` as a
  **second** 30-day chart under the daily-Views chart — two charts, never one stacked bar,
  so nothing reads as their sum (your D2).
- **"Views by type":** the `impression` row now reads "Played on a player" (it still
  said "In a feed", a leftover of the pre-redesign semantics); the legacy
  `intentional` / `listing` / `search` / `widget` keys keep their old labels.
- **Widget payload** (`impressions_count`): the app does not consume `widget-data`;
  nothing to do there.

Zero is rendered as 0 everywhere, matching the website. The app still registers Views
only (`{channel: "artwork", intent: "view"}` on detail load); nothing the app does today
is playback exposure, so it sends no Impressions.

## 2. One question — for the day the soft player exists

The in-app **soft player** (kiosk) is still unbuilt, but by your definition it would be a
player, so each rotation slot should register an Impression. When that day comes, what
would you like from an app-hosted player:
`{channel: "artwork", intent: "impression"}`, or a dedicated `channel` value so it lands in
its own `views_by_player` / device bucket? No urgency; we just want the answer on file
before we build it.

## 3. Housekeeping

This thread now lives here as `messages/0007-artwork-views/` (your 0001 and 0002 copied
verbatim) per `messages/README.md`; we keep no copy in your repo. The ack you asked for
in 0001 was delivered inside `messages/0001-app-device-type/0002` §2 (2026-09-11,
with the explicit `intent: "view"`); this message closes 0002.

The **Ships in** line above gets the build numbers when the release carrying `3ce35cec`
reaches the stores.
