# German (de) review, pack 1 (messages 1–550)

Overall the pack is in good shape: "du" is used throughout, nouns are capitalized, „…" quotes and
the spaced `…` are applied consistently, all placeholders and plural branches are intact, and the
glossary terms are followed. The findings below are the exceptions.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| settingsMentionsSummary | low | The line addresses the user as "dich", then switches to "ich" in the option. In German this jump reads as a mistake; keep one perspective. | Wer dich erwähnen darf: {policy, select, following{Personen, denen ich folge} nobody{niemand} other{alle}} | Wer dich erwähnen darf: {policy, select, following{Personen, denen du folgst} nobody{niemand} other{alle}} |
| settingsPlayAnimationsSubtitle | low | "frame" is "Frame" everywhere else in the Club (artworkFrames, artworkColorsPerFrame). Here it is "Bild". | … zeigen sie nur ihr erstes Bild (nur auf diesem Gerät). | … zeigen sie nur ihren ersten Frame (nur auf diesem Gerät). |
| toolMoveShort | low | The tile says "Bewegen" but the tool's name, and every tip that refers to it ("Werkzeug Verschieben"), is "Verschieben". The user can't match the tile to the tips. If "Verschieben" fits the 48 px budget, use it. | Bewegen | Verschieben |
| commentsDeletedByMod | medium | Missing article: "von Moderator gelöscht" is ungrammatical. A gender-neutral collective also avoids implying one male moderator. | [von Moderator gelöscht] | [von der Moderation gelöscht] |
| commentsModDeleteBody | medium | The quoted tombstone must match commentsDeletedByMod; change both together. | … durch den Hinweis „[von Moderator gelöscht]“ ersetzt … | … durch den Hinweis „[von der Moderation gelöscht]“ ersetzt … |
| downloadUpscaledSubtitle | medium | "per Nächster-Nachbar" is ungrammatical: the noun phrase is undeclined and wrongly hyphenated. publishScaleTo uses "(nächster Nachbar)", so match it. | Vergrößerung per Nächster-Nachbar · WEBP | Vergrößert (nächster Nachbar) · WEBP |
| mentionNoMatch | medium | Unnatural. "Niemand … zum Erwähnen" isn't how a German UI reports an empty search. | Niemand mit diesem Namen zum Erwähnen. | Niemand mit diesem Namen gefunden. |
| playerMirror | low | The label is a verb, but its options ("Keine", "Beide") are noun-agreeing answers. The noun reads correctly with them. | Spiegeln | Spiegelung |
| onboardingProfileTitle | low | This heading is about twice the length of the English and will wrap on a phone. A shorter phrase keeps the meaning. | Gib deinem Profil eine persönliche Note (optional) | Persönliche Note (optional) |
| search | low | This is the page name as well as the tooltip. "Suche" is the usual German page title; "Suchen" reads as a button. | Suchen | Suche |
| aboutBody | low | "reagiere und kommentiere und sende" chains two "und"s. A list reads more smoothly. | … folge Künstlern, reagiere und kommentiere und sende Kunst an Makapix-Player. | … folge Künstlern, reagiere, kommentiere und sende Kunst an Makapix-Player. |
| avatarRemoveBody | low | "Das gilt sofort" is stiff. | Dein Profil zeigt stattdessen deinen Anfangsbuchstaben. Das gilt sofort. | Dein Profil zeigt stattdessen deinen Anfangsbuchstaben. Die Änderung gilt sofort. |
| statUnique | medium | Misleading: "Eindeutig" means "unambiguous" and doesn't convey "number of distinct viewers". | Eindeutig | Besucher |
| statUnique7d | medium | Same problem as statUnique. | Eindeutig (7 T.) | Besucher (7 T.) |

## Systemic notes

- **"Moderator" vs. "Moderation" in system text.** Tombstones and impersonal notices name a
  person with an article-less or generic masculine "Moderator" ("[von Moderator gelöscht]",
  "Ein Moderator hat …"). Where the text means "the moderation team", "die Moderation" is
  idiomatic German, gender-neutral, and needs no article juggling. Apply this at least to the
  tombstone and anything quoted from it. "Ein Moderator hat …" in notifications is acceptable.
- **Generic masculine "der Künstler".** artworkNoRemixes uses it here, and the other packs do too
  (layersNotRemixable, publishRemixOffBody, pendingRejected, modPromoteBody). Elsewhere the pack
  already uses neutral wording ("Die Person kann …", blockConfirmBody). If the project wants
  consistency, rephrase these impersonally, e.g. "Remixe sind für dieses Werk nicht erlaubt". This
  is a style decision, not an error; record it in GLOSSARY.md either way.
- **One word per concept: Move vs. shift, frame, nearest neighbor.**
  - Move/shift: the Move tool is "Verschieben" in full but "Bewegen" on its tile. The glossary's
    "shift" (move items one position) is also "verschieben", and de-3's `barShift` is
    "Verschieben". The Move tool and the shift action therefore share a label. Make the tile
    label match the tool name, and give shift a different word on the Frames and Layers pages,
    e.g. "Versetzen".
  - Frame: "Frame" is the glossary term, but a few Club strings fall back to "Bild".
  - Nearest neighbor: render it one way everywhere ("nächster Nachbar").
- **"posten" vs. "veröffentlichen".** The glossary verb is "veröffentlichen". This pack and de-2
  mix in "posten" ("Darf öffentlich posten", "Im Club posten", "Als neuen Beitrag posten"). It
  reads naturally and fits tight labels better, so this needs no change. If it stays, add it to
  the glossary as the accepted short form.
