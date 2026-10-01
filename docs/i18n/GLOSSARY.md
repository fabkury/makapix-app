# Translation glossary and style

For whoever writes or reviews a translation — a person or a model. English meaning comes from
[`CONTEXT.md`](../../CONTEXT.md), which stays the terminology authority; this file says how each
term is rendered in the other seven languages, so that one concept has one word across the app.

A term is added here the first time a batch needs it (PLAN.md). When a review changes a term,
change it here first, then in every message that uses it.

## Never translated

Brand and product names: **Makapix Club**, **Makapix Editor**, **Makapix**. File formats and
technical tokens: `.mkpx`, PNG, GIF, WebP, APNG, JPEG, BMP, MP4, GPL, Aseprite, RGB, RGBA, HEX,
AA, px, ms, fps, KiB, MiB. Third-party names: GitHub, Apple, Google, Android, iOS, Windows.
User-written content (titles, comments, handles, hashtags) is never translated. Terms of Service
and legal pages stay in English.

`HSV` keeps its Latin abbreviation in every language except French, where artists know it as
`TSV` (teinte, saturation, valeur).

## Voice

| | Address | Notes |
|---|---|---|
| es | tú | Neutral international Spanish; avoid regionalisms where a neutral word exists. |
| pt | você | Brazilian Portuguese. |
| fr | vous | A no-break space (U+00A0) before `:` `;` `!` `?`. |
| de | du | Nouns capitalized; prefer the short native word to the compound when both exist. |
| ru | вы (lowercase) | Tool names are nouns (Карандаш, Заливка); actions are infinitives. |
| ja | です／ます, no pronouns (あなた only in notifications) | A space around Latin words and name-like placeholders; none between a number and its counter (see "Decided in the L3 review"). Full-width punctuation. |
| zh | 你 | Simplified. A half-width space between Chinese and Latin or digits. Full-width punctuation. |

All languages: sentence case, as in English. Short and plain, like the English. No exclamation
marks the English does not have. The ellipsis is the single character `…`. A button names its
action with the same verb the menu item uses.

## Field labels, titles, and buttons

A text-field label and a top-bar title are one line and are cut off when too long; the screen
sweeps fail on that at a 320 px phone. When a natural translation does not fit, shorten the
wording (drop an article or a preposition, pick a shorter synonym) — as French "Confirmer le mot
de passe" for "Confirm new password". Confirmation words the user must type (delete account)
are each language's own word, typable on that language's keyboard.

## Short labels

Messages whose key ends in `Short` are toolbar tile labels: one line, 54 px wide, 8.5 px type.
The limit is **48 px measured in Roboto** (`ToolTile.labelBudget`; `tool_label_fit_test.dart`
enforces it) — about ten Latin letters, nine Cyrillic, or five CJK characters. Prefer a real
short word to an abbreviation; when abbreviating, end with a period (es `Sel. color`). The short
label must not be longer than the full name, and no two tools may share one.

## Terms

### Club

