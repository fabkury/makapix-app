# ja review: Patterns Invert pack (patterns-ja.jsonl, 4 messages)

| key | severity | problem | current | proposed |
|---|---|---|---|---|

## Systemic notes

- No findings. All four strings read as natural UI Japanese and match the shipped strings on the
  same page.
- `patFamilyBayer` and `patBayer` use ベイヤー, as the glossary and the shipped `bayerSize` and
  `ditherFamilyBayer` do. The ` · ` separator in `patBayer` matches the shipped `patChecker`
  (市松 · {size}×{size} セル), and `{fraction}` is present and untouched.
- `patternsInvert` (オン／オフ反転) is the glossary's decision and the same wording as the shipped
  `patInverse` suffix, so a tile name and the switch that produces it agree. It stays clear of
  反転 (Flip) and 色反転 (the color Invert). At seven characters it fits a switch title. On a
  switch row the words オン／オフ could for a moment be read as the switch's own states, but the
  page labels its two preview colors オン and オフ and the line below explains the effect, so it
  does not mislead.
- `patternsInvertSub` (パターンが飛ばすセルを塗ります) says what the English says, uses セル and
  パターン as `patternsHint` does, and ends in ます with no period, like the neighboring
  `patternsOffSub`. 飛ばす is the everyday word for "skip" and reads well here.

Checked 4 messages.
