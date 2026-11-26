# zh review: Patterns Invert pack (patterns-zh.jsonl, 4 messages)

| key | severity | problem | current | proposed |
| --- | --- | --- | --- | --- |
| patternsInvertSub | low | Garden path: 绘制图案 is a very common collocation ("draw a pattern"), so the reader first parses "draw the pattern…" and has to re-read to get "paint [the cells the pattern skips]". Adding 改为 marks 绘制 as the verb of the whole line and also conveys that the switch changes what gets painted. Meaning is otherwise correct; 格子 and 绘制 match the shipped `patternsHint`. | 绘制图案跳过的格子 | 改为绘制图案跳过的格子 |

## Systemic notes

- `patFamilyBayer` and `patBayer` (拜耳, 拜耳 · {fraction}) match the glossary transliteration and the shipped `bayerSize` and `ditherFamilyBayer`; the placeholder is intact and the spacing around the middle dot matches the English source.
- `patternsInvert` (反相) follows the glossary rule that Invert is 反相 everywhere and matches the shipped `patInverse` suffix （反相）. To a native speaker 反相 on its own suggests color inversion (as in `toolInvert`), which this switch is not; the subtitle is what disambiguates it, so the subtitle should always be shown with the title. No change proposed, since the glossary rules out 反转 and the term is short.
- "Cell" is 格子 and "pattern" is 图案 throughout, consistent with the shipped strings on the same page.

Checked 4 messages.
