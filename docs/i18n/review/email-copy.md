# Email copy review (es, pt, fr, de, ru, ja, zh)

Pack: `email-copy.jsonl`, 17 messages × 7 languages: the verification-code, password-reset-code,
and download-ready emails. All placeholders ({handle}, {code}, {count}, {expires}, {url}) survive
untouched in every language; the footer is identical everywhere; terminology matches the glossary
(obra / arte / œuvre / Werk / работа / 作品 / 作品; download = descarga / download / téléchargement /
Download / скачивание / ダウンロード / 下载) and the app's own auth and download screens
(restablecer, redefinir, réinitialiser, zurücksetzen, сброс, 再設定, 重置; the button matches
`pmdDownload` in every language). Greetings follow each language's letter convention (es
"Hola, {handle}:", fr "Bonjour {handle},", ru "Здравствуйте, {handle}!", zh "{handle}，你好："). No
high-severity findings.

| lang | key | severity | problem | current | proposed |
|---|---|---|---|---|---|
| es | bdr_why | low | "correo" twice in two short sentences; the second can be a pronoun. | Recibes este correo porque solicitaste una descarga por lotes en Makapix Club. Si no fuiste tú, puedes ignorar este correo. | Recibes este correo porque solicitaste una descarga por lotes en Makapix Club. Si no fuiste tú, puedes ignorarlo. |
| pt | code_expiry | low | This line sits right under the bare 6-digit code; opening with the pronoun "Ele" for a thing reads translated. Brazilian services name the code. | Ele expira em 10 minutos. | O código expira em 10 minutos. |
| fr | bdr_why | low | "Si ce n'est pas vous" is colloquial for a security line; French services say "si vous n'êtes pas à l'origine de cette demande". | … Si ce n'est pas vous, vous pouvez ignorer cet e-mail. | Vous recevez cet e-mail car vous avez demandé un téléchargement groupé sur Makapix Club. Si vous n'êtes pas à l'origine de cette demande, vous pouvez ignorer cet e-mail. |
| de | verify_intro, reset_intro, bdr_ready | low | These are the first body line after the salutation "Hallo {handle}," (comma). German letter convention (DIN 5008) continues in lowercase after a comma salutation, unless the word is a noun. | Hier ist dein Code, … / Hier ist dein Code, … / Dein Sammel-Download ist bereit. | hier ist dein Code, um deine E-Mail-Adresse bei Makapix Club zu bestätigen: / hier ist dein Code, um dein Passwort für Makapix Club zurückzusetzen: / dein Sammel-Download ist bereit. |
| de | reset_subject | low | Long subject with a doubled possessive (Dein … deines); the second possessive adds nothing and costs inbox width. | Dein Code zum Zurücksetzen deines Passworts für Makapix Club | Dein Code zum Zurücksetzen des Passworts für Makapix Club |
| de | bdr_subject | low | A download "steht bereit" is the idiomatic phrasing; "ist bereit" reads literal. | Dein Download von Makapix Club ist bereit | Dein Download von Makapix Club steht bereit |
| ru | bdr_why | medium | "пакетное скачивание" is translationese, and the same email calls the thing "архив работ" in the subject and first line; "письмо" is also repeated. | Вы получили это письмо, потому что запросили пакетное скачивание в Makapix Club. Если это были не вы, просто проигнорируйте это письмо. | Вы получили это письмо, потому что запросили архив работ в Makapix Club. Если это были не вы, просто проигнорируйте его. |
| ru | code_expiry | low | The line sits right under the bare code; "Он" with no noun in the line reads abrupt. Name the code. | Он действует 10 минут. | Код действует 10 минут. |
| ja | greeting_named | low | Glossary (L3 review) puts a half-width space before さん after a handle placeholder, as `notifActor` does: "{handle} さん". | {handle}さん | {handle} さん |
| ja | verify_subject | low | Glossary spacing rule: a half-width space between a Latin word and Japanese; the app writes "Makapix Club に…", "Makapix Club の…" everywhere. | Makapix Clubの確認コード | Makapix Club の確認コード |
| ja | verify_intro | low | Same spacing rule. | Makapix Clubでメールアドレスを確認するためのコードは次のとおりです。 | Makapix Club でメールアドレスを確認するためのコードは次のとおりです。 |
| ja | reset_subject | low | Same spacing rule. | Makapix Clubのパスワード再設定コード | Makapix Club のパスワード再設定コード |
| ja | reset_intro | low | Same spacing rule. | Makapix Clubのパスワードを再設定するためのコードは次のとおりです。 | Makapix Club のパスワードを再設定するためのコードは次のとおりです。 |
| ja | bdr_subject | low | Same spacing rule. | Makapix Clubのダウンロードの準備ができました | Makapix Club のダウンロードの準備ができました |
| ja | bdr_expiry | low | {expires} renders as "2026-10-12 14:00 UTC", which starts with digits and ends with the Latin "UTC"; without spaces it glues to は and です ("有効期限は2026-10-12 14:00 UTCです"). | このリンクの有効期限は{expires}です。 | このリンクの有効期限は {expires} です。 |
| ja | bdr_why | low | Same spacing rule. | このメールは、Makapix Clubで一括ダウンロードを… | このメールは、Makapix Club で一括ダウンロードをリクエストされたためお送りしています。お心当たりがない場合は、このメールを無視してください。 |
| zh | verify_intro | low | "验证邮箱地址的验证码" repeats 验证 back to back; mainland verification emails phrase it with the code announced last. | 以下是你在 Makapix Club 验证邮箱地址的验证码： | 你正在 Makapix Club 验证邮箱地址，验证码如下： |
| zh | reset_ignore | low | "你的密码没有更改" reads like "you did not change your password"; the reassurance services give is that the password stays unchanged. | …你的密码没有更改。 | 如果你没有申请重置密码，请忽略这封邮件。你的密码不会被更改。 |

