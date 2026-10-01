# French (fr): second-pass review of the rewrites

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| editDetailsModTags | medium | Still says "tags", while the rewrites of `modTagsAddLabel` and `artworkTaggedByMod` moved to "hashtags" for the same thing; the bare "Ajoutés" also opens with no noun to agree with. | Ajoutés par un modérateur : ces tags ne peuvent pas être modifiés. | Hashtags ajoutés par un modérateur : ils ne peuvent pas être modifiés. |
| tipCopyPaste | medium | The four option names are lowercase. The glossary rule says tips capitalize option names as on screen (chips `Copier`, `Couper`, `Coller`, `Effacer`), and the same message capitalizes "Coller" in its last sentence. | Copier, couper, coller ou effacer la sélection. Source : calque ou image entière. Coller dépose une ébauche déplaçable. | Copier, Couper, Coller ou Effacer la sélection. Source : calque ou image entière. Coller dépose une ébauche déplaçable. |
| tipMove | low | "démultiplier" is technically right (gear reduction), but many readers take it as "multiply/amplify", the opposite of what Slow does. Here, unlike `optSlowTip`, nothing follows to explain it. | … Lent démultiplie le geste. | … Lent rend le geste plus précis. |
| mirrorMoveAxisBody | low | Same ambiguity with "démultiplie" as in `tipMove`. | Faites glisser n'importe où sur la toile ; Lent démultiplie le geste ; touchez la poignée pour saisir une valeur | Faites glisser n'importe où sur la toile ; Lent rend le geste plus précis ; touchez la poignée pour saisir une valeur |
| tipFlip | low | The switch to the imperative leaves the second sentence ("Agit…") with no subject, so it reads as a fragment after "Retournez". | Retournez le calque horizontalement ou verticalement. Agit sur la sélection s'il y en a une. | Retournez le calque horizontalement ou verticalement, ou la sélection s'il y en a une. |
| placeReachHint | low | "y accèdent" makes the tool and the view the ones doing the reaching, which sounds odd. The old "y donnent accès" was more natural. | L'outil Déplacer et la vue Zone hors toile y accèdent. | L'outil Déplacer et la vue Zone hors toile y donnent accès. |

Checked 76 messages.
