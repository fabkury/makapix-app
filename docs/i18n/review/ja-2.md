# Japanese (ja) review, pack 2 (messages 551–1100)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| modChipHidden | medium | Reads as a clipped clause ("moderator hides") rather than a state on a chip. | モデレーターが非表示 | モデレーターにより非表示 |
| modHideBody | medium | Pronoun あなた (against the no-pronoun rule); the contrast reads more naturally naming the role. | フィードと検索から全員に対して非表示になります。モデレーターによる非表示は作者には解除できませんが、あなたは解除できます。 | フィードと検索から全員に対して非表示になります。モデレーターによる非表示は作者には解除できませんが、モデレーターは解除できます。 |
| publishHiddenSubtitle | medium | Pronoun あなた; 自分 is the usual UI word for the viewer. | 再表示するまで、あなただけに表示されます。 | 再表示するまで、自分にだけ表示されます。 |
| publishReplaceNote | low | 新規投稿として投稿する is redundant (投稿 twice). | 上の情報は新規投稿として投稿する場合にのみ適用されます。 | 上記の情報は新規投稿する場合にのみ適用されます。 |
| publishAsNew | low | Same redundancy on the button. | 新規投稿として投稿 | 新規投稿する |
| publishAllowRemixesBody | medium | Pronoun あなた, and あなたがクレジットされます is translationese. | 公開される系譜にはあなたがクレジットされます。 | 公開される系譜に作者として名前が表示されます。 |
| publishRemixNote | low | このリンク points at a link object that is not on screen; what is public and permanent is the remix relationship. Same in publishRemixNoteCount. | このリンクは公開され、取り消せません。 | 元の作品とのつながりは公開され、あとから解除できません。 |
| publishRemixNoteCount | low | Same as publishRemixNote. | このリンクは公開され、取り消せません。 | 元の作品とのつながりは公開され、あとから解除できません。 |
| publishParentGoneBody | low | 宣言している is a literal rendering of "declares"; stiff. | このリミックスがオリジナルとして宣言している投稿はもう存在しません。 | このリミックスの元として指定されている投稿は、すでに存在しません。 |
| editDetailsAllowRemixesBody | medium | Same as publishAllowRemixesBody: pronoun and translationese. | 公開される系譜にはあなたがクレジットされます。 | 公開される系譜に作者として名前が表示されます。 |
| rulesGateReportNote | medium | 誰でもブロックできます can be read as "anyone can block" rather than "you can block anyone". | アプリ内から、どのコンテンツやユーザーでも通報でき、誰でもブロックできます。 | アプリ内から、あらゆるコンテンツやユーザーを通報したり、どのユーザーでもブロックしたりできます。 |
| mentionEveryoneBody | medium | Two pronouns (あなたの, あなたを); both drop naturally on the "Who can mention me" page. | あなたの作品を見られるメンバーなら誰でも、あなたをメンションできます。 | 自分の作品を見られるメンバーなら誰でもメンションできます。 |
| mentionFollowingBody | medium | Pronouns あなた twice in the first sentence. | あなたがフォローしているメンバーだけが、あなたをメンションできます。 | 自分がフォローしているメンバーだけがメンションできます。 |
| mentionNobodyBody | medium | Pronoun あなた; redundant on this page. | 誰もあなたをメンションできません。 | 誰もメンションできません。 |
| mentionsIntro | medium | Pronoun あなた. | コメントや作品の説明であなたがメンションされると、 | コメントや作品の説明で自分がメンションされると、 |
| mentionsBlockNote | medium | Pronoun あなた. | ブロックしたメンバーは、この設定にかかわらず、あなたをメンションできません。 | ブロックしたメンバーは、この設定にかかわらずメンションできません。 |
| umdHideBody | medium | Pronoun あなた; name the role as in modHideBody. | ユーザーは元に戻せませんが、あなたは戻せます。 | ユーザーは元に戻せませんが、モデレーターは戻せます。 |
| tipOutline | medium | 側 alone is neither natural Japanese nor an on-screen label; the options it names are 外側／内側 (Side) and 丸／四角 (Corners). | 側、角、太さで形を調整します。 | 外側／内側、角の形、太さで調整します。 |
| tipRuler | low | 共有点 is a math term for a common point of two figures; the point where the two measured lines meet is the vertex. | 角度モードでは、共有点での角度が表示されます。 | 角度モードでは、2本の線が交わる頂点の角度が表示されます。 |
| optWrap | medium | ループ suggests animation looping in an animation editor; the option makes pixels wrap around to the opposite edge. Photoshop's Offset filter calls this 折り返す. | ループ | 折り返し |
| optSlowTip | low | Chained 〜して、〜ようにして、〜できます reads clumsily. | ドラッグを減速し、下書きが指より小さく動くようにして、正確に配置できます | ドラッグを減速して下書きの動きを指より小さくし、正確に配置します |
| optContrastLetter | low | 対 (from 対比) is not recognizable as Contrast next to 明; a katakana initial is more legible. | 対 | コ |
| mirrorChipH | low | A space between two Japanese words is not Japanese typography; compose as one label. | ミラー 左右 | 左右ミラー |
| mirrorChipV | low | Same as mirrorChipH. | ミラー 上下 | 上下ミラー |
| mirrorChipBoth | low | Same as mirrorChipH. | ミラー 上下左右 | 上下左右ミラー |
| mirrorChipTip | low | 長押しで軸 is cut off without a verb. | 長押しで軸 | 長押しで軸を移動 |

