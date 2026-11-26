# fr review: Patterns Invert pack (patterns-fr.jsonl, 4 messages)

| key | severity | problem | current | proposed |
|---|---|---|---|---|

## Systemic notes

- No findings. The four strings are correct, natural, and consistent with the shipped strings on
  the page: "motif" for pattern, "cellules" for cells (as in `patternsHint` and `patChecker`),
  "Bayer" kept in Latin (as in `bayerSize` and `ditherFamilyBayer`), `{fraction}` present and
  untouched, and the " · " separator matching `patChecker`.
- `patternsInvert` "Inverser" is the glossary's decision and is short enough for a switch title.
  It is the same word as the color tool's short label (`toolInvertShort`), but the subtitle
  "Peint les cellules que le motif ignore" makes clear that it acts on cells, not colors, so a
  French reader is not misled.
- `patternsInvertSub` uses the third-person descriptive "Peint…", where the English is an
  imperative. That is the usual French form for a line describing what a setting does and matches
  the neighboring `patternsOffSub` ("L'outil peint tous les pixels"); no change needed.
- Not under review, noted only for the record: the shipped suffix `patInverse` reads
  "(inverse)"; "(inversé)" would be the participle matching the new "Inverser" switch. It is
  understandable as is.

Checked 4 messages.
