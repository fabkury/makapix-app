# de review: Patterns Invert pack (patterns-de.jsonl, 4 messages)

| key | severity | problem | current | proposed |
|---|---|---|---|---|

## Systemic notes

- No findings. All four strings are correct, natural German and fit their slots.
- `patternsInvert` "Invertieren" matches the glossary and the shipped tile suffix "(invertiert)".
  It also stays distinct from the color Invert tool, which the app renders with "umkehren"
  ("Farben umkehren", "Umkehren"), so the switch does not promise a color change.
- `patternsInvertSub` "Malt die Zellen, die das Muster auslässt" uses the same words as the
  shipped strings on the page ("Zellen", "Muster", "malen" as in "Das Werkzeug malt jeden
  Pixel"); the comma before the relative clause is correct, and there is no final period, as in
  the neighboring subtitle.
- `patFamilyBayer` and `patBayer` keep the name in Latin script as the glossary requires, match
  the shipped "Bayer {n}×{n}", and `{fraction}` is present and untouched.

Checked 4 messages.
