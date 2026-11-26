# es review: Patterns Invert pack (patterns-es.jsonl, 4 messages)

| key | severity | problem | current | proposed |
|---|---|---|---|---|

## Systemic notes

- No findings. The four strings are correct, natural, and consistent with the shipped strings on
  the same page.
- `patFamilyBayer` / `patBayer`: "Bayer" stays in Latin script as the glossary requires, and
  matches the shipped `bayerSize`; `{fraction}` is present and untouched, with the same " · "
  separator the app uses in `patChecker`.
- `patternsInvert`: "Invertir" is the glossary's word, is as short as the English, and agrees with
  the shipped "(inverso)" suffix. The same word is the short label of the color Invert tool
  (`toolInvertShort`), but the two never share a screen, and the line under the switch makes the
  meaning clear.
- `patternsInvertSub`: "Pinta las celdas que el patrón omite" uses "celdas" and "patrón" as the
  page hint does. "Pinta" reads both as the imperative (tú) and as a description of what the
  switch does, which suits a line placed next to `patternsOffSub` ("La herramienta pinta todos los
  píxeles"). No final period, as in the English.

Checked 4 messages.
