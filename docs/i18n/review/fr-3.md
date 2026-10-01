# French review: pack fr-3 (messages 1101–1645)

Independent review of the French translation, pack 3 (editor: menus, import/crop/place, Frames and
Layers pages, blend modes, palettes, patterns and dither, keyboard shortcuts, replay and timelapse).
No-break spaces before `:` `;` `!` `?` and inside « » were checked mechanically: none missing.
Every placeholder and plural branch is present.

## Messages 1101–1200

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| layerMoveGroupTip | medium | A subjectless plural verb ("Se déplacent…"): a fragment no French tooltip would use. Name the subject. | Se déplacent ensemble avec l'outil Déplacer (quand rien n'est sélectionné) | Calques déplacés ensemble par l'outil Déplacer (quand rien n'est sélectionné) |
| frameDeleteAgain | low | The button label quoted in running text needs quotation marks; without them "Supprimer l'image … supprimer l'image" reads as a stutter. | Appuyez de nouveau sur Supprimer l'image pour supprimer l'image {number} | Appuyez de nouveau sur « Supprimer l'image » pour supprimer l'image {number} |
| toolNoteOn | low | The note sits beside "Pelure d'oignon" (feminine): what is switched on is the onion skin, so the agreement is "activée". | activé | activée |
| clubSizeNearest | low | "Proche :" on its own is clipped; "la plus proche" is the meaning and still short. | Hors format Club. Proche : {width} × {height} | Hors format Club. Le plus proche : {width} × {height} |
| clubSizeAlert | medium | "elle" has no antecedent: the only noun before it is the plural "les œuvres". Name the drawing. | Makapix Club n'accepte pas les œuvres de {width} × {height} : elle ne pourra pas être publiée sur le Club à cette taille. | Makapix Club n'accepte pas les œuvres de {width} × {height} : ce dessin ne pourra pas être publié sur le Club à cette taille. |

## Messages 1201–1300

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| openOverMax | low | "la" has no feminine antecedent in the sentence (it starts with the dimensions), and the menu item should be quoted. | {width}×{height} dépasse le maximum de {max}×{max}. Utilisez Importer une image… pour la redimensionner ou la rogner. | L'image ({width}×{height}) dépasse le maximum de {max}×{max}. Utilisez « Importer une image… » pour la redimensionner ou la rogner. |
| outgoingDiscard | medium | Discard is "Abandonner" elsewhere (commonDiscard, commonDiscardTitle). "Supprimer" is the word for Delete, which here is a different action (drawingDelete*). | Le supprimer | L'abandonner |
| discardDrawingTitle | medium | Same text as drawingDeleteTitle ("Supprimer « {name} » ?"), so the two dialogs can't be told apart; Discard is "Abandonner" in the rest of the app. | Supprimer « {name} » ? | Abandonner « {name} » ? |
| discardDrawingBody | low | "Il" has no antecedent: the title only gives the name. | Il ne sera pas conservé dans Mes dessins. Cette action est irréversible. | Ce dessin ne sera pas conservé dans Mes dessins. Cette action est irréversible. |
| nudgeLeft, nudgeUp, nudgeDown, nudgeRight | low | "Gauche 1 px" copies the English word order; French puts the distance first. | Gauche 1 px (maintenir pour répéter) | 1 px à gauche (maintenir pour répéter); likewise 1 px vers le haut / vers le bas / à droite |
| cropResultDownscaled | low | "réduit" (masculine) beside its sibling lines' "placée" (feminine) for the same implicit subject. | (réduit pour tenir dans {canvasWidth}×{canvasHeight}) | (réduite pour tenir dans {canvasWidth}×{canvasHeight}) |
| cropResultBeyond | medium | "La partie éloignée" ("the distant part") doesn't say which part, and "at import" was dropped, so it reads as if something has already been deleted. | En 1:1 : {width} × {height} px, plus grand que la zone hors toile. La partie éloignée est supprimée. | En 1:1 : {width} × {height} px, plus grand que la zone hors toile. Le surplus sera perdu à l'import. |

