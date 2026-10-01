# Japanese (ja) review: pack 1 (messages 1–550)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| settingsMentionsSummary | low | Uses the pronoun あなた, against the no-pronoun convention; the subject is clear without it (see Systemic notes). | あなたをメンションできる人：{policy, select, …} | メンションできる人：{policy, select, following{フォロー中のユーザー} nobody{なし} other{全員}} |
| commonRemove | low | Same word as commonDelete (削除), though the context says this is not a permanent deletion; a user removing an item from a list may fear the content is destroyed. | 削除 | 外す |
| commentsDeletedByMod | low | Reads as a clipped sentence ("moderator deleted"); the placeholder idiom is により. Change commentsModDeleteBody's quote to match. | [モデレーターが削除] | [モデレーターにより削除] |
| commentsModChip | medium | モデ is not an abbreviation Japanese users know (it reads as the start of モデル); next to a shield icon a short native word is clearer. modHubNote (pack 2) quotes this label as 「モデ」 and must change with it. | モデ | 管理 |
| downloadLayersSubtitle | low | 完全なドキュメント is translationese for "the full document". | レイヤーを含む完全なドキュメント | 全レイヤーを含むドキュメント |
| filterSortCreated | low | The context says this is the date the artwork was posted; 作成日 suggests when it was drawn. | 作成日 | 投稿日 |
| createAccountGithub | low | Space between a Latin word and Japanese, against the convention (see Systemic notes). | GitHub で登録 | GitHubで登録 |
| createAccountHaveAccount | low | Without すでに the question reads "Do you have an account?", not "Already have one?". | アカウントをお持ちですか？ログイン | すでにアカウントをお持ちですか？ログイン |
| createAccountLostTemp | low | 紛失しましたか is stiff for a lost email; Japanese apps ask whether it can't be found. | 仮パスワードを紛失しましたか？再設定 | 仮パスワードが見つかりませんか？再設定 |
| handleBadChars | low | ～を使ってください reads as if all four kinds must be used; the rule is that only these are allowed. | 文字、数字、ハイフン、アンダースコアを使ってください。 | 使用できるのは文字、数字、ハイフン、アンダースコアのみです。 |
| accountCantUnlinkOnly | low | 唯一のログイン方法は解除できません is literal; the natural form gives the reason. | 唯一のログイン方法は解除できません。 | ログイン方法が1つしかないため、連携を解除できません。 |
| welcomeTitle | low | Space between Latin and Japanese (see Systemic notes). | Makapix Club へようこそ | Makapix Clubへようこそ |
| commonContinue | low | A wizard's next-step button is 次へ in Japanese apps; 続ける reads as "keep going (with what you were doing)". | 続ける | 次へ |
| onboardingHandleTitle | low | Plain dictionary form as a heading, unlike the sibling step titles (パスワードを設定). | ユーザー名を決める | ユーザー名を設定 |
| onboardingHandleBody | medium | あなたの@名前 is literal and odd (the pronoun plus a half-translated "@name"). | Makapix Club 全体で使われるあなたの@名前です。あとで設定から変更できます。 | Makapix Club全体で使われる@ユーザー名です。あとで設定から変更できます。 |
| onboardingProfileTitle | medium | ひと工夫を加える means "add some ingenuity"; the English means "add a personal touch" to the profile. | ひと工夫を加える（任意） | プロフィールを充実させる（任意） |
| onboardingProfileBody | low | あなただとわかりやすくなります is a literal "help people recognize you" with a pronoun. | 写真と短い自己紹介があると、あなただとわかりやすくなります。スキップしてあとで設定することもできます。 | 写真と短い自己紹介があると、ほかのユーザーに覚えてもらいやすくなります。スキップしてあとで設定することもできます。 |
| accountUploadsLeft | low | Spaces between Japanese and the numbers. | 残り {remaining} / {limit} | 残り{remaining}/{limit} |
| accountCanPostPublicly | low | As a row label with the value はい / 承認待ち, 公開投稿 ("public post") does not say it is a permission. | 公開投稿 | 公開投稿の権限 |
| notifSomeone | medium | Substituted into the notif* templates, which add さん after {who}: the result is 誰か さんが…, and 誰かさん is jocular. | 誰か | 名無し (renders as the familiar 名無しさん); or drop さん from the templates when {who} is this message |
| notifReaction | low | The artwork title is unquoted here, unlike notifMentionDescriptionOf and notifRemixTitled, which use 「」; an unquoted title blends into the sentence. Same in notifModTags. | {who} さんが {title} に {emoji} でリアクションしました | {who} さんが「{title}」に{emoji}でリアクションしました |
| notifModTags | low | Unquoted title (see notifReaction). | モデレーターが {title} のハッシュタグを変更しました | モデレーターが「{title}」のハッシュタグを変更しました |
| notifPromoted | low | Unneeded pronoun; the notification is already addressed to the user. Same for notifReputation and notifModerator. | あなたの投稿がおすすめに選ばれました | 投稿がおすすめに選ばれました |
| notifReputation | low | Unneeded pronoun. | あなたの評価が変わりました | 評価が変わりました |
| notifModerator | low | Unneeded pronoun. | あなたはモデレーターになりました | モデレーターになりました |
| contributeTagline | low | Unneeded pronoun and a space before Club. | あなたのドット絵を Club で共有しましょう。 | ドット絵をClubで共有しましょう。 |
| aboutVersion | low | Half-width parentheses and spaces inside Japanese text. | バージョン {version} ({build}) | バージョン{version}（{build}） |
| blockConfirmBody | medium | Four あなた in one sentence: literal and heavy. Japanese drops them; the context makes the person clear. | このユーザーはあなたの投稿へのコメントやリアクション、あなたのフォローができなくなり、あなたにはこのユーザーのコンテンツが表示されなくなります。ブロックは「設定 → ブロックしたユーザー」でいつでも解除できます。 | このユーザーは投稿へのコメントやリアクション、フォローができなくなり、このユーザーのコンテンツも表示されなくなります。ブロックは「設定 → ブロックしたユーザー」でいつでも解除できます。 |
| profileBlockedBanner | low | Same literal pronoun pattern as blockConfirmBody. | @{handle} をブロックしています。このユーザーはあなたとやり取りできず、あなたにはこのユーザーのコンテンツが表示されません。 | @{handle} をブロックしています。このユーザーとはやり取りできず、コンテンツも表示されません。 |
| profileTabReacted | medium | As a tab next to the リアクション statistic, リアクション reads as "reactions received"; the tab lists artworks this user reacted to. | リアクション | リアクション済み |
| profileGalleryWaiting | low | Literal personification ("the gallery is waiting for your works"); Japanese empty states state the fact and invite. | ギャラリーがあなたの作品を待っています。 | ギャラリーはまだ空です。 |
| remixesEmpty | low | The page title (remixesOfMyWorks) says 自分の作品; this says あなたの作品. | あなたの作品のリミックスはまだありません。… | 自分の作品のリミックスはまだありません。… (second line unchanged) |
| statUnique | medium | ユニーク alone reads as "quirky / one of a kind" to a general Japanese user; the stat is distinct viewers. Same in statUnique7d. | ユニーク | 閲覧者数 |
| statUnique7d | medium | See statUnique. | ユニーク（7日） | 閲覧者数（7日） |
| statsColComments | low | コメ is chat slang; コメント (four characters) fits a 56 px column at table type sizes, as 閲覧 and 反応 beside it show. | コメ | コメント |
| statsFirstView | low | 最初の閲覧 / 最後の閲覧 are literal; date-row labels in Japanese UIs are 初回 / 最終. | 最初の閲覧 | 初回閲覧 |
| statsLastView | low | See statsFirstView. | 最後の閲覧 | 最終閲覧 |
| statsComputed | low | 集計 alone ("tally") does not say the value is a timestamp. | 集計 | 集計日時 |
| artworkColorsPerFrame | low | The context asks to keep the ≤ sign; 以下 replaces it. Natural, but it changes the technical line's compact form. | 1フレームあたり{count}色以下 | ≤{count}色／フレーム |
| artworkEditLayers | low | Two で in a row (付きで … Makapix で) is clumsy. | レイヤー付きで Makapix で開く | Makapixでレイヤーごと開く |

