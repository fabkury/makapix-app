# Store listing review: French (fr-FR)

| field | severity | problem | current | proposed |
|---|---|---|---|---|
| fullDescription | medium | "L'art d'un lecteur" is a word-for-word rendering of "Art on a player" and reads as translationese; French says what the player shows. | L'art d'un lecteur se met à jour en direct depuis le Club | Les œuvres affichées sur un lecteur se mettent à jour en direct depuis le Club |
| fullDescription | medium | "fichier avec calques modifiable" stacks the adjective awkwardly after "calques" (it agrees with "fichier" but reads as if it qualified the layers), and "partiez de la vraie source" is a literal echo of "build on the real source". | Les artistes peuvent joindre leur fichier avec calques modifiable, pour que vous partiez de la vraie source | Les artistes peuvent joindre leur fichier avec calques, entièrement modifiable, pour que vous repartiez de la source d'origine |
| fullDescription | low | The space before ":" is a plain space (U+0020); the glossary asks for a no-break space (U+00A0), so the colon cannot wrap to the next line on its own. | Remix : (U+0020 before the colon) | Remix : (U+00A0 before the colon) |
| fullDescription | low | The opening sentence leaves "intégré" dangling after a long noun phrase and repeats "pixel art" twice in a row of complements; a verb reads more naturally. | Makapix Club est une communauté de pixel art avec un éditeur complet de pixel art animé intégré. | Makapix Club est une communauté de pixel art qui intègre un éditeur complet de pixel art animé. |
| fullDescription | low | "Import GIF, …" / "Export PNG, …" read as English verbs left untranslated; the other bullets use the imperative ("Parcourez", "Suivez", "Publiez"). | Import GIF, PNG, APNG, JPEG, BMP et WebP / Export PNG, GIF et WebP sans perte | Importez des fichiers GIF, PNG, APNG, JPEG, BMP et WebP / Exportez en PNG, GIF et WebP sans perte |
| fullDescription | low | "sans compte pour dessiner" is slightly ambiguous ("without an account in order to draw"); the English means no account is required. | Fonctionne entièrement hors ligne, sans compte pour dessiner | Fonctionne entièrement hors ligne, aucun compte requis pour dessiner |
| fullDescription | low | "En English" clashes once the list starts with an English word; a label avoids the preposition while keeping the native names. | En English, Español, Português, Français, Deutsch, Русский, 日本語 et 简体中文. | Disponible en : English, Español, Português, Français, Deutsch, Русский, 日本語 et 简体中文. (U+00A0 before the colon) |

Length limits: title 24/30, shortDescription 77/80, fullDescription 1,369/4,000; all within limits.

**Verdict.** A sound, accurate translation that follows the glossary (fil, œuvre, publier,
lecteur, calque, toile, image for frame, vous). No meaning errors. The two medium items are
literal phrasings worth rewording before release; the rest is polish.