## Messages 1301–1400

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| placeParked | low | "Parked" means kept off-canvas; the translation drops "kept", which is the reassuring half of the line. | Hors toile : {edges}. | Conservé hors toile : {edges}. |
| placeDroppedStorage | medium | Identical to placeDroppedCanvas: the reason (beyond the storage area vs. beyond the canvas) is lost, and "Supprimé" suggests something was deleted rather than not imported. | Supprimé : {edges}. | Perdu au-delà de la zone disponible : {edges}. |
| placeDroppedCanvas | medium | See placeDroppedStorage. | Supprimé : {edges}. | Perdu au-delà de la toile : {edges}. |
| placeReachHint | low | A bare infinitive as the subject ("Déplacer et la vue…") reads as a verb, not as the tool. | Déplacer et la vue Zone hors toile y donnent accès. | L'outil Déplacer et la vue Zone hors toile y accèdent. |
| framesLayerNameHits | medium | Agreement breaks in the `other` branch when {hits} is 1 ("Dans 1 images sur 5 sélectionnées"): the noun follows {hits}, not {count}. | one{Dans {hits} image sur {count} sélectionnée} other{Dans {hits} images sur {count} sélectionnées} | one{Présent dans {hits} image sélectionnée sur {count}} other{Présent dans {hits} des {count} images sélectionnées} |
| framesScaleRange | low | French writes the decimal comma (0,1). Check first that the factor field accepts a comma; if it accepts only a dot, keep 0.1. | De 0.1 à 10 | De 0,1 à 10 |
| layersMergeGap | low | "a un trou" is colloquial for a gap in a selection. | La fusion exige des calques voisins : la sélection a un trou. | La fusion exige des calques voisins : la sélection est discontinue. |
| layersCopiedToFrames | low | "Copié" (masculine singular) has no subject, and several layers may have been copied. | Copié vers {count} image / Copié vers {count} images | Copie effectuée vers {count} image / Copie effectuée vers {count} images |

## Messages 1401–1500

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| layersPickBlend | low | "non normale" reads as "abnormal"; the meaning is "a mode other than Normal". | Fusion non normale | Fusion autre que Normal |
| layersBiggerRows / layersSmallerRows | low | The rows get taller or shorter, not bigger or smaller all round. | Lignes plus grandes / Lignes plus petites | Lignes plus hautes / Lignes moins hautes |
| layersClear | low | Erasing a layer's pixels is "Effacer" in French image editors and in this app's own optClear; "Vider" is fine for the palette (paletteClear), which empties a list. | Vider | Effacer |
| layersBlendTitle | low | "Fusion de 1 calque" reads like "merging 1 layer" (Fusionner is the Merge button on the same page); the heading lists blend modes. | Fusion de {count} calque / Fusion de {count} calques | Mode de fusion de {count} calque / Mode de fusion de {count} calques |

## Messages 1501–1645

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| pickColorTitle | low | The title lost its verb; the keyboard command (kbPickColor) uses one. | Couleur | Choisir une couleur |
| pickSourcePrev | low | A tiny label under a swatch, "one short word": "Précédente" is 10 letters against the English 4. | Précédente | Préc. |
| patInverse | low | "inversé" is masculine singular but the pattern names vary in gender and number (Diagonale, Grille, Points, Hachures croisées…). "inverse" agrees with all of them in a parenthetical tag. | {name} (inversé) | {name} (inverse) |
| ditherHintOff | low | For a smooth transition the natural French word is "dégradé"; "rampe" (the glossary's term for a palette run of one hue) sounds odd here. | Une rampe lisse entre les couleurs | Un dégradé lisse entre les couleurs |
| memBlocked | medium | "ferait dépasser au dessin la limite" is clumsy, and "Réduisez les images" reads as "shrink the pictures" rather than "use fewer frames". | Bloqué : cette modification ferait dépasser au dessin la limite de mémoire. Réduisez les images, les calques ou la taille de la toile pour continuer à l'agrandir. | Bloqué : avec cette modification, le dessin dépasserait la limite de mémoire. Réduisez le nombre d'images ou de calques, ou la taille de la toile, pour continuer à l'agrandir. |

## Systemic notes

1. **Discard vs. Delete.** The app's Discard is "Abandonner" (commonDiscard), but the outgoing-drawing
   dialogs here use "Supprimer". That word belongs to Delete, so discardDrawingTitle and
   drawingDeleteTitle end up with the same text. Use "Abandonner" for every Discard.
2. **"image" = frame is ambiguous in some sentences.** The glossary choice is standard in French
   animation software and should stay. Where "image" (frame) appears next to the picture sense or a
   size verb, though, rephrase so it reads as a count of frames ("le nombre d'images"). Examples:
   memBlocked "Réduisez les images", and the import and place lines, where "l'image" is the imported
   picture. Watch for this in future strings.
3. **Implicit-subject participles and pronouns.** Several short lines drop their subject and then use
   a gendered participle or pronoun with no antecedent: layerMoveGroupTip, clubSizeAlert "elle",
   discardDrawingBody "Il", layersCopiedToFrames "Copié", patInverse "inversé", cropResultDownscaled
   "réduit" beside "placée". Either name the subject or pick a form that doesn't vary in gender
   ("inverse", "Copie effectuée"). In plurals, make sure the noun agrees with the number in front of
   it (framesLayerNameHits).
4. **Distinct English messages collapsed into one French text.** placeDroppedStorage and
   placeDroppedCanvas are both "Supprimé : {edges}.", and cropResultBeyond dropped "at import". When
   two keys exist because they mean different things, the French should keep the difference.
5. **Menu labels quoted in running text** (frameDeleteAgain, openOverMax) should be in « », as French
   software does, so the user sees which control is meant.
6. Mechanical checks passed: every no-break space before `: ; ! ?` and inside « » is present, the
   ellipsis is always `…`, every placeholder and plural branch is present, the blend-mode names follow
   Photoshop FR, and the ten blend badges are unique.
