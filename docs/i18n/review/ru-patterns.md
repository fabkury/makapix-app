# ru review: Patterns Invert pack (patterns-ru.jsonl, 4 messages)

| key | severity | problem | current | proposed |
|---|---|---|---|---|

## Systemic notes

- No findings. The four strings are correct, natural, and consistent with the shipped strings on
  the same page.
- Terms match the page: "узор" (pattern), "ячейки" (cells), and "закрашивает" (paints) are the
  words `patternsHint`, `patternsOffSub`, and `patChecker` already use. "Байер" matches
  `bayerSize` and `ditherFamilyBayer`, and the glossary's transliteration rule.
- `patternsInvert` "Инвертировать" is the glossary's decision and an infinitive, as the Russian
  convention asks for actions. The same verb names the color Invert elsewhere
  (`optInvertColors` "Инвертировать цвета"), but the subtitle directly under the switch says
  what it does to cells, so a native reader is not misled. At 13 letters it is the longest of
  the eight titles, yet fine for a switch row title.
- `patternsInvertSub` uses the third-person descriptive form ("Закрашивает…") where the English
  is an imperative. That is the natural Russian form for a setting's explanation and matches
  `tipInvert` ("Инвертирует цвета изображения.") and `patternsOffSub`. No final period, as in
  the other subtitles.
- `patBayer` keeps `{fraction}` untouched and the " · " separator used by `patChecker`.

Checked 4 messages.
