# pt review: Patterns Invert pack (patterns-pt.jsonl, 4 messages)

| key | severity | problem | current | proposed |
|---|---|---|---|---|

## Systemic notes

- No findings. The four strings read as natural Brazilian Portuguese and match the shipped
  strings on the same page: "padrão" for pattern, "células" for cells (as in `patternsHint`
  and `patChecker`), and "Inverter" next to the existing "(inverso)" suffix.
- `patFamilyBayer` and `patBayer` keep the name Bayer in Latin script, as the glossary says and
  as `bayerSize` already does; `{fraction}` is present and untouched, and the " · " separator
  matches `patChecker`.
- `patternsInvert` ("Inverter") is the glossary's term and is as short as the English. It is the
  same word as the short label of the color Invert tool (`toolInvertShort`), but the two never
  share a screen, and the line under the switch says what it does.
- `patternsInvertSub` ("Pinta as células que o padrão pula") uses the descriptive third person,
  in line with the neighboring `patternsOffSub` ("A ferramenta pinta todos os pixels"); "pula" is
  the natural Brazilian verb for "skips". No period, as in the English.

Checked 4 messages.
