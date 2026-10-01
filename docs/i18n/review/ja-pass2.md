# Japanese (ja) translation review, second pass

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| createAccountLostTemp | medium | Typo: two particles in a row (をが). | 仮パスワードをが見つかりませんか？再設定 | 仮パスワードが見つかりませんか？再設定 |
| notifSomeone | medium | 名無し is anonymous-forum slang (名無しさん), and the notification templates add さん after {who}, which produces exactly that slang. It reads as a joke, not as an app fallback. | 名無し | 不明なユーザー (better still, drop the さん suffix in the templates when this fallback is used) |
| blockConfirmBody | medium | Once あなた was dropped, the sentence no longer says whose posts the blocked user cannot comment on or react to, or whom they cannot follow. 投稿へのコメント…フォローができなくなり can read as the user's own posts and following in general. | このユーザーは投稿へのコメントやリアクション、フォローができなくなり、このユーザーのコンテンツも表示されなくなります。ブロックは「設定 → ブロックしたユーザー」でいつでも解除できます。 | ブロックすると、このユーザーはこちらの投稿へのコメントやリアクション、こちらのフォローができなくなり、このユーザーのコンテンツも表示されなくなります。ブロックは「設定 → ブロックしたユーザー」でいつでも解除できます。 |
| mentionNobodyBody | low | Without an object, 誰もメンションできません first reads as "you can't mention anyone", the opposite direction. A passive form is clear without a pronoun. | 誰もメンションできません。ユーザー名はどこでもただのテキストになり、通知も届きません。 | 誰からもメンションされません。ユーザー名はどこでもただのテキストになり、通知も届きません。 |
| mentionsBlockNote | low | Same ambiguity: メンションできません has no object. The passive is clearer. | ブロックしたメンバーは、この設定にかかわらずメンションできません。 | ブロックしたメンバーからは、この設定にかかわらずメンションされません。 |
| mirrorChipTip | low | Long-press opens the mirror sheet, which holds the axis actions. It does not start moving the axis, so 軸を移動 promises the wrong thing. The list separator is a Latin middle dot with spaces; Japanese uses ・, as cmdMirrorCycle does. | ミラー描画：タップでオフ · 左右 · 上下 · 両方を切り替え、長押しで軸を移動 | ミラー描画：タップでオフ・左右・上下・両方を切り替え、長押しで軸の設定 |
| cmdMirrorCycle | low | At 18 full-width characters this probably will not fit the 290 px line it shares with its key (the old text had 9). Check it on a phone. | ミラー切替（オフ・左右・上下・両方） | ミラー（オフ・左右・上下・両方）, or ミラーのモード切替 if that still does not fit |
| optFlipSelection | low | The sibling chips are フレームを反転 and レイヤーを反転. 鏡像反転 makes this one longer and uneven. Avoiding 選択範囲を反転 (Photoshop's Select Inverse) is right, but 選択部分 alone already does that. | 選択部分を鏡像反転 | 選択部分を反転 |
| acOverBody | low | A space between a numeric placeholder and its counter, which the settled spacing rule says not to add. | パレットに入る色は最大 {max}色のため、… | パレットに入る色は最大{max}色のため、… |
| patInverse | low | Half-width slash inside Japanese text. Use full-width punctuation. | {name}（オン/オフ反転） | {name}（オン／オフ反転） |

Checked 92 messages.
