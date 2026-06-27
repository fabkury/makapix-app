# C3 — Edit & Remix

**Phase:** C3 of the Makapix Club social pillar (SPEC-CLUB §28, §9).
**Status:** 🟡 in progress — see [Progress](#progress).
**Depends on:** C1 (Post/detail), C2 (publish flow + upload_api). **Last updated:** 2026-06-26.

---

## 1. Goal & acceptance

Open any Club artwork in the Makapix Editor, edit it, then either **replace the original** (owner) or
**post as new** (anyone — a remix). This is the native realization of the website's "Edit in Piskel/PixelC" +
`PISKEL_REPLACE`/`PISKEL_EXPORT` protocol, in-process (no iframe).

**Acceptance:**
- **Tier-1:** the edit-bridge model + permission logic unit-tested; `flutter analyze` clean for lib/club.
- **Build:** `flutter build apk --debug` green.
- **Device (user):** open a post → "Edit in Makapix" → the artwork loads into the editor → edit → "Post to
  Club" offers **Replace original** (own posts) and **Post as new**; both reach `development.makapix.club`.

**Non-goals (deferred):** non-owner replace via "allow others to edit" (the flag isn't exposed on the Post
payload — only the owner gets Replace client-side; non-owners use Post-as-new, the main remix path; the server
still enforces permission); a first-class remix edge (server has none — provenance by convention, §5).

## 2. The two flows

**Open (club → editor):**
1. On the artwork detail, **Edit in Makapix** (shown to everyone — remix-friendly).
2. Download the native bytes (GET the post's `art_url`; webp/gif/png — the codec decodes all).
3. Hand them to the editor via a Riverpod **bridge** (§3); the editor loads them as a fresh document and
   remembers the source (post id, sqid, title, isOwner).

**Finish (editor → club):**
- **Replace original** (owner): re-export → `POST /post/{id}/replace-artwork` (multipart `image`). Keeps the
  post, its reactions/comments/stats; bumps `artwork_modified_at` (players resync).
- **Post as new** (anyone): the C2 publish flow, pre-filled (title "Remix of …" by convention, §5).

## 3. The club↔editor bridge (no engine import in lib/club)

- `club/edit/club_edit_request.dart` — `ClubEditRequest { Uint8List bytes; int sourcePostId; String sourceSqid;
  String title; bool isOwner; }`.
- `club/state/edit_bridge.dart` — `pendingClubEditProvider` (`StateProvider<ClubEditRequest?>`) +
  `clubEditSourceProvider` (`StateProvider<ClubEditSource?>` the editor sets while editing a Club post, read by
  the publish flow to offer Replace).
- **Editor side (`main.dart`, becomes a `ConsumerStatefulWidget`):** watches `pendingClubEditProvider`; when
  set, confirms (discard current doc?), loads the bytes into the engine (§4), records the source into
  `clubEditSourceProvider`, clears the pending request, and pops back to the editor.
- **Club detail side:** "Edit in Makapix" downloads bytes → sets `pendingClubEditProvider` →
  `Navigator.popUntil(root)` so the editor (root) surfaces and consumes it.

## 4. Engine load (the risky bit — device-verified)

The engine has `Engine(w,h)` (ctor), `importImage(bytes, mode, asLayer, startFrame, crop…)`, `load(mkpx)`.
To open a Club artwork as a fresh document:
1. decode dimensions (Flutter `ui.instantiateImageCodec` — already used by the editor) to get w,h (+ frame
   count for animations);
2. recreate the engine at (w,h) (the editor's "new document" path), then `importImage(bytes, mode: Fit,
   asLayer: false, startFrame: 0)` to bring in the (possibly animated) frames.
This reuses the editor's existing import machinery. **Fidelity (frame timing, transparency) is verified on
device** — noted as the one device-bound risk. (A future engine `open_image_as_document` FFI would make this
exact; out of scope here.)

## 5. Provenance (convention)

Server has no remix edge. Post-as-new pre-fills the description with `Remix of {original title} by
@{owner}` and (optionally) a `remix` hashtag, so lineage is human-visible. Tracked as a server ask
(SPEC-CLUB brief §7.4) for a real edge later.

## 6. API additions
- `UploadApi.replaceArtwork(postId, bytes, filename) → Post` (`POST /post/{id}/replace-artwork`, multipart).
- `EditApi.downloadArtwork(artUrl) → Uint8List` (plain dio GET of the vault URL; no auth needed).

## 7. Tests (Tier-1)
- `club_edit_request_test` — model holds bytes/source/isOwner.
- permission: owner detection (me.sub == owner.sqid) → Replace offered; else only Post-as-new.

## 8. Risks
- **Engine load fidelity** — animations/transparency must survive download→import; device-verified.
- **Discard-current-work** — opening a Club artwork replaces the editor's doc → a confirm dialog guards it.
- **allow-others-to-edit not on the payload** → non-owner Replace deferred; Post-as-new covers remix.
- Editor becomes a `ConsumerStatefulWidget` — keep the existing engine/UI behavior intact.

---

## Progress
- [ ] Plan written + self-reviewed
- [ ] edit bridge model + providers + replace/download API
- [ ] detail page "Edit in Makapix"; publish "Replace original" + remix pre-fill
- [ ] editor consumes pending edit (load + provenance); ConsumerStatefulWidget
- [ ] analyze + test + Android build; C3 acceptance

### Notes / findings
- (none yet)
