# Russian (ru) translation review, pack 3 (messages 1101–1645)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| layerMoveGroupTip | low | The plural verb has no subject: the chip and its tooltip are about this one layer. «вместе инструментом» also invites a misreading as "together with the tool"; naming the other layers removes it. | Двигаются вместе инструментом «Перемещение» (когда ничего не выделено) | Двигается вместе с другими слоями группы инструментом «Перемещение» (когда ничего не выделено) |
| toolNoteOn | medium | The note sits beside the Onion skin tool, whose Russian name «Калька» is feminine; the masculine form does not agree. | включён | включена |
| fileNew | low | A menu action should be an infinitive (glossary); the File > New item in Russian software is «Создать». | Новый | Создать |
| newDocName | low | A drawing's title is «название» everywhere else (`untitled` = «Без названия», `layerUnnamed` = «(без названия)»); «Имя» reads as a file or person name. | Имя (необязательно) | Название (необязательно) |
| loadOverBudget | low | Context is a local drawing (glossary: рисунок); «работа» is reserved for a published artwork. | Работа слишком велика, чтобы открыть её на этом устройстве. | Рисунок слишком велик, чтобы открыть его на этом устройстве. |
| outgoingDiscard | low | Russian buttons do not carry a pronoun; «Удалить его» reads clumsy. | Удалить его | Удалить |
| viewHintCrop | low | «щипок» is not the usual UI name of the gesture; Russian help text says «сведение пальцев» or names the fingers. | Масштаб: щипок, двойное касание или прокрутка. Один палец двигает рамку. | Масштаб: двумя пальцами, двойным касанием или прокруткой. Один палец двигает рамку. |
| viewHintPlace | low | Same as viewHintCrop. | Масштаб: щипок, двойное касание или прокрутка. Один палец двигает изображение. | Масштаб: двумя пальцами, двойным касанием или прокруткой. Один палец двигает изображение. |
| previewCut | low | «(часть)» does not say what is partial; reuse the word of previewTruncated. | (часть) | (сокращён) |
| selectAll | low | "Select all" in Russian UI is «Выделить всё» (everything); «все» reads as an incomplete "all [of them]". The pack writes ё elsewhere (ещё). | Выделить все | Выделить всё |
| framesBiggerTiles | low | Inverted word order reads as a comparison fragment; menu items put the noun first. | Крупнее плитки | Плитки крупнее |
| framesSmallerTiles | low | Same as framesBiggerTiles. | Мельче плитки | Плитки мельче |
| layersMerged | medium | Unnatural word order with the count dangling at the end after a colon; a native speaker would not phrase a status line this way. | Слоёв объединено в «{name}»: {count} | Слои ({count}) объединены в «{name}» |
| layersBiggerRows | low | Same word-order issue as framesBiggerTiles. | Крупнее строки | Строки крупнее |
| layersSmallerRows | low | Same as layersBiggerRows. | Мельче строки | Строки мельче |
| layersResetSub | low | Mixes a full adjective («Видимый») with a short participle («разблокирован»), and the bare «Обычный» does not say it is the blend mode. | Видимый, разблокирован, непрозрачность 255, «Обычный» | Видимые, незаблокированные, непрозрачность 255, наложение «Обычный» |
| blendDarken | medium | Russian image editors (Photoshop) call Darken «Замена тёмным», the pair of the glossary's Lighten «Замена светлым»; «Затемнение» breaks the pair and is also the group heading (blendGroupDarken), so the mode and its group read the same. | Затемнение | Замена тёмным |
| paletteImported | low | The bare name with a feminine participle leaves «импортирована» without a visible noun; name the palette. | «{name}» импортирована ({count} цвет) … | Палитра «{name}» импортирована ({count} цвет) … (all four branches) |
| paletteCreated | low | Same as paletteImported. | «{name}» создана ({count} цвет) … | Палитра «{name}» создана ({count} цвет) … (all four branches) |
| patternsHint | low | «с этим инструментом ({tool})» is a visible workaround for case; the tool name in quotes after «инструментом» stays in the nominative and reads naturally. | Коснитесь узора, чтобы использовать его с этим инструментом ({tool}). … | Коснитесь узора, чтобы использовать его с инструментом «{tool}». … (rest unchanged) |
| engineRefusedFallback | low | Same English as engineRefused, rendered differently («Это изменение отклонено» there); one message should match the other. | Редактор отклонил это изменение | Это изменение отклонено (or change engineRefused to match) |
| cmdLayerUp | low | Every other command name on the shortcuts page is an infinitive («Дублировать кадр», «Копировать выделение»); this one is a noun phrase. Equally short as an infinitive. | Слой выше | Поднять слой |
| cmdLayerDown | low | Same as cmdLayerUp. | Слой ниже | Опустить слой |
| timelapseSquare | low | The two choices of the same group use different parts of speech (noun «Квадрат» vs adjective «Вертикальный»); both should describe the video. | Квадрат | Квадратное (and timelapsePortrait: Вертикальное) |

## Systemic notes

1. **"Artwork" in editor contexts.** The glossary keeps «работа» for a published Club artwork and «рисунок» for a local drawing, but the pack renders the English word "artwork" as «работа» even where it means the local drawing: the whole Artwork colors page (`artworkColorsTitle` «Цвета работы», `paletteFromArtwork`, `acExtracting`, `acOverTitle`, `acEmptyTitle`, `acFailedTitle`, `acPendingNote`) and `loadOverBudget`. Readable, but it blurs the one distinction the glossary draws. I would use «рисунок» on that page («Цвета рисунка», «Из цветов рисунка», «В рисунке больше {max} цветов») and keep «работа» for Club messages such as `clubLoadFailed` and `clubSizeAlert`.
2. **Agreement with a noun that is not on screen.** Short notes, tags, and toasts often agree with a noun the reader has to guess: `toolNoteOn` is masculine beside the feminine «Калька», and the palette toasts put a feminine participle after a bare user-typed name. When a state word or participle stands alone, either name the noun («Палитра «{name}» создана») or check its gender against the tool or object it sits beside. This needs a check across all three packs for every `toolNote*` and status tag.
3. **Comparative menu items and parts of speech.** Size toggles put the comparative first («Крупнее плитки», «Мельче строки»). That reads as a fragment of a comparison; Russian menus put the noun first («Плитки крупнее»). The same pattern shows up in mixed parts of speech inside one group (`timelapseSquare`/`timelapsePortrait`, `cmdLayerUp` among infinitive commands, `fileNew` as an adjective where the glossary wants an infinitive). The glossary rule (tools are nouns, actions are infinitives) works where it is applied, and the remaining cases should follow it.
4. **Blend modes.** Align with Russian Photoshop throughout: Darken is «Замена тёмным», the pair of the glossary's «Замена светлым». The other ten names are correct.
5. Minor: the pack writes decimals with a dot (`framesScaleRange` «От 0.1 до 10»). Russian uses a decimal comma. Keep the dot only if the number field rejects a comma. If it accepts one, write «0,1».
