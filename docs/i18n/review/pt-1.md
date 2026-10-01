# Brazilian Portuguese review, part 1 (messages 1–550)

Independent native-level review of `pt` against the English source and `docs/i18n/GLOSSARY.md`.
Only real problems are listed; a message with no row was read and found correct.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| toolSelectLayerShort | low | Alone on a tile, "Da camada" ("of the layer") does not say what the tool does; the sibling tile is "Sel. cor". | Da camada | Sel. camada (if it fits the 48 px budget; otherwise "Sel. cam.") |
| commentsGuest | low | "convidado" means someone who was invited; a person commenting without an account is a "visitante". | convidado | visitante |
| modTagsPostGone | medium | "marcar esta publicação" reads as "mark/flag this post" (or tag a person), not "add hashtags to it". | Não é possível marcar esta publicação: ela pode ter sido excluída. | Não é possível adicionar hashtags a esta publicação: ela pode ter sido excluída. |
| modTagsAddLabel | low | "tag" here, "hashtag" in every other message of the same sheet. | Adicionar tag | Adicionar hashtag |
| playerSent | low | What was sent is "a arte" (feminine, glossary); the participle should agree. | Enviado para {player} | Enviada para {player} |
| playerMirror | low | The label is a verb, but its options "Nenhum" / "Ambos" answer a noun; "Rotação" beside it is a noun too. | Espelhar | Espelhamento |
| playerManageSubtitle | low | A row subtitle describes what the page does; Brazilian apps use the infinitive there, not the imperative. | Registre, renomeie ou remova dispositivos | Registrar, renomear ou remover dispositivos |
| monitored13plus | low | "maiores de 13 anos" strictly excludes age 13; the English includes it. | Para maiores de 13 anos | A partir de 13 anos |
| authBackToSignIn | medium | "Voltar para entrar" reads as "go back in order to enter"; the verb "entrar" cannot stand for the sign-in form as a noun. | Voltar para entrar | Voltar ao login |
| createAccountTempIntro | medium | "a senha temporária do seu e-mail" reads as "your email account's password"; the password was sent by email. | Digite a senha temporária do seu e-mail para concluir. Você poderá escolher sua própria senha na próxima etapa. | Digite a senha temporária que enviamos por e-mail para concluir. Você poderá escolher sua própria senha na próxima etapa. |
| authVerifiedEnterTemp | medium | Same ambiguity: "senha temporária do seu e-mail". | E-mail verificado. Digite a senha temporária do seu e-mail para concluir. | E-mail verificado. Digite a senha temporária que enviamos por e-mail para concluir. |
| authEnterTemp | medium | Same ambiguity: "senha temporária do seu e-mail". | Digite a senha temporária do seu e-mail. | Digite a senha temporária que enviamos por e-mail. |
| authEnterCode | low | Same pattern, less risky with a code: "código … do seu e-mail". | Digite o código de 6 dígitos do seu e-mail. | Digite o código de 6 dígitos que enviamos por e-mail. |
| deleteAccountDoneBody | low | "Obrigado" is gendered for the speaker; the neutral company voice avoids it. | … Obrigado por ter feito parte do Makapix Club. | … Agradecemos por você ter feito parte do Makapix Club. |
| deleteAccountBullet4 | low | "desconectado" is masculine for every user and is not the glossary's sign-out word ("sair"). | Você será desconectado imediatamente e sua conta será desativada. … | Sua sessão será encerrada imediatamente e sua conta será desativada. … |
| accountSignedInAs | low | "Conectado" is masculine for every user and reads as "online" rather than "signed in". | Conectado • {roles} | Sessão ativa • {roles} |
| feedRecommended | low | The feed lists "artes" (feminine); the filter options already agree in the feminine (Estática, Animada). | Recomendados | Recomendadas |
| noLoginToDraw | low | "entrar" with no object is ambiguous in a caption ("enter"?), and the caption must be short. | Desenhe sem precisar entrar → | Desenhe sem login → |
| accountCanPostPublicly | low | "publicar publicamente" repeats the root; `notifApproved` already says "para todos". | Pode publicar publicamente | Pode publicar para todos |
| notifTrust | low | "divulgação pública" for "public release" is stiff and differs from `notifApproved` ("publicada para todos"). | Você recebeu Confiança: suas publicações agora são aprovadas automaticamente para divulgação pública | Você recebeu Confiança: suas publicações agora são aprovadas automaticamente e ficam visíveis para todos |
| notifTrustBy | low | Same as `notifTrust`. | {who} concedeu Confiança a você: suas publicações agora são aprovadas automaticamente para divulgação pública | {who} concedeu Confiança a você: suas publicações agora são aprovadas automaticamente e ficam visíveis para todos |
| blockedToast | low | "bloqueado" is masculine whatever the blocked person's gender; `profileBlockedBanner` already uses the neutral form. | @{handle} bloqueado | Você bloqueou @{handle} |
| unblockedToast | low | Same as `blockedToast`. | @{handle} desbloqueado | Você desbloqueou @{handle} |
| profileTabReacted | medium | The tab lists artworks the user reacted to, but "Reações" is also the statistic on the same profile for reactions received (`statReactions`): one word, two opposite directions. | Reações | Reagiu |
| profileFeedReacted | medium | Same as `profileTabReacted`; keep the two identical. | @{handle} · Reações | @{handle} · Reagiu |
| profileGalleryWaiting | low | "está esperando" with no object sounds unfinished in Portuguese. | Sua galeria está esperando. | Sua galeria está esperando por você. |
| statsColViews | low | "Visual." reads as the word "visual", not as an abbreviation of "visualizações". | Visual. | Vis. |
| artworkTaggedByMod | medium | "Marcada por um moderador" has no clear subject and reads as "(the artwork was) flagged by a moderator"; the legend is about hashtags a moderator added, and the tooltip (`artworkTagByMods`) says "Adicionada". | Marcada por um moderador | Hashtag adicionada por um moderador |

