# Russian (ru): second-pass review of the rewrites

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| artworkMenuPromote | medium | The feed is named «Рекомендуемое» (`feedRecommended`) and the dialog, toasts, and notification all quote it that way; this menu item alone uses a lowercase bare adjective, which reads as an odd substantivized "the recommended" rather than the feed's name. | Добавить в рекомендуемое… | Добавить в «Рекомендуемое»… |
| artworkMenuDemote | medium | Same inconsistency as `artworkMenuPromote` (cf. `modDemoteTitle` «Рекомендуемого»). | Убрать из рекомендуемого… | Убрать из «Рекомендуемого»… |
| modChipPromoted | medium | Same inconsistency: lowercase, unquoted feed name, unlike every dialog and toast. | В рекомендуемом · {category} | В «Рекомендуемом» · {category} |
| outgoingDiscard | low | The rewrite makes the button "Не сохранять", but its follow-up confirmation (`discardDrawingTitle`, not in this pack) still reads «Удалить «{name}»?», so one action is named by two different verbs in two consecutive dialogs. Align the confirmation with the button. | Не сохранять | Keep; change `discardDrawingTitle` to «Не сохранять «{name}»?» |
| modTagsPostGone | low | The save can remove or change moderator hashtags, not only add them; "добавить" narrows the meaning. | К этой публикации нельзя добавить хештеги — возможно, она удалена. | Хештеги этой публикации нельзя изменить — возможно, она удалена. |
| avatarFromPostTitle | low | The menu item that opens this dialog now says "Использовать как фото профиля…"; the dialog title uses a different verb and noun form ("Сделать фотографией") and has no object. | Сделать фотографией профиля? | Использовать как фото профиля? |
| rulesGateBody | low | "мы баним" is slang in an otherwise formal policy paragraph, and it switches from the passive ("удаляются") to the active voice mid-sentence. A neutral phrase keeps the ban/block distinction without the colloquialism. | …материалы, нарушающие правила, удаляются, а систематических нарушителей мы баним. | …материалы, нарушающие правила, удаляются, а систематические нарушители лишаются доступа. |
| tipCopyPaste | low | "очищает выделение из слоя или всего кадра" attaches the source to "clear" grammatically, and unlike the other rewritten tips (`tipBucket`, `tipDodge`, `tipResize`) the options are not named by their chip labels (Слой / Кадр). | Копирует, вырезает, вставляет или очищает выделение из слоя или всего кадра. Вставка появляется подвижным черновиком. | Копирует, вырезает, вставляет или очищает выделение; источник: «Слой» или «Кадр». Вставка появляется подвижным черновиком. |
| layersResetSub | low | "наложение «Обычный»": the masculine name agrees with "режим", not with "наложение", so the phrase reads ungrammatical. | Видимые, незаблокированные, непрозрачность 255, наложение «Обычный» | Видимые, незаблокированные, непрозрачность 255, режим «Обычный» |
| reasonCopyright | low | "нарушение … интеллектуальной собственности" is loose; one infringes rights to it. | Нарушение авторских прав или интеллектуальной собственности | Нарушение авторских или иных интеллектуальных прав |

Checked 123 messages.