## Systemic notes

- **Japanese spacing around "Makapix Club" and {expires}.** Every Japanese message that contains
  the brand glues it to the following particle ("Makapix Clubの", "Makapix Clubで"). The glossary's
  settled rule (L3 review, 2026-10-02) and every app string ("Makapix Club にログイン", "Makapix Club
  の @{handle}") put a half-width space there, so the emails should too. The review brief's ja line
  ("no space between Japanese and Latin letters") predates that decision; the glossary wins. The same
  rule covers "{handle} さん" and the date placeholder, which ends in the Latin "UTC".
- **German letter convention after "Hallo {handle},".** A comma salutation is followed by a
  lowercase first word in German correspondence. Since `greeting_named` / `greeting_anonymous` always
  precede `verify_intro`, `reset_intro`, and `bdr_ready`, those three should start lowercase
  ("hier", "dein"). If the server may ever render a body line without a greeting, the alternative is
  to keep the capitals and end the salutation with "!" instead ("Hallo {handle}!"), which also takes
  a capital after it.
- **Name the code on the expiry line (pt, ru).** `code_expiry` sits directly under the code, which
  is shown big on its own line; a bare pronoun ("Ele", "Он") has no noun on screen to refer to.
  es ("Caduca…"), fr ("Il expire…"), and de ("Er läuft…") read fine there; pt and ru read better
  saying "O código" / "Код".
- **One name for the ZIP in Russian.** Russian calls it "архив" in the subject and first line but
  "пакетное скачивание" in the small print; keep "архив работ" throughout, with "скачивание" (per the
  glossary) for the act of downloading.
- The other languages' term for "batch download" (descarga por lotes, download em lote,
  téléchargement groupé, Sammel-Download, 一括ダウンロード, 批量下载) does not appear on any app screen
  (the app says only "Downloads" / "Request download"), but each is a correct, natural rendering and
  consistent within its email; no change needed.

**Applied 2026-10-05:** all findings; German takes the reviewer's alternative (`Hallo {handle}!` with capitals after it), since the server's layout is not ours to assume. Delivered in `messages/0005-localized-text/email-copy/` (server `develop` 12156ed).