| en | es | pt | fr | de | ru | ja | zh |
|---|---|---|---|---|---|---|---|
| artwork (a published piece) | obra | arte | œuvre | Werk | работа | 作品 | 作品 |
| post (noun) | publicación | publicação | publication | Beitrag | публикация | 投稿 | 帖子 |
| publish / post (verb) | publicar | publicar | publier | veröffentlichen | опубликовать | 投稿する | 发布 |
| feed | feed | feed | fil | Feed | лента | フィード | 动态 |
| follow | seguir | seguir | suivre | folgen | подписаться | フォローする | 关注 |
| followers | seguidores | seguidores | abonnés | Follower | подписчики | フォロワー | 粉丝 |
| following | siguiendo | seguindo | abonnements | Folge ich | подписки | フォロー中 | 关注 |
| reaction | reacción | reação | réaction | Reaktion | реакция | リアクション | 回应 |
| comment | comentario | comentário | commentaire | Kommentar | комментарий | コメント | 评论 |
| remix | remix | remix | remix | Remix | ремикс | リミックス | 再创作 |
| hashtag | hashtag | hashtag | hashtag | Hashtag | хештег | ハッシュタグ | 话题标签 |
| mention | mención | menção | mention | Erwähnung | упоминание | メンション | 提及 |
| handle (@name) | nombre de usuario | nome de usuário | pseudo | Benutzername | имя пользователя | ユーザー名 | 用户名 |
| profile | perfil | perfil | profil | Profil | профиль | プロフィール | 个人主页 |
| account | cuenta | conta | compte | Konto | аккаунт | アカウント | 账号 |
| sign in | iniciar sesión | entrar | se connecter | anmelden | войти | ログイン | 登录 |
| sign out | cerrar sesión | sair | se déconnecter | abmelden | выйти | ログアウト | 退出登录 |
| settings | ajustes | configurações | paramètres | Einstellungen | настройки | 設定 | 设置 |
| report (verb) | denunciar | denunciar | signaler | melden | пожаловаться | 通報する | 举报 |
| block | bloquear | bloquear | bloquer | blockieren | заблокировать | ブロックする | 屏蔽 |
| moderator | moderador | moderador | modérateur | Moderator | модератор | モデレーター | 管理员 |
| community rules | normas de la comunidad | regras da comunidade | règles de la communauté | Community-Regeln | правила сообщества | コミュニティルール | 社区规则 |
| Contribute (open the editor from the Club) | contribuir | contribuir | contribuer | beitragen | создать | 作品を描く | 创作 |
| player (a Makapix display device) | reproductor | player | lecteur | Player | плеер | プレーヤー | 播放器 |
| badge | insignia | insígnia | badge | Abzeichen | значок | バッジ | 徽章 |
| 6-digit code | código de 6 dígitos | código de 6 dígitos | code à 6 chiffres | 6-stelliger Code | 6-значный код | 6桁のコード | 6 位验证码 |
| temporary password | contraseña temporal | senha temporária | mot de passe temporaire | temporäres Passwort | временный пароль | 仮パスワード | 临时密码 |
| linked logins | inicios de sesión vinculados | logins vinculados | connexions associées | verknüpfte Anmeldungen | привязанные способы входа | 連携ログイン | 关联登录 |
| like (a comment) | me gusta | curtir | j'aime | gefällt mir | нравится | いいね | 赞 |
| highlights (an artist's picked best works) | mejores obras | melhores artes | sélection | Highlights | лучшее | ハイライト | 代表作 |
| featured (on the welcome page) | destacados | destaques | à la une | empfohlen | подборка | 注目の作品 | 精选 |
| reputation | reputación | reputação | réputation | Reputation | репутация | 評価 | 声望 |
| tagline | lema | frase | devise | Motto | девиз | ひとこと | 个性签名 |
| lineage (originals and remixes of an artwork) | linaje | linhagem | filiation | Abstammung | происхождение | 系譜 | 创作脉络 |
| layers file (.mkpx) | archivo con capas | arquivo com camadas | fichier avec calques | Ebenendatei | файл со слоями | レイヤーファイル | 图层文件 |
| promote / demote (moderator; adds to / removes from the Recommended feed) | recomendar / quitar de Recomendados | promover / remover promoção | mettre en avant / retirer | empfehlen / Empfehlung aufheben | добавить в рекомендуемое / убрать из рекомендуемого | おすすめに追加 / 外す | 推荐 / 取消推荐 |
| hide / unhide (a post) | ocultar / mostrar | ocultar / reexibir | masquer / réafficher | ausblenden / einblenden | скрыть / показать | 非表示 / 再表示 | 隐藏 / 取消隐藏 |
| download (a ZIP export of your artworks) | descarga | download | téléchargement | Download | скачивание (загрузка = upload, loading) | ダウンロード | 下载 |
| community rules | normas de la comunidad | regras da comunidade | règles de la communauté | Community-Regeln | правила сообщества | コミュニティルール | 社区规则 |
| Terms of Service | Términos del servicio | Termos de Serviço | Conditions d'utilisation | Nutzungsbedingungen | Условия использования | 利用規約 | 服务条款 |
| ban / unban (moderator; distinct from a user's block) | expulsar / readmitir | banir / remover banimento | bannir / lever le bannissement | sperren / entsperren | забанить / разбанить | 利用停止 / 利用停止を解除 | 封禁 / 解除封禁 |
| trusted (user) | de confianza | confiável | de confiance | vertrauenswürdig | доверенный | 信頼済み | 受信任 |
| reputation | reputación | reputação | réputation | Reputation | репутация | 評価 | 声望 |
| report (noun) | denuncia | denúncia | signalement | Meldung | жалоба | 通報 | 举报 |
| blocked users (the list) | usuarios bloqueados | usuários bloqueados | utilisateurs bloqués | blockierte Nutzer | чёрный список | ブロックしたユーザー | 已屏蔽的用户 |
| monitored hashtags | hashtags supervisados | hashtags monitoradas | hashtags surveillés | überwachte Hashtags | отслеживаемые хештеги | 監視対象のハッシュタグ | 受监控的话题标签 |

### Editor

| en | es | pt | fr | de | ru | ja | zh |
|---|---|---|---|---|---|---|---|
| drawing (a local document) | dibujo | desenho | dessin | Zeichnung | рисунок | イラスト | 画作 |
| layer | capa | camada | calque | Ebene | слой | レイヤー | 图层 |
| frame | fotograma | quadro | image | Frame | кадр | フレーム | 帧 |
| canvas | lienzo | tela | toile | Leinwand | холст | キャンバス | 画布 |
| selection | selección | seleção | sélection | Auswahl | выделение | 選択範囲 | 选区 |
| palette | paleta | paleta | palette | Palette | палитра | パレット | 调色板 |
| color | color | cor | couleur | Farbe | цвет | 色 | 颜色 |
| primary color | color primario | cor primária | couleur principale | Primärfarbe | основной цвет | メインカラー | 主色 |
| opacity | opacidad | opacidade | opacité | Deckkraft | непрозрачность | 不透明度 | 不透明度 |
| blend mode | modo de fusión | modo de mesclagem | mode de fusion | Mischmodus | режим наложения | 合成モード | 混合模式 |
| pattern | patrón | padrão | motif | Muster | узор | パターン | 图案 |
| dither | tramado | pontilhado | tramage | Dithering | дизеринг | ディザ | 抖动 |
| gradient | degradado | gradiente | dégradé | Verlauf | градиент | グラデーション | 渐变 |
| mirror (symmetry) | espejo | espelho | miroir | Spiegel | зеркало | ミラー | 镜像 |
| anti-alias | suavizado | suavização | anticrénelage | Kantenglättung | сглаживание | アンチエイリアス | 抗锯齿 |
| onion skin | papel cebolla | papel cebola | pelure d'oignon | Zwiebelhaut | калька | オニオンスキン | 洋葱皮 |
| undo / redo / repeat | deshacer / rehacer / repetir | desfazer / refazer / repetir | annuler / rétablir / répéter | rückgängig / wiederherstellen / erneut anwenden | отменить / вернуть / повторить | 元に戻す / やり直し / 繰り返し | 撤销 / 重做 / 重复 |
| open / import / export / save | abrir / importar / exportar / guardar | abrir / importar / exportar / salvar | ouvrir / importer / exporter / enregistrer | öffnen / importieren / exportieren / speichern | открыть / импорт / экспорт / сохранить | 開く / インポート / エクスポート / 保存 | 打开 / 导入 / 导出 / 保存 |
| draft (pending, uncommitted change) | boceto | rascunho | ébauche | Entwurf | черновик | 下書き | 草稿 |
| slow (geared drag) | lento | lento | lent | langsam | медленно | スロー | 慢速 |
| threshold | umbral | limiar | seuil | Schwelle | порог | しきい値 | 阈值 |
| replay | repetición | replay | replay | Replay | повтор | リプレイ | 回放 |
| timelapse | time-lapse | timelapse | timelapse | Zeitraffer | таймлапс | タイムラプス | 延时视频 |

Open and Import are different gestures (CONTEXT.md): keep two distinct words in every language.

**Decided in the L3 review (2026-10-02).** Where a word did two jobs, one job moved:
- **Discard** is never the word for Delete or Cancel: fr *abandonner*, ru *не сохранять*,
  de *verwerfen*.
- **Upload** to the Club is fr *envoyer / envoi* (*importer* stays the editor's Import);
  ru *отправка*.
- **Download** is ru *скачать / скачивание*; *загрузка* is upload and loading.
- **"Verlauf"** (de) is the gradient: write *Farbverlauf* in running text, and never use it for
  history.
- **"tela"** (pt) is the canvas only; the screen is *janela* ("Ajustar à janela").
- **Export / Import** in Japanese are エクスポート / インポート everywhere; 読み込む means load.
- **Invert** in Chinese is 反相 everywhere (反转 is too close to Flip, 翻转); noise dithers are
  噪声 (噪点 is photographic grain).
- **The Move tool vs. shift** in German: the tool is *Verschieben* (its tile says *Bewegen*:
  "Verschieben" is 49 px against the 48 px tile budget), moving items one position is
  *versetzen*.
- **Notification sender**: the honorific lives in `notifActor` (Japanese "{handle} さん");
  the templates use the bare {who}, so the unknown-sender fallback never gets さん.
- **"artwork" in the editor** is the local drawing: ru *рисунок*, de *Zeichnung* (*работа* /
  *Werk* stay for published Club artworks).
- **Tool tips** use the imperative (es, pt, fr), and name every option exactly as its chip
  says, capitalized as on screen.
- **Bare "Club"** inside a Russian sentence is written *Makapix Club* (it cannot decline).
- **"Reacted"** (the profile tab of artworks the user reacted to) must differ from
  "Reactions" (received): es *Reaccionó*, pt *Reagiu*, ru *Понравилось*, ja リアクション済み.
- **Japanese spacing**, settled: a half-width space between Japanese and a Latin word or a
  placeholder that stands for a name, title, or handle (GitHub で登録, {name} を開きました);
  no space between a number or numeric placeholder and its Japanese counter ({count}フレーム,
  3件), and none in 50%. The pre-review messages that space a counter are tolerated, not a
  pattern to follow.
- **Japanese pronouns**: あなた only in notifications; elsewhere drop it or say 自分.
- **Decimal input**: numeric fields accept a comma or a point, so labels may show each
  language's own decimal mark (",5", "0,1").

**Selection** has two meanings. The table row above is the pixel selection (the Select
tools). The set of frames or layers picked on the Frames and Layers pages uses the same word
in the Latin-script languages and Russian (выделение), and the plain "chosen" words in
Japanese and Chinese (選択 / 所选), not 選択範囲 / 选区, which mean an area of pixels.

More editor terms (Frames and Layers pages):

| en | es | pt | fr | de | ru | ja | zh |
|---|---|---|---|---|---|---|---|
| stack (the layers of a frame) | pila | pilha | pile | Stapel | стопка | 重ね順 | 堆叠 |
| Move group | grupo de movimiento | grupo de movimento | groupe de déplacement | Bewegungsgruppe | группа сдвига | 移動グループ | 移动组 |
| shift (move items one position) | desplazar | deslocar | décaler | versetzen | сдвиг | ずらす | 移位 |
| merge (layers) | combinar | mesclar | fusionner | vereinen | объединить | 結合 | 合并 |
| off-canvas (kept outside the canvas) | fuera del lienzo | fora da tela | hors toile | außerhalb | за холстом | キャンバス外 | 画布外 |
| active (the layer you draw on) | activa | ativa | actif | aktiv | активный | アクティブ | 当前图层 |
| duration (of a frame) | duración | duração | durée | Dauer | длительность | 表示時間 | 时长 |

### Palettes, patterns, and dither

- **Bayer** is a person's name: Latin in the Latin-script languages, transliterated in
  Russian (Байер), Japanese (ベイヤー), and Chinese (拜耳).
- **Ramp** (a run of one hue from dark to light): rampa (es, pt), rampe (fr), Verlauf (de),
  ряд (ru), described rather than named in Japanese and Chinese.
- **Preset** palettes: predefinidas (es, pt), préréglages (fr), Vorlagen (de), готовые
  палитры (ru), プリセット, 预设.
- **Halftone**: semitono, meio-tom, demi-teintes, Halbton, полутон, ハーフトーン, 半色调.
- **ON / OFF** (the two preview colors of a pattern) are the words of a switch: ON / OFF in
  Spanish, Portuguese, and French; AN / AUS; ВКЛ / ВЫКЛ; オン / オフ; 开 / 关. The page hints
  use the same words.
- **Color models**: RGB and HSV everywhere except French (RVB, TSV; channel letters R V B and
  T S V).

### Blend modes

The eleven names are the `blend*` messages, taken from what image editors call them in each
language (Photoshop's localized names, where it has one). They differ on purpose from a
word-for-word translation: French Screen is "Superposition" and Overlay is "Incrustation";
German Screen is "Negativ multiplizieren" and Overlay is "Ineinanderkopieren"; Russian
Lighten is «Замена светлым»; Japanese Darken / Lighten are 比較（暗）/ 比較（明）; Chinese
Multiply is 正片叠底 and Screen is 滤色. The two-letter tile badges are one message
(`blendBadges`, ten codes in wire order; one character each in Japanese and Chinese), and a
test keeps them unique per language.

A keyboard key is named as printed on that language's keyboards (the `key*` messages):
Ctrl is "Strg" in German; Shift is "Mayús", "Maj", "Umschalt"; Enter is "Entrée", "Eingabe"
(Spanish keeps "Enter", which Latin American keyboards print and every reader knows); Delete is "Supr", "Suppr", "Entf"; the space bar is "Espacio", "Espaço", "Espace",
"Leertaste", «Пробел», スペース, 空格. Russian, Japanese, Chinese, and Brazilian keyboards keep
the English legends for the rest.

### Replay and timelapse

- **Finale** (the last part of a timelapse, where the finished animation plays): el final,
  o final, le final, das Finale, финал, フィナーレ, 结尾.
- **Shape** of a timelapse (square or tall) is the aspect, and must not collide with
  **Format** (the file type) in the same dialog: Proporción, Proporção, Proportions,
  Seitenverhältnis, Пропорции, 縦横比, 画面比例.
- **Chapter** (a segment of a recording): capítulo, chapitre, Kapitel, глава, チャプター, 章节.

### Tools

The tool names (full and short) are the `tool*` messages in the ARB files; that is their
glossary. Notable choices:

- **Dodge / Burn** use the plain words for lighten and darken in Spanish, Portuguese, French,
  and German rather than the darkroom jargon; Japanese and Chinese keep the terms their paint
  programs use (覆い焼き / 焼き込み, 减淡 / 加深).
- **Flip vs. Invert** must stay distinct: Flip mirrors geometry, Invert inverts colors. Japanese
  uses 反転 for Flip and 色反転 for Invert.
- **Redo vs. Repeat** must stay distinct (German: Wiederherstellen vs. Erneut anwenden; Russian:
  Вернуть vs. Повторить).

### Tool options

The option labels are the `opt*` messages; the help tips (`tip*`) name options by those same
words, so change both together. Decisions:

- **Draft vs. Eraser in Spanish.** Both are naturally "borrador"; the Eraser keeps it and a
  draft is "boceto".
- **Shape** is two words in Russian: the Shape tool is Фигура, the brush tip's shape is Форма.
- **Fill** is two messages: the button that fills at the reticle (a verb: Rellenar, Füllen)
  and the filled-shape mode (Relleno, Gefüllt).
- **Width** of a stroke is its thickness (Grosor, Épaisseur, Stärke, Толщина), not the canvas
  width (Ancho, Largeur, Breite), which is a separate message.
- **One-letter slider labels**: H / S / V stay Latin; Brightness / Contrast take each
  language's own letters (de H / K, ru Я / К); the Levels inputs are L / H in English and
  Min / Max elsewhere.
- **AA** and **cleanEdge** are not translated.

### Names stored in documents

- A drawing nobody named is "Untitled" in the current language (`untitled`). The stored title
  is whatever language the app was in at the time; any language's default reads as unnamed.
- Layers are named by the engine, in English, inside the document ("Layer 1", "Layer 1
  copy"). They are translated only for display (`layerDefaultName`, `layerCopyName`); a name
  the artist typed is never touched.
- French uses "Annuler" for both Cancel and Undo, as French software does.

## Open terminology questions

None open.
