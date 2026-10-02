# Review: srv-errors (18 failed-request headlines, all seven languages)

| lang | key | severity | problem | current | proposed |
|---|---|---|---|---|---|
| es | accountHandleCheckFailed | low | The same username field shows `handleChecking` "Verificando…" while the check runs, then this headline says "comprobar". Use the same verb for the same action. | No se pudo comprobar este nombre de usuario. | No se pudo verificar este nombre de usuario. |
| ru | playersCommandFailed | low | Per the context this covers sending an artwork as well as a command (next, back). "команду" narrows it to commands, so it reads oddly when an artwork failed to send. Dropping the object keeps it general, like es/pt/ja/zh. | Не удалось отправить команду плееру. | Не удалось отправить на плеер. |
| ja | accountUnlinkFailed | low | 解除 goes with 連携, not with ログイン. The button says 連携を解除, and "連携ログインを解除" reads as "cancel the linked login". Unlinking undoes the link, so make 連携 the object. | この連携ログインを解除できませんでした。 | このログインの連携を解除できませんでした。 |
| zh | accountUnlinkFailed | low | Same issue as ja. The button says 解除关联, but here 解除 takes 关联登录 as its object ("remove this linked login"). Make the link the thing removed. | 无法解除此关联登录。 | 无法解除此登录方式的关联。 |

## Systemic notes

- **No cause is promised.** None of the 18 promises a cause, so each works as a first line above the server's English explanation. The generic three keep "the Club" as the subject in every language, matching the existing `srvDimensionsInvalid` (El Club / O Club / Le Club / Der Club / Makapix Club / Club で / Club). Russian keeps the "Makapix Club" convention, with correct masculine agreement (не принял, не нашёл).
- **Consistent with existing strings.** Each language reuses its existing "Could not …" pattern: es "No se pudo …", pt "Não foi possível …", fr "Impossible de …", de "… konnte nicht … werden", ru "Не удалось …", ja "…できませんでした。", zh "无法…". The glossary terms (handle, account, report, player, linked logins, 6-digit code) match the glossary and the existing Account, Players and Report screens. Two strings break the pattern on purpose and are fine: de `authSignInFailed` ("Die Anmeldung ist fehlgeschlagen.") and zh `authVerifyFailed` ("验证码验证失败。").
- **Russian verbs differ from the buttons.** The account buttons say "Сменить пароль" and "Сменить имя пользователя", while the new headlines say "изменить". Both verbs are natural and the meaning is clear, so this is not a finding. If the project wants error messages to repeat button verbs, align them to "сменить".
- **Existing string, outside this pack.** `reportSendFailed` in English and all seven languages still says "check your connection and try again". That is the kind of cause-promising this pack avoids. It shows on a different path (a connection failure), so it may be intended, but it is worth confirming that the report page never shows it for a server refusal.
- **Applied 2026-10-02:** all four findings. `reportSendFailed` ("check your connection") now
  shows only when the server said nothing; a refusal with server text shows `reportNotAccepted`
  over it. The Russian verbs and German articles are left as they are.
- **German articles.** The new German headlines use an article ("Die Meldung", "Der Player", "Der Code"). Older ones drop it ("Beitrag konnte nicht gelöscht werden.", "Meldung konnte nicht gesendet werden – …"). Both are correct German. If the project wants one style, the article form reads better as a standalone headline.
