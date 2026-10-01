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
| ja | です／ます, no pronouns | No space between Japanese and Latin or digits. Full-width punctuation. |
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
| featured (on the welcome page) | destacados | destaques | à la une | empfohlen | избранное | 注目の作品 | 精选 |
| reputation | reputación | reputação | réputation | Reputation | репутация | 評価 | 声望 |
| tagline | lema | frase | devise | Motto | девиз | ひとこと | 个性签名 |
| lineage (originals and remixes of an artwork) | linaje | linhagem | filiation | Abstammung | происхождение | 系譜 | 创作脉络 |
| layers file (.mkpx) | archivo con capas | arquivo com camadas | fichier avec calques | Ebenendatei | файл со слоями | レイヤーファイル | 图层文件 |
| promote / demote (moderator) | destacar / quitar de destacados | promover / remover promoção | mettre en avant / retirer | empfehlen / Empfehlung aufheben | продвинуть / снять продвижение | おすすめに追加 / 外す | 推荐 / 取消推荐 |
| hide / unhide (a post) | ocultar / mostrar | ocultar / reexibir | masquer / réafficher | ausblenden / einblenden | скрыть / показать | 非表示 / 再表示 | 隐藏 / 取消隐藏 |
| download (a ZIP export of your artworks) | descarga | download | téléchargement | Download | загрузка | ダウンロード | 下载 |
| community rules | normas de la comunidad | regras da comunidade | règles de la communauté | Community-Regeln | правила сообщества | コミュニティルール | 社区规则 |
| Terms of Service | Términos del servicio | Termos de Serviço | Conditions d'utilisation | Nutzungsbedingungen | Условия использования | 利用規約 | 服务条款 |
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
| replay | repetición | replay | replay | Replay | повтор | リプレイ | 回放 |
| timelapse | time-lapse | timelapse | timelapse | Zeitraffer | таймлапс | タイムラプス | 延时视频 |

Open and Import are different gestures (CONTEXT.md): keep two distinct words in every language.

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

## Open terminology questions

- **Draft** (CONTEXT.md: visible but uncommitted editor state) vs. **Eraser** in Spanish: both
  are naturally "borrador". Decide when batch E1/E2 shows where "draft" appears in UI text.