## Systemic notes

1. **Spaces between Japanese and Latin text.** The convention is no space, but the pack puts a
   half-width space around Latin names and many placeholders: `GitHub で登録`, `Makapix Club へようこそ`,
   `Makapix Club に接続中…`, `Makapix で編集`, `{fileName} を保存しました`, `{player} に送信しました`,
   `最大 {value}`, `評価 {points}`, `残り {remaining} / {limit}`. Numeric placeholders are mostly
   tight (`{max}件`, `{count}フレーム`), so the pack follows two rules at once. Remove the space
   everywhere for Latin words and numbers. The one defensible exception is a space after `@{handle}`
   / `#{tag}` (it keeps the handle visibly separate from the particle); if kept, make it a written
   rule in the glossary rather than an accident.
2. **The pronoun あなた.** It appears in 29 messages in this pack (and more in packs 2 and 3:
   the mention settings, modHideBody, umdHideBody). In notifications ("{who} さんがあなたをフォローしました")
   it matches what major Japanese apps write, and needs no change. Elsewhere it is translationese and
   breaks the no-pronoun rule: drop it where the sentence stays clear (blockConfirmBody, notifPromoted,
   notifReputation, notifModerator, contributeTagline), or use 自分 where a contrast is needed (the
   remixes page already says 自分の作品, while remixesEmpty says あなたの作品).
3. **さん after {who}.** The notification templates append さん to `{who}`; that is right for
   handles, but `notifSomeone` (誰か) is substituted into the same slot and yields 誰か さん. Either give
   notifSomeone a word that takes さん naturally (名無し) or have the code choose a さん-less template
   for the unknown sender.
4. **Titles in sentences.** Some notifications quote `{title}` with 「」 and some do not
   (notifReaction, notifModTags). Always quote: user titles can be any text and otherwise run into
   the particles.
5. **Plural messages.** This pack collapses every plural to a plain message (`{n}バイト`,
   `{count}フレーム`); pack 3 keeps the `{count, plural, other{…}}` wrapper. Both are valid ICU and
   render the same, but one form should be chosen (the brief's form is `other` only).
6. **Glossary: Contribute = 作品を描く.** The Contribute page also offers "Upload a file", which is
   not drawing. The term is acceptable on the brush tooltip, but as the page name it slightly misleads.
   A neutral 作品を投稿 / 投稿する would cover both options; worth a glossary decision rather than a
   per-message change.