28 findings: 0 high, 8 medium, 20 low.

## Systemic notes

1. **"do seu e-mail" for "from your email".** "A senha temporária do seu e-mail" is understood as
   the password *of* the user's email account, which is the wrong thing to ask for on a sign-in
   screen. Everywhere a code or password arrives by email, say "que enviamos por e-mail"
   (`createAccountTempIntro`, `authVerifiedEnterTemp`, `authEnterTemp`, `authEnterCode`).
2. **"Marcar" for "to tag".** In Brazilian apps "marcar" is to mark, to flag, or to tag a
   *person*. For hashtags it misleads in moderation contexts (`modTagsPostGone`,
   `artworkTaggedByMod`): say "adicionar hashtags" / "hashtag adicionada". "Arte marcada com
   #tag" (`hashtagFeedEmpty`) is fine because the hashtag is named.
3. **"Reações" carries two meanings.** Reactions received (statistics, titles) and artworks the
   user reacted to (profile tab, list name) share the word. Give the tab its own word
   ("Reagiu") everywhere it appears.
4. **"Entrar" works as a verb only.** The glossary's "entrar" is right on buttons and in
   sentences ("Entre para comentar"), but it cannot replace the noun "sign-in": "Voltar para
   entrar" and "Desenhe sem precisar entrar" stumble. Where English uses the noun, use "login",
   which the glossary already has in "logins vinculados" (and `homeOffline` already uses "login
   salvo").
5. **Gendered participles about people.** "Conectado", "desconectado", "bloqueado", "Obrigado"
   assume a masculine user or speaker. Most can be rephrased neutrally at no cost in length
   ("Você bloqueou @…", "Sua sessão será encerrada", "Agradecemos").
6. **Agreement with "arte" (feminine).** The glossary's "arte" makes artwork-related adjectives
   feminine; the pack mostly does this (Estática, Animada, Próxima, Oculta) but slips in
   "Enviado para {player}" and "Recomendados".
7. **"Public release" has three renderings**: "publicada para todos", "divulgação pública",
   "publicar publicamente". "Para todos" is the natural one; use it in all three places.
8. **Watch item for parts 2 and 3: Flip vs. Mirror.** The Flip tool (`toolFlip`) and the
   player's Mirror option (`playerMirror`) are both "Espelhar", and the glossary's symmetry
   term is "espelho". That is fine as long as the editor's symmetry option is not also labeled
   "Espelhar"; if it is, the Flip tool needs another word ("Virar").

What is good and should stay: "você" throughout, no European vocabulary or spelling, "…" as one
character everywhere, straight double quotes used consistently, ICU plurals complete and
grammatical, every placeholder intact, and the English em dashes turned into colons or periods,
which is how Brazilian interfaces punctuate.
