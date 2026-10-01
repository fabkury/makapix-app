# Spanish review, part 3 of 3 (messages 1101–1645)

Independent review of the `es` translation against `docs/i18n/GLOSSARY.md`. Only real problems are listed.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| toolNoteOn | low | The note sits beside the Onion skin tool, "Papel cebolla" (masculine); the feminine reads as a mismatch next to it. | activada | activado |
| shareCanceled | low | "Envío" suggests sending a message and breaks the pattern of the neighbors (`exportCanceled` "Exportación cancelada", `shareFailedShort` "Error al compartir"). | Se canceló el envío | Compartir cancelado |
| previewTruncated | medium | On the crop page "recortada" reads as "cropped" (the page's own verb is Recortar), not "truncated to fewer frames". `previewCut` already says "parcial". | Vista previa recortada: la animación completa se importa igualmente. | Vista previa parcial: la animación completa se importa igualmente. |
| cropResultBeyond | low | "Zona exterior" is the name given to the Overscan view option (`viewOverscanOn`); here the English means the off-canvas storage area, which the glossary and the neighbors call "fuera del lienzo". | …mayor que la zona exterior. La parte más lejana se descarta al importar. | …mayor que la zona fuera del lienzo. La parte más lejana se descarta al importar. |
| placeParked | low | Drops "parked/kept": the line no longer says this part is preserved, which is its whole contrast with the "Se pierde" line below it. | Fuera del lienzo: {edges}. | Se conserva fuera del lienzo: {edges}. |
| framesIdleHint | low | Two imperatives followed by a noun phrase ("doble toque"); elsewhere the gesture is "toca dos veces" (`viewHintCrop`). Also about 40 % longer than the English for a two-line slot. | Toca o desliza para seleccionar · mantén pulsado para ver opciones · doble toque para ir | Toca o desliza para seleccionar · mantén pulsado para opciones · toca dos veces para ir |
| layersIdleHint | low | Same mixed form; and "activar" alone can be read as "switch on/show" rather than "make it the layer you draw on" (glossary: active = activa). | …· mantén pulsado para ver opciones · doble toque para activar | …· mantén pulsado para opciones · toca dos veces para hacerla activa |
| layersMakeActive | low | "Activar" on a layer is ambiguous next to Visible/Bloqueada (enable? show?). The glossary term is the adjective "activa". | Activar | Hacer activa |
| batchUndoHolds | low | "Conservará" does not convey memory use; a reader may take it as "undo will keep (restore) N MB". | Deshacer conservará unos {size} MB | Deshacer ocupará unos {size} MB de memoria |
| framesShiftMoves | low | Bare number after the verb reads oddly, especially when negative ("Se desplaza -3"). A noun label avoids it and needs no plural. | Se desplaza {count} | Desplazamiento: {count} |
| framesShiftClamped | low | Same as `framesShiftMoves`. | Se desplaza {count} (pediste {requested}) | Desplazamiento: {count} (pediste {requested}) |
| layersLockedNote | low | Much longer than the English for a "two short lines on a phone" slot. | …está bloqueada: estas acciones no están disponibles / …están bloqueadas: estas acciones no están disponibles | …está bloqueada: acciones no disponibles / …están bloqueadas: acciones no disponibles |
| layersToTop | low | "Arriba del todo" is colloquial Peninsular usage; a neutral wording exists. | Mover arriba del todo | Mover a la parte superior |
| layersToBottom | low | Same as `layersToTop`. | Mover abajo del todo | Mover a la parte inferior |
| patFamilyDiagonals | low | "Trama" is already the Screen blend mode (`blendScreen`) and the root of "tramado" (dither); a third use for crosshatch on the Patterns page, which sits next to the Dither page, blurs the terms. | Diagonales y trama cruzada | Diagonales y rayado cruzado |
| patCrosshatch | low | Same as `patFamilyDiagonals`; "rayado" is also the word `ditherHintHatch` already uses for hatching. | Trama cruzada · {size} px | Rayado cruzado · {size} px |
| ditherFamilyBayer | low | A person's name after a noun phrase needs "de". | Tramado ordenado Bayer | Tramado ordenado de Bayer |
| kbHeldKeys | medium | "Teclas mantenidas" is not idiomatic; the participle needs its complement (the app itself says "mantén pulsado"). | Teclas mantenidas | Teclas mantenidas pulsadas |
| kbPanCanvas | low | "Desplazar" is the glossary word for Shift (move frames or layers one position) and is also used for scrolling (`viewHintCrop`); a third meaning on the shortcuts page, which lists frame commands too. The context itself says "moves the view". | Desplazar el lienzo | Mover la vista |
| keyEnter | low | "Intro" is the Spain keyboard legend; Latin American keyboards print "Enter", which every Spanish speaker also understands. For neutral international Spanish "Enter" is the safer name. | Intro | Enter |
| replayOlderTip | low | Agreement: the chip it explains is "Grabación antigua" (feminine). | Grabado antes de una actualización del editor. … | Grabada antes de una actualización del editor. … |
| replayNoHistory | low | "Repetir" is the Repeat action (`toolRepeat`); "a history that can be repeated" reads as re-applying operations, not playing them back. | Este dibujo aún no tiene un historial que se pueda repetir. | Este dibujo aún no tiene un historial que se pueda reproducir. |
| timelapseLongBody | low | "Vídeo" (accented) is the Spain-only spelling; "video" is used across Latin America and is equally valid for the RAE, so it is the neutral choice. | …(un vídeo largo que quizá supere… | …(un video largo que quizá supere… |

<!-- batch 5 (1536–1645) done -->

## Systemic notes

Overall this part is in good shape: no meaning errors, every placeholder and plural branch is intact and
grammatical, `¿…?` / `¡…!` are opened correctly, quotes are consistently «…», the ellipsis is always `…`,
the address is consistently "tú", and the glossary terms (fotograma, capa, lienzo, pila, boceto, combinar,
tramado, degradado, Supr, ON/OFF) are applied without exception. 23 findings: 0 high, 2 medium, 21 low.

1. **"Repetición" (replay) collides with "Repetir" (Repeat).** The glossary renders replay as "repetición"
   while the Repeat action is "Repetir" and the Frames page has "Repetir después". Titles such as "Ver
   repetición" work (the sports-broadcast sense), but derived wording breaks down: "un historial que se
   pueda repetir" (`replayNoHistory`) says "re-apply", and "Este dibujo aún no tiene repetición" is vague.
   If the glossary is ever reopened, keeping "replay" untranslated (as Portuguese and French do) or using
   "reproducción" for the verb forms would remove the collision. At minimum, never use the verb
   "repetir" for replaying.

2. **Overloaded words.** Three words carry several unrelated meanings in the editor:
   - *trama / tramado*: Screen blend mode ("Trama", the Photoshop name), dither ("tramado"), and crosshatch
     ("trama cruzada"). Changing crosshatch to "rayado cruzado" (matching "Rayado" in `ditherHintHatch`)
     leaves only the two established uses.
   - *desplazar*: Shift frames/layers (glossary), pan the canvas (`kbPanCanvas`), and scroll
     (`viewHintCrop`, `viewHintPlace`). Reserving it for Shift and using "mover la vista" for pan keeps
     the glossary term unambiguous.
   - *ajustar*: Fit (`importFit`, `viewFit`, `cropFitToCanvas`) and Trim (`cropTrim`,
     `cropNothingToTrim`). Tolerable because the objects differ ("al lienzo" / "al contenido"), but worth
     knowing if either string is shortened.

3. **Residual Peninsular flavor.** The text is neutral almost everywhere; the exceptions are "vídeo"
   (→ "video"), the key name "Intro" (→ "Enter"), and "arriba/abajo del todo" (→ "a la parte
   superior/inferior"). "Pulsa" / "mantén pulsado" are acceptable in neutral Spanish and are used
   consistently, so they were not flagged.

4. **"Zona exterior" vs "fuera del lienzo".** "Zona exterior" is the name of the Overscan view option;
   the off-canvas storage area is "fuera del lienzo" in the glossary. `cropResultBeyond` uses the view
   option's name for the storage area, and `placeParked` drops the "kept" idea. Keep "Zona exterior" for
   the view option only.

5. **Gesture wording.** Hints mix imperatives with a noun phrase ("Toca… · mantén pulsado… · doble
   toque…") while other pages say "toca dos veces". One form everywhere ("toca dos veces") reads better
   and the shorter "para opciones" helps the two-line limit.

6. **"Activar" for "make active".** On layers, "activar" can be read as "enable/show". The glossary term
   is the adjective ("capa activa"); "hacer activa" keeps the meaning in the item menu and the hint.

7. **Length.** Spanish runs 25–40 % longer than English in several "one line / two short lines" slots
   (`layersLockedNote`, `framesIdleHint`, `layersIdleHint`, `viewHintCrop`, `viewHintPlace`). Only the
   clearest cases are in the table; the screen sweeps at 320 px are the real judge for the rest.
