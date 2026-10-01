# Second-pass review: Brazilian Portuguese (pt)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| tipCopyPaste | medium | The rewrite names Paste by its chip ("Colar") in the last sentence, but the first two sentences still use lowercase imperatives and lowercase "camada" / "quadro" instead of the chip labels (optCopy "Copiar", optCut "Recortar", optPaste "Colar", optClear "Limpar", optLayer "Camada", optFrame "Quadro"). That breaks the glossary rule that tips name each option as its chip shows it, and it is inconsistent within the message. | Copie, recorte, cole ou limpe a seleção. Origem: camada ou quadro inteiro. Colar cria um rascunho móvel. | Use Copiar, Recortar, Colar ou Limpar na seleção. Origem: Camada ou Quadro inteiro. Colar cria um rascunho móvel. |
| reportResolvedOn | low | Its siblings reportResolved and reportSentBody now use "Obrigado." with a period. This one keeps "Obrigado:", and a colon after "Obrigado" is not natural Portuguese punctuation. | Obrigado: analisamos sua denúncia sobre {subject}. | Obrigado. Analisamos sua denúncia sobre {subject}. |
| followUpdateFailed | low | "o status de seguir" is a stiff calque. The message is shown when following or unfollowing fails, so it can say that directly. | Não foi possível atualizar o status de seguir. | Não foi possível seguir ou deixar de seguir. |
| cropAspectLocked | low | This reads as "the canvas's proportion is locked". The intended meaning is that the crop's aspect ratio is locked to match the canvas. | Proporção da tela travada | Proporção travada igual à da tela |

Checked 77 messages.