## Systemic notes

1. **Pronoun あなた.** The style rule is no pronouns, yet あなた appears in ten messages of this
   pack (rows above) and in about 25 more in pack 1 (notification lines such as notifFollow,
   blockConfirmBody, profilePrivateNote, artworkHiddenToast). In Japanese UI the viewer is
   implied or called 自分 (settings, "Who can mention me" = 自分をメンションできる人, already used
   here). In notifications the possessive simply drops: 「{who}さんがフォローしました」,
   「{who}さんが作品のリミックスを投稿しました」. Where a contrast needs a subject (moderator vs
   artist), name the role (モデレーター). Recommend a sweep of all three packs.
2. **Spacing between Japanese and Latin letters, digits, and placeholders is inconsistent and
   mostly against the glossary rule** (no space). Across the three packs I count about 275
   spaced junctions against about 190 unspaced ones; within this pack, Latin words and most
   placeholders are spaced (Club に投稿, エクスポート ZIP を保存, Apple でのログイン,
   @{handle} さん, {date} に参加, 評価 {points}, フレーム {current} / {total}), while counts are
   not ({count}日, 最大{max}件, 6文字のコード, {seconds}秒ループ). Keys in this pack with a
   space at a Japanese–Latin/digit junction: layersNotMkpx, layersTooLarge, publishTitle,
   publishSignIn, publishRemixDescription, publishScaleTo, publishNdNoRemixes,
   publishRemixNote, publishScaled, publishLayersTooLarge, publishReady, publishTooLarge,
   publishSizeNotAllowed, publishedBody, rulesGateBody, pmdRequestBody, pmdSaveZipTitle,
   pmdSavedZip, commonNoAccountId, reportRateLimited, reportTargetComment, reportQuestions,
   reportBlockUser, umdTitle, umdTrustGranted, umdBannedUntil, umdReputationLine, umdJoined,
   umdHideTitle, umdUnbanTitle, umdUnbanned, umdBanPermBody, umdBannedPermToast,
   umdBannedForToast, umdRevealTitle, umdRepApplied, banTitle, appleNoToken, appleCanceled,
   appleFailed, githubCanceled, githubFailedRetry, githubFailed, signInStateMismatch,
   exportRendering, gifFlattenedNotice, clipboardTitle, optFrameOf, gradColorN, mirrorAxisX,
   mirrorAxisY. Either apply the glossary rule mechanically in all packs (keeping the space
   between a number and a Latin unit, {size} MiB, and around an email address, where it aids
   reading and tapping), or, if the Apple-style spaced convention is preferred, change the
   glossary; today the app mixes both.
3. **Plural messages are rendered two ways.** Some keep the ICU form with only `other`
   (lineageOriginals, pmdViews, pmdReactions), others drop the plural wrapper and interpolate
   {count} directly (publishRemixNoteCount, pmdDeleteBody, pmdArtworks, pmdExpiresDays,
   pmdExpiresHours, daysCount, umdBannedForToast, exportOutputFrames). Both work, but the
   brief's convention is `{count, plural, other{…}}`; pick one form for all packs so a future
   language check or tooling pass does not trip on the difference.
4. **Remix wording uses リンク for the lineage relationship** (publishRemixNote,
   publishRemixNoteCount, publishStripClaimBody, editDetailsAllowRemixesBody). It is
   understandable, but in the publish notes the demonstrative このリンク reads as a URL. つながり
   (or 系譜, the glossary's lineage term) would be clearer; at minimum avoid この before it.
5. Help tips (`tip*`) otherwise match the option labels well (しきい値, 斜め, スロー, 強さ,
   ドット／ソフト／ミスト, 四角／楕円／投げ縄, 自由な倍率); only tipOutline names options that do
   not exist on screen.
