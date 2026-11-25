# pt review: Pulse pack (pulse-pt.jsonl, 15 messages)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| pulseMore | low | "+" and "mais" say the same thing twice ("+12 mais" reads "mais 12 mais"). The English "+12 more" has the same doubling, but in Portuguese the sign is read aloud as "mais", so the repetition is audible. The context asks for very short. | `+{count} mais` | `+{count}` (or `mais {count}`) |
| pulsePromoted | low | Article on the feed name differs from the shipped moderator toast for the same event (`modPromotedToast`: "Adicionada aos Recomendados."). "em Recomendados" is correct Portuguese; this is only a consistency polish. | `{count, plural, one{Uma arte de <b>{who}</b> entrou em Recomendados} other{{count} artes de <b>{who}</b> entraram em Recomendados}}` | `{count, plural, one{Uma arte de <b>{who}</b> entrou nos Recomendados} other{{count} artes de <b>{who}</b> entraram nos Recomendados}}` |

## Systemic notes

- The pack is clean: 13 of 15 messages need no change. Meaning, register (no direct address is needed in these lines), Brazilian vocabulary, and spelling are all correct.
- ICU: every plural message has `one` and `other`, both grammatical; `{who}`, `{count}`, `{total}` and the `<b></b>` tags are intact and the tags stay around the name. In Portuguese the `one` branch also serves 0 ("reagiu a uma arte" for 0); a card with a count of 0 should never be shown, so no change is proposed.
- Verbs after `{who}` are third-person singular with no gendered participle ("reagiu", "publicou", "recebeu", "ganhou"), so the lines agree with any handle. The passive "was added" was rightly turned into the active "entrou", which avoids gender agreement issues.
- Glossary terms are respected and match the shipped `app_pt.arb`: arte, publicar, remix, comentário, player, insígnia, reputação, Recomendados (`feedRecommended`), registrar (the `players*` messages), "Tudo" (`optAll`).
- "Pulso" as the page name is consistent with the shipped `modHubNote`, which already calls the website's moderation pulse "pulso". It is a natural, one-word rendering; no change.
