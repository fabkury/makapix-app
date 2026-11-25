# Russian (ru) review: Pulse pack (`pulse-ru.jsonl`, 15 messages)

Checked against `docs/i18n/GLOSSARY.md` and the shipped `app/lib/l10n/app_ru.arb`. Messages not
listed have no problem.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| pulseFilterAll | medium | The chip stands before «Работы · Реакции · Комментарии · Рекомендуемое · Плееры · Значки · Репутация» (mixed gender and number), and means "every kind of activity". «Все» is the plural "all" and, on a page about what members do, reads first as "everyone" (it is the word `mentionEveryone` uses). The neuter «Всё» ("everything") is the form for a heterogeneous list, and is what `optAll` already uses. | Все | Всё |
| pulseComingSoon | medium | The page name stands bare inside a sentence, so the opening reads literally ("a pulse will appear soon"). Russian puts a section name in «» in running text, as the shipped messages do for «Рекомендуемое» and «Доверие». | Пульс скоро появится: всё, что делает сообщество, в одном месте. | «Пульс» скоро появится: всё, что делает сообщество, в одном месте. |
| pulseReputation | low | «повысил(а) репутацию» without «свою» can be read as raising someone's reputation, and it is the one card where the «(а)» form is avoidable: the score went up by itself, the member did nothing in this sentence. A subject-less wording is cleaner and matches the pattern of `pulsePromoted` (handle after the noun, undeclined). | `<b>{who}</b> повысил(а) репутацию` | `Репутация <b>{who}</b> выросла` |
| pulseLikes, pulsePosts, pulseRemixes, pulseComments, pulseBadges, pulsePromoted | low | Polish, optional. The `one` branch rightly keeps `{count}` (it also serves 21, 31, 101), but for exactly one item the card says «опубликовал(а) 1 новую работу», «получил(а) 1 значок», where the English says "a new artwork", "a badge". An explicit `=1` branch without the number reads naturally; the four category branches stay as they are. No shipped Russian message uses `=1` yet, so adopt it for all six or none. | `one{<b>{who}</b> опубликовал(а) {count} новую работу}` (and the same shape in the other five) | add before `one`: `=1{<b>{who}</b> отреагировал(а) на работу}` · `=1{<b>{who}</b> опубликовал(а) новую работу}` · `=1{<b>{who}</b> опубликовал(а) ремикс}` · `=1{<b>{who}</b> написал(а) комментарий}` · `=1{<b>{who}</b> получил(а) значок}` · `=1{В «Рекомендуемое» добавили работу <b>{who}</b>}` |

## Systemic notes

- **Plurals are correct.** All six plural messages carry `one`, `few`, `many`, `other`, each
  grammatical for its numbers (1/21 работу, 2 работы, 5 работ; `other` = genitive singular for
  fractions), adjective agreement included («новую работу / новые работы / новых работ»). Every
  placeholder and every `<b>{who}</b>` pair is intact.
- **Gender.** The «(а)» past-tense form follows the shipped notification messages
  (`notifReaction`, `notifRemix`, …), so it is consistent and needs no change. It can only be
  avoided where the sentence can lose its human subject, which is the case for `pulseReputation`
  alone (and already done in `pulsePromoted`).
- **Terms match the glossary and the shipped file:** работа, ремикс, комментарий, значок, плеер,
  репутация, «Рекомендуемое» (in «», accusative after «в», as in `notifPromoted`),
  «Всего» as in `playersTotal`.
- **Section names in running text take «».** Applies to «Пульс» wherever a later message names
  the page inside a sentence; the bare title, tooltip, and chip stay unquoted.
- **"All" chips:** «Всё» for a mixed list of kinds, «Все» only when it agrees with one plural
  noun or means people.
