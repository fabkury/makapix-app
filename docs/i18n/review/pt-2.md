# Translation review: Brazilian Portuguese (pt), pack 2 (messages 551–1100)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| modDemoteAction | low | A bare "Remover" on the dialog's red button can read as removing the post itself; the glossary pair is "remover promoção". | Remover | Remover promoção |
| pmdSelectAll | low | "tudo (carregado)" is awkward; the items are posts (feminine plural). | Selecionar tudo (carregado) | Selecionar todas (carregadas) |
| reportResolvedOn | medium | The subject in parentheses reads oddly ("analisamos sua denúncia (um comentário)"); the English says "your report on {subject}". | Obrigado: analisamos sua denúncia ({subject}). | Obrigado: analisamos sua denúncia sobre {subject}. |
| umdRevealEmailBody | low | "registrada no registro" repeats the word. | A consulta fica registrada no registro de auditoria | A consulta fica gravada no registro de auditoria |
| umdRevealBody | low | Same repetition as umdRevealEmailBody. | A consulta fica registrada no registro de auditoria da moderação. | A consulta fica gravada no registro de auditoria da moderação. |
| umdJoined | medium | "entrou em" is the glossary's "sign in" verb (entrar), so it reads as "signed in on {date}", not "joined". | entrou em {date} | membro desde {date} |
| playersOfflineSeen | low | "visto:" drops "last"; "visto por último" is the usual wording. | Offline · visto: {when} | Offline · visto por último: {when} |
| followUpdateFailed | medium | "seguimento" is not used for following someone; it reads as "follow-up". | Não foi possível atualizar o seguimento. | Não foi possível atualizar o status de seguir. |
| tipOutline | low | The option names Corners and Width are lowercased while every other tip capitalizes the option labels it names (Limiar, Diagonal, Lento, Pontos). | Lado, cantos e espessura definem a forma. | Lado, Cantos e Espessura definem a forma. |
| tipCopyPaste | medium | "O colado pode ser movido" is unnatural (a past participle used as a noun); the English says Paste drops a movable draft. | O colado pode ser movido. | Colar cria um rascunho móvel. |
| tipSelectLayer | low | Descriptive third person ("Transforma") while most tips use the imperative, like the English ("Turn…"). | Transforma os pixels opacos da camada em uma seleção. | Transforme os pixels opacos da camada em uma seleção. |
| tipFlip | low | Same mood inconsistency (English "Mirror…"). | Espelha a camada na horizontal ou na vertical. Atua na seleção, se houver. | Espelhe a camada na horizontal ou na vertical. Atua na seleção, se houver. |
| tipRotate | low | Same mood inconsistency; the option Angle is lowercased so it no longer names the on-screen option. | Gira a camada ou o quadro em 90°, 180° ou em um ângulo livre. | Gire a camada ou o quadro em 90°, 180° ou em um Ângulo livre. |
| tipResize | low | Same mood inconsistency; the option Scale is lowercased. | Redimensiona a camada ou o quadro: ½×, 2× ou uma escala livre ao arrastar. | Redimensione a camada ou o quadro: ½×, 2× ou arraste uma Escala livre. |
| tipInvert | low | Same mood inconsistency (English "Invert…"). | Inverte as cores da imagem. | Inverta as cores da imagem. |
| tipPlay | medium | Mixes moods within one tip: descriptive "Reproduz ou pausa" followed by imperative "Vá… pule". | Reproduz ou pausa a animação. Vá ao quadro anterior ou ao próximo, ou pule para um. | Reproduza ou pause a animação. Vá ao quadro anterior ou ao próximo, ou pule para um. |
| optDiagonalTip | low | "(8 conexões)" does not render "8-connected" (each pixel has 8 neighbors); it reads as "8 connections". | Vizinhos na diagonal: a região pode cruzar cantos (8 conexões) | Vizinhos na diagonal: a região pode cruzar cantos (8 vizinhos) |
| mirrorChipTip | medium | "Não" for the Off state is unnatural in a list of modes and does not match the Off option on the mirror sheet (mirrorModeOff = "Desativado"). | Desenho espelhado: toque para alternar Não · H · V · Ambos; segure para o eixo | Desenho espelhado: toque para alternar Desativado · H · V · Ambos; segure para o eixo |
| mirrorSubtitle | low | "vale para os dois lados" is loose; the English says each stroke lands on both sides. | Cada traço, figura e preenchimento vale para os dois lados do eixo | Cada traço, figura e preenchimento é aplicado dos dois lados do eixo |
| patternSwatchTipOn | medium | "quadro" is the glossary word for an animation frame, so "toque no quadro" reads as "tap the frame"; the tile here is the swatch, which the next message calls "amostra". | {label}: {name} · toque no quadro para trocar, na borda verde para desativar | {label}: {name} · toque na amostra para trocar, na borda verde para desativar |

## Systemic notes

- **Help-tip mood is mixed.** Most tool tips (`tip…`) use the imperative like the English
  ("Arraste…", "Toque…", "Ajuste…"), but the transform tips switch to descriptive third person
  ("Transforma", "Espelha", "Gira", "Redimensiona", "Inverte", "Reproduz ou pausa"), and
  `tipPlay` mixes both in one tip. Pick the imperative everywhere, matching the English and the
  majority.
- **Option names inside tips.** The brief says tip words that name on-screen options must match
  the `opt…` labels; most tips capitalize them (Limiar, Diagonal, Lento, Pontos, Suave, Névoa),
  but `tipOutline` (cantos, espessura), `tipRotate` (ângulo) and `tipResize` (escala) lowercase
  them, so they stop reading as the labels. Capitalize every option name a tip cites.
- **"quadro" must stay reserved for the animation frame** (glossary). It leaked in as the
  pattern swatch tile (`patternSwatchTipOn`); check any other place that renders "tile" or
  "box" with "quadro". Similarly, "entrar" is the glossary verb for sign in, so it should not be
  reused for "joined" (`umdJoined`): "membro desde" avoids the clash.
- The em dash of the English is consistently turned into a colon, period, or semicolon, which
  reads naturally in Brazilian Portuguese; "Obrigado:" (reportResolved, reportSentBody) is the
  one place where a period would read better ("Obrigado. Analisamos…"), but it is acceptable.
- Glossary terms (publicação, arte, camada, quadro, tela, rascunho, denunciar, banir / remover
  banimento, reexibir, player, arquivo com camadas, cor primária) are applied consistently across
  this pack; "período de carência" for the 7-day grace period is consistent across all three
  packs and acceptable.
