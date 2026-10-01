# Review: Brazilian Portuguese, part 3 of 3 (messages 1101–1645)

Independent native-level review of `pt` against the English source and `docs/i18n/GLOSSARY.md`.
Only real problems are listed; a message that is absent from the table was judged correct.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| viewFit | medium | "tela" is the glossary word for *canvas*, so "Ajustar à tela" reads as "fit to canvas", and it is letter-for-letter the same as `cropFitToCanvas` ("Fit to canvas"), a different action. The screen needs another word here. | Ajustar à tela | Ajustar à janela |
| clubSizeNearest | medium | "Fora do Club" says "outside the Club", not "not a size the Club accepts"; the word "size" is lost and the line is unclear on its own. | Fora do Club. Mais próximo: {width} × {height} | Tamanho não aceito. Mais próximo: {width} × {height} |
| layerMergeDown | low | The set phrase in Brazilian image editors is "Mesclar para baixo"; "Mesclar abaixo" reads as "merge below (somewhere)". | Mesclar abaixo | Mesclar para baixo |
| selectNone | medium | The same action (clear the pixel selection) is "Remover seleção" in `cmdDeselect`; one action needs one name. "Desmarcar" is also what one does to a checkbox, not to a pixel selection. | Desmarcar tudo | Remover seleção |
| autosaveFailed | low | Two sentences, the first ends with a period and the second does not. Keep it one clause like the English. | Não foi possível salvar automaticamente. Verifique o armazenamento do dispositivo | Não foi possível salvar automaticamente: verifique o armazenamento do dispositivo |
| nudgeUp | low | Bare "Cima" / "Baixo" are not used alone as directions in a tooltip (unlike "Esquerda" / "Direita"). | Cima 1 px (segure para repetir) | Para cima 1 px (segure para repetir) |
| nudgeDown | low | Same as `nudgeUp`. | Baixo 1 px (segure para repetir) | Para baixo 1 px (segure para repetir) |
| zoomIn | low | "Ampliar zoom" is not idiomatic; Brazilian apps say "Aumentar zoom" / "Diminuir zoom". | Ampliar zoom | Aumentar zoom |
| zoomOut | low | Pair of `zoomIn`. | Reduzir zoom | Diminuir zoom |
| cropTrim | low | "Aparar ao conteúdo" is a calque of "trim to content"; the preposition does not work with "aparar". | Aparar ao conteúdo | Aparar até o conteúdo |
| cropAspectLocked | medium | "travada na da tela" is awkward (stacked "na da") and hard to parse in a tooltip. | Proporção travada na da tela | Proporção da tela travada |
| cropResultDownscaled | medium | Gender: every sibling line refers to the image in the feminine ("posicionada em 1:1", "Ampliada"); this one switches to the masculine. | Na tela: {width} × {height} px (reduzido para caber em {canvasWidth}×{canvasHeight}) | Na tela: {width} × {height} px (reduzida para caber em {canvasWidth}×{canvasHeight}) |
| placeParked | low | Drops "parked/kept": next to "Descartado: …" the user cannot tell that this part is preserved. Sibling messages say "fica guardada fora dela". | Fora da tela: {edges}. | Guardado fora da tela: {edges}. |
| framesShiftHint | low | "move para o início" says the frames go to the very beginning; the English says they move earlier (toward the start) by that many positions. | Posições a deslocar. Um número negativo move para o início. | Posições a deslocar. Um número negativo move para trás. |
| framesScaleTitle | medium | "Escalar" in everyday Brazilian Portuguese means to climb or to pick a team; as "scale" it is developer jargon. The operation multiplies durations by a factor. | Escalar durações | Multiplicar durações |
| framesScaleAction | medium | Same as `framesScaleTitle` (the button must use the title's verb). | Escalar | Multiplicar |
| framesScaleRange | low | Portuguese writes the decimal with a comma. Use "0,1" if the field accepts a comma; if it only parses a period, keep it and ignore this entry. | De 0.1 a 10 | De 0,1 a 10 |
| framesInsertBefore | low | "Inserir um em branco" with no noun is hard to read; naming the frame costs one word. Same for `framesInsertAfter`. | Inserir um em branco antes de cada um | Inserir quadro em branco antes de cada um |
| framesInsertAfter | low | See `framesInsertBefore`. | Inserir um em branco depois de cada um | Inserir quadro em branco depois de cada um |
| layersInsertAbove | low | As `framesInsertBefore`: name the layer. Same for `layersInsertBelow`. | Inserir uma em branco acima de cada uma | Inserir camada em branco acima de cada uma |
| layersInsertBelow | low | See `layersInsertAbove`. | Inserir uma em branco abaixo de cada uma | Inserir camada em branco abaixo de cada uma |
| layersErrBeyond | low | "além da do topo" (stacked "da do") reads badly. | A camada {number} está além da do topo ({count}) | A camada {number} está além da camada do topo ({count}) |
| blendScreen | low | "Tela" is also the app's word for canvas (the "Tela" submenu, "Redimensionar tela"). In the blend list the meaning is recoverable and other paint apps use "Tela" for Screen, so this is only a note; Photoshop's Brazilian name is "Divisão", which would confuse more people than it helps. No change proposed unless the canvas term changes. | Tela | (keep) |
| ditherHintRowsHalf | low | Missing comma: as written, "outra não em 50 %" reads as "the other one not at 50 %". | Uma linha sim, outra não em 50 % | Uma linha sim, outra não, em 50 % |
| ditherHintColsHalf | low | Same as `ditherHintRowsHalf`. | Uma coluna sim, outra não em 50 % | Uma coluna sim, outra não, em 50 % |
| kbHeldKeys | low | "Teclas seguradas" is not a phrase a Brazilian would write; the participle sounds off as a heading. | Teclas seguradas | Ao segurar a tecla |
| replayOlderTip | low | Agreement: the tip opens from the chip "Gravação antiga" (feminine) and then says "Gravado". | Gravado antes de uma atualização do editor. A reprodução pode diferir da sessão original. | Gravada antes de uma atualização do editor. A reprodução pode diferir da sessão original. |

Totals: 0 high, 7 medium, 20 low (27 entries out of 545 messages; `blendScreen` is a note with no change proposed).

ICU and placeholders: every message in this part keeps all its placeholders untouched, every plural has
grammatical `one` and `other` branches, and the ellipsis is `…` throughout. Quotation marks are the
straight `"…"` of the source, used consistently. No European Portuguese vocabulary or spelling was found;
the register is a consistent "você" with imperative buttons and hints.

## Systemic notes

1. **"Tela" carries three meanings.** The glossary makes it the canvas, but in this part it is also the
   device screen (`viewFit` "Ajustar à tela" = fit to *screen*, identical to `cropFitToCanvas` "Ajustar à
   tela" = fit to *canvas*) and the Screen blend mode (`blendScreen`). Keep "tela" for the canvas only:
   use "janela" (or rephrase, as `viewZoomFit` "Exibição: ajustada" already does) wherever the English
   says "screen". This is the one pattern that can actually mislead.
2. **One action, one name, for clearing the selection.** `selectNone` says "Desmarcar tudo" and
   `cmdDeselect` says "Remover seleção". Pick "Remover seleção" everywhere (and check parts 1 and 2 for
   other renderings of Deselect / Select none).
3. **"Escalar" for "scale".** As a verb for multiplying values it is jargon in Brazil ("escalar" is to
   climb, or to select a team). `framesScaleTitle` / `framesScaleAction` should be "Multiplicar"; the
   import flow already avoids it well ("Ampliar", "Ajustar", "Escala" as a noun), so this is confined to
   the durations dialog.
4. **Gender of the implied noun in status lines.** The import and crop notes speak of the image in the
   feminine ("Posicionada", "Ampliada"), with one masculine slip (`cropResultDownscaled` "reduzido");
   likewise `replayOlderTip` "Gravado" after the chip "Gravação antiga". When a message has no subject,
   agree with the noun the neighboring messages use.
5. **Gesture wording varies.** Double-tap is "toque duas vezes" on the crop and place pages and "toque
   duplo" on the Frames and Layers pages. Both are fine; choosing one (the shorter "toque duplo") would
   be tidier. "Segure" for hold and "de novo" for again are consistent.
6. **Flip is "Espelhar", Mirror (symmetry) is "Espelho".** The two are distinct from Invert, as the
   glossary requires, and "Espelhar horizontalmente" is what GIMP-style editors say for Flip, so no
   change is requested; but the verb of one feature is the noun of the other. If users confuse them,
   "Virar horizontalmente / Virar H" (Photoshop's Brazilian wording) separates them cleanly.
7. **Cross-part check.** `replaceColorToleranceHelp` calls the Bucket tool "Preencher". That is right
   only if the tool's own name (`toolBucket`, in another part) is "Preencher"; this part could not
   verify it.
8. **Directions and zoom in tooltips** (`nudgeUp`, `nudgeDown`, `zoomIn`, `zoomOut`): prefer the forms
   Brazilian software uses, "Para cima / Para baixo" and "Aumentar zoom / Diminuir zoom".
