# Review: srv-codes pack (54 messages, es · pt · fr · de · ru · ja · zh)

Checked against `GLOSSARY.md` and the neighboring strings in `app/lib/l10n/app_<lang>.arb`
(srvAccountBanned, srvFileTooLarge, srvDimensionsInvalid, srvServerProblem, accountUploadsLeft,
accountCantUnlinkOnly, modTagsCap/modTagsTitle, playersMaxReached, layersGone, pmdDownloads,
badgesTitle, umdBannedUntil). Placeholders tested with sample values ("5 Oct 2026", "5 MiB",
"300×200", "PNG, JPEG, GIF, WEBP", "GitHub"/"Apple", remaining = 1). No placeholder or plural is
broken; every ICU plural has the right branches (ru one/few/many/other, ja/zh other only). The
`srvQuotaExceeded` rewording reads as "storage full" in all seven languages (ja: see below).
"Sign in with Apple" uses Apple's own name everywhere (Iniciar sesión con Apple, Iniciar sessão
com a Apple, Se connecter avec Apple, Mit Apple anmelden, Вход с Apple, Apple でサインイン,
通过 Apple 登录), as do Apple Account / settings.

| lang | key | severity | problem | current | proposed |
|---|---|---|---|---|---|
| es | srvEmailTakenWith | medium | The relative clause "que inicia sesión" attaches to the nearest noun, "correo", so it reads as "this email, which signs in with GitHub". | Ya existe una cuenta con este correo, que inicia sesión con {method}. | Ya existe una cuenta con este correo y usa {method} para iniciar sesión. |
| es | accountUploadsLeftHour | medium | No plural: with remaining = 1 it shows "Quedan 1 de 10", which is ungrammatical (the neighbor `accountUploadsLeft` has the same flaw). | Quedan {remaining} de {limit} esta hora | {remaining, plural, one{Queda {remaining} de {limit} esta hora} other{Quedan {remaining} de {limit} esta hora}} |
| es | accountUploadsLeftDay | medium | Same: "Quedan 1 de 10 hoy". | Quedan {remaining} de {limit} hoy | {remaining, plural, one{Queda {remaining} de {limit} hoy} other{Quedan {remaining} de {limit} hoy}} |
| pt | srvEmailTakenWith | medium | "que entra com" attaches to "e-mail" ("this e-mail, which signs in with…"); an account that "entra" is also odd. | Já existe uma conta com este e-mail, que entra com {method}. | Já existe uma conta com este e-mail, e ela usa {method} para entrar. |
| pt | srvStorageUnavailable | low | The neighbor `srvServerProblem` renders the same "Please try again later" as "Tente novamente mais tarde"; this one drops "novamente". | … Tente mais tarde. | O armazenamento do Club está temporariamente indisponível. Tente novamente mais tarde. |
| pt | srvParentCommentGone | low | "responder" takes "a": colloquial "que você está respondendo" reads loose in an error message. | O comentário que você está respondendo não está mais disponível. | O comentário ao qual você está respondendo não está mais disponível. |
| pt | accountUploadsLeftHour | medium | No plural: with remaining = 1 it shows "Restam 1 de 10" (the neighbor `accountUploadsLeft` has the same flaw). | Restam {remaining} de {limit} nesta hora | {remaining, plural, one{Resta {remaining} de {limit} nesta hora} other{Restam {remaining} de {limit} nesta hora}} |
| pt | accountUploadsLeftDay | medium | Same: "Restam 1 de 10 hoje". | Restam {remaining} de {limit} hoje | {remaining, plural, one{Resta {remaining} de {limit} hoje} other{Restam {remaining} de {limit} hoje}} |
| fr | badgeMasterDesc | low | "Maître artiste" is not an established French phrase; it reads as a calque. | Maître artiste reconnu | Artiste reconnu comme maître |
| de | srvEmailTakenWith | low | "ein Konto, das sich … anmeldet": an account does not sign itself in. | Für diese E-Mail-Adresse gibt es bereits ein Konto, das sich mit {method} anmeldet. | Für diese E-Mail-Adresse gibt es bereits ein Konto, das die Anmeldung mit {method} verwendet. |
| de | srvModTagsLimit | medium | Inconsistent term: everywhere else (`modTagsTitle`, `modTagsNone`, `modTagsCap`) these are "Moderator-Hashtags". | Zu viele Moderations-Hashtags. Das Limit liegt bei {max}. | Zu viele Moderator-Hashtags. Das Limit liegt bei {max}. |
| de | bdrErrorNoPosts | medium | "die enthalten sein konnten" is stilted and unclear (contained in what?). | Es gab keine Beiträge, die enthalten sein konnten. | Es gab keine Beiträge zum Herunterladen. |
| de | accountUploadsLeftHour | medium | Word order: the time adverbial trailing after "übrig" is unnatural German. | {remaining} von {limit} übrig in dieser Stunde | In dieser Stunde noch {remaining} von {limit} übrig |
| de | accountUploadsLeftDay | medium | Same: "übrig heute" is unnatural. | {remaining} von {limit} übrig heute | Heute noch {remaining} von {limit} übrig |
| de | badgeTopContributorDesc | low | "gepostet" is colloquial; the glossary verb for publish/post is "veröffentlichen". | Mehr als 100 Werke gepostet | 100 oder mehr Werke veröffentlicht |
| ru | srvPendingVerification | low | "Эта почта" (this mail) for the address; the neighbors say "адрес почты". | Эта почта ожидает подтверждения. Найдите код во входящих. | Этот адрес почты ожидает подтверждения. Найдите код во входящих. |
| ru | srvImageInvalid | low | Says "this file is not an image"; the English allows a damaged image ("isn't a valid image"). | Этот файл не является изображением. | Этот файл не является корректным изображением. |
| ru | srvModTagsLimit | medium | Inconsistent term: the neighbors (`modTagsTitle`, `modTagsNone`, `modTagsCap`) say "хештеги модераторов". | Слишком много модераторских хештегов. Максимум — {max}. | Слишком много хештегов модераторов. Максимум — {max}. |
| ru | srvPlayerUnsupported | low | "Этот … эту" repetition. | Этот плеер не поддерживает эту функцию. | Плеер не поддерживает эту функцию. |
| ru | srvBdrNotReady | medium | "скачивание" is the act of downloading; "the download isn't ready" here means the ZIP archive. "Скачивание не готово" is unnatural. `bdrErrorNoPosts`/`bdrErrorInternal` already say "архив". | Это скачивание ещё не готово. | Архив для скачивания ещё не готов. |
| ru | srvBdrExpired | medium | Same: a process cannot have an expiry; the link to the archive expired. | Срок действия этого скачивания истёк. | Срок действия ссылки на этот архив истёк. |
| ru | srvBdrNotFound | medium | Same. | Это скачивание больше недоступно. | Этот архив больше недоступен. |
| ru | accountUploadsLeftHour | low | "в этот час" is literal; the day sibling uses "на сегодня". | Осталось {remaining} из {limit} в этот час | Осталось {remaining} из {limit} на этот час |
| ru | badgeTopContributorDesc | medium | "Опубликовал" is masculine and is shown on every holder's profile, women included; "более 100" also excludes exactly 100 ("100+"). | Опубликовал более 100 работ | 100 и более опубликованных работ |
| ja | srvEmailTakenWith | low | "{method} でログインします" reads as an announcement ("[we] will sign in with GitHub"), not as a description of the existing account. | このメールアドレスのアカウントはすでにあり、{method} でログインします。 | このメールアドレスは、{method} でログインするアカウントですでに使われています。 |
| ja | srvQuotaExceededUsage | medium | Without "your" (dropped per the no-pronoun rule), "ストレージの空き容量がありません" is the OS's device-storage-full message; a Japanese user will free space on the phone. Name the Club's storage, as `srvStorageUnavailable` does. "（{limit} 中 {used} 使用）" is also stiff. | ストレージの空き容量がありません（{limit} 中 {used} 使用）。 | Club のストレージ容量が上限に達しました（{used} / {limit} 使用中）。 |
| ja | srvStorageUnavailable | low | The neighbor `srvServerProblem` says "しばらくしてからもう一度お試しください" for the same English; this drops もう一度. | …しばらくしてからお試しください。 | Club のストレージが一時的に利用できません。しばらくしてからもう一度お試しください。 |
| ja | srvModTagsLimit | low | Counter differs from `modTagsCap` (最大{max}件), and the settled rule puts no space between a numeric placeholder and its counter. | …上限は {max} 個です。 | モデレーター用ハッシュタグが多すぎます。上限は{max}件です。 |
| ja | srvHashtagTooLong | low | Space between the numeric placeholder and the counter 文字 (settled rule: none). | {max, plural, other{ハッシュタグが長すぎます。上限は {max} 文字です。}} | {max, plural, other{ハッシュタグが長すぎます。上限は{max}文字です。}} |
| ja | srvPlayerNotFound | low | Loses "anymore": reads as "this player has never been registered", while it was removed meanwhile. | このプレーヤーは登録されていません。 | このプレーヤーは登録が解除されています。 |
| ja | srvPlayerInvalidValue | low | Translationese (the player as the subject that "uses" a value). | プレーヤーはその値を使用できません。 | この値はプレーヤーで使用できません。 |
| ja | bdrErrorUserGone | low | Loses "no longer". | アカウントが存在しません。 | アカウントはすでに存在しません。 |
| ja | badgeMasterDesc | low | "認められた" is a literal calque of "recognized". | 認められたマスターアーティスト | 公認のマスターアーティスト |
| ja | srvQuotaExceeded | medium | The reworded string is word-for-word the OS's "device storage full" message (see srvQuotaExceededUsage); the user is told to free phone storage instead of Club storage. | ストレージの空き容量がありません。 | Club のストレージ容量が上限に達しました。 |
| zh | srvLastLoginMethod | low | Double 的 is clumsy; the neighbor `accountCantUnlinkOnly` already says it more simply. | 无法解除你唯一的登录方式的关联。 | 这是你唯一的登录方式，无法解除关联。 |
| zh | srvModTagsLimit | medium | Inconsistent term: the glossary and every neighbor (`modTagsTitle`, `modTagsCap`, `accountRole`) use 管理员, not 版主. | 版主话题标签过多，上限为 {max} 个。 | 管理员话题标签过多，上限为 {max} 个。 |
| zh | srvPlayerNotFound | medium | "已不再注册" is unnatural Chinese; the context is a player removed meanwhile, and the players page says 移除/删除. | 此播放器已不再注册。 | 此播放器已被移除。 |
| zh | srvBdrNotReady | low | "此下载" (this download) as a thing that is "ready" is stiff; name the file. | 此下载尚未准备好。 | 下载文件尚未准备好。 |
| zh | accountUploadsLeftHour | low | "本小时" is unusual; "当前小时" / "这一小时" is the usual wording. | 本小时剩余 {remaining} / {limit} | 这一小时剩余 {remaining} / {limit} |
| zh | badgeModerator | medium | Glossary term is 管理员 (and the user's role on the account page is 管理员); a badge reading 版主 next to a role reading 管理员 looks like two different things. | 版主 | 管理员 |
| zh | badgeModeratorDesc | medium | Same. | 社区版主 | 社区管理员 |
| zh | badgeTopContributorDesc | low | "100 多个" reads as "a bit over 100" and 个 is a loose measure word for artworks. | 发布了 100 多个作品 | 已发布 100 件以上作品 |

## Systemic notes

- **The "uploads left" counter has no plural (es, pt, and the fr neighbor).** `accountUploadsLeftHour`/`Day` copy the
  older `accountUploadsLeft` pattern, which conjugates the verb (or agrees "restants") for the plural only. With one
  upload left, es/pt print "Quedan 1" / "Restam 1". Fix all three keys together with an ICU plural on `{remaining}`
  (or a neutral label form, "Restantes: {remaining} de {limit}"); fr "{remaining} sur {limit} restants" has the same
  milder issue for 0 and 1.
- **"Moderator hashtags" drifted in the new string (de, ru, zh).** `srvModTagsLimit` uses a different word from the
  established mod-tags family (de Moderations- vs Moderator-, ru модераторских vs хештегов модераторов, zh 版主 vs
  管理员). zh also introduced 版主 in the two moderator badge strings. The glossary's 管理员 should hold everywhere,
  badges included.
- **Japanese "storage full" reads as the phone's storage.** With the possessive dropped, ストレージの空き容量がありません
  is the OS's own wording. Both quota keys should name the Club's storage, as `srvStorageUnavailable` already does. The
  other six languages keep "your" and read correctly.
- **Russian "скачивание" as a countable object.** The glossary's скачивание is right for the action and the list title,
  but in the bdr error strings "this download" means the ZIP. Use архив there (as `bdrErrorNoPosts`/`bdrErrorInternal`
  already do).
- **"Posted 100+ artworks" became "more than 100" in es, pt, fr, de, ru, zh.** Strictly, that excludes the 100th post,
  the exact moment the badge is earned. Low stakes, but "100 o más / 100 ou mais / au moins 100 / 100 oder mehr /
  100 и более / 100 件以上" is both exact and natural (ja 100点以上 is already right).
- **Japanese counters after numeric placeholders** still sometimes take a space (`{max} 個`, `{max} 文字`). The settled
  rule (no space before a counter) should be applied when these strings are touched.

**Applied 2026-10-05:** all findings and the systemic notes: the three uploads-left lines take an ICU plural on `{remaining}` (now an `int`; es/pt/fr, the older `accountUploadsLeft` included); "moderator hashtags" and zh 管理员 match their neighbors (badges included); ja names the Club's storage; ru says «архив» for the ZIP; "100+" reads "100 or more" everywhere. Japanese counters touched here lost their space.
