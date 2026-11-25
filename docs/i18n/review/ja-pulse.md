# Japanese (ja) review: Pulse pack (15 messages)

Pack: `pulse-ja.jsonl`. Checked against `GLOSSARY.md` and the shipped `app_ja.arb`.
Nine messages need no change and are not listed.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| pulseLikes | medium | Counter for artworks: the shipped messages count 作品 with 点 (`remixRowMany` 「あなたの作品{count}点のリミックス」, `publishRemixNoteCount` 「オリジナル{count}点」); 件 is used for reactions, remixes, and posts. 点 is also the natural counter for artworks. | `<b>{who}</b>が{count}件の作品にリアクションしました` | `{count, plural, other{<b>{who}</b>が{count}点の作品にリアクションしました}}` |
| pulsePromoted | medium | Same counter inconsistency: 作品{count}件 here, 作品{count}点 in `remixRowMany`. | `<b>{who}</b>の作品{count}件がおすすめに選ばれました` | `{count, plural, other{<b>{who}</b>の作品{count}点がおすすめに選ばれました}}` |
| pulsePosts | low | Same counter: 作品 counted with 件. Tolerable here because 件 can be read as counting the posts, but 点 keeps the three artwork cards alike. | `<b>{who}</b>が新しい作品を{count}件投稿しました` | `{count, plural, other{<b>{who}</b>が新しい作品を{count}点投稿しました}}` |
| pulseRemixes, pulseComments, pulseBadges (and the three above) | low | ICU: the English source is a plural message, and every other Japanese plural message in `app_ja.arb` keeps the wrapper with the single `other` branch (`framesSelectedCount`, `paletteColorCount`, `pmdReactions`, …). These six drop it and use a bare `{count}`. The displayed text is the same; this is a convention break, and worth checking that the tooling and tests accept a non-plural translation of a plural source. The wording itself is fine. | `<b>{who}</b>がリミックスを{count}件投稿しました` / `<b>{who}</b>がコメントを{count}件書きました` / `<b>{who}</b>がバッジを{count}個獲得しました` | `{count, plural, other{<b>{who}</b>がリミックスを{count}件投稿しました}}` / `{count, plural, other{<b>{who}</b>がコメントを{count}件書きました}}` / `{count, plural, other{<b>{who}</b>がバッジを{count}個獲得しました}}` |
| pulseMore | low | 他 before a number can be read た or ほか; the app writes this word in hiragana elsewhere (ほかのユーザー). Hiragana is also the usual UI form (ほか3件). | `他{count}件` | `ほか{count}件` |
| pulseComingSoon | low | 始まります suits an event or a broadcast; for a feature that is not available yet, apps say 公開 or 近日公開. The second sentence is good. | `パルスはまもなく始まります。コミュニティの動きをまとめて見られます。` | `パルスはまもなく公開されます。コミュニティの動きをまとめて見られます。` |

## Systemic notes

- **Counter for artworks.** The pack counts 作品 with 件; the shipped file counts it with 点
  (and uses 件 for reactions, remixes, comments). Use 点 for 作品 everywhere, and consider a
  line in the glossary's Japanese spacing/counter decision so the next batch does not drift.
- **Plural wrapper.** Six messages translate a plural source without
  `{count, plural, other{…}}`. All earlier Japanese plural messages keep the wrapper. Pick one
  convention; keeping the wrapper matches the brief ("plural messages have only `other`").
- **{who} with さん.** With {who} filled as 「pixel_bob さん」, 「{who}が」 and 「{who}の」 without
  a space are correct and match `notifFollow` and the other notification lines; the fallback
  誰か also reads correctly (誰かが…). No change needed. The honorific sits inside the bold
  tags, which is acceptable.
- **Spacing and punctuation** follow the glossary: no space between a number and its counter,
  full-width colon in 「合計：{total}」, no exclamation marks.
- **Terminology** matches the glossary: 作品, リアクション, リミックス, コメント, プレーヤー, バッジ,
  評価, おすすめ (as in `notifPromoted`), 投稿する.
- **パルス** as the page name is acceptable as a katakana feature name. It has no established
  "community activity" sense in Japanese (it suggests an electrical pulse), so the page relies
  on its flame icon and content to explain it; no better one-word candidate to propose.
