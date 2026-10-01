# Russian translation review — part 3 of 3 (messages 1101–1645)

Independent native-level review of `ru-3.jsonl` against `docs/i18n/GLOSSARY.md`. Only real
problems are listed; a message without an entry was judged correct and natural.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| layerVisible | low | The two neighboring chips use different adjective forms (full «Видимый» next to short «Заблокирован»). | Видимый | Виден |
| layerMoveGroup | low | The tool is «Перемещение» (layerMoveGroupTip, placeReachHint), but its group is «Группа сдвига»; «сдвиг» is also the glossary word for Shift (move items one position), so the chip does not read as belonging to the Move tool. See Systemic notes. | Группа сдвига | Группа перемещения |
| layerMoveGroupTip | low | Verb has no subject and the instrumental «инструментом» reads heavy; a tooltip for one layer's chip is clearer in the singular. | Двигаются вместе инструментом «Перемещение» (когда ничего не выделено) | Слои группы двигаются вместе при работе «Перемещением» (когда ничего не выделено) |
| frameNewAfter | medium | Dangling preposition: «после» needs an object in Russian (unlike the adverb «выше» in layerNewAbove). | Новый кадр после | Новый кадр следом |
| toolNoteOn | medium | Gender: the note stands beside «Калька» (feminine), so «включён» disagrees. | включён | включена |
| toolNoteActive | low | Masculine short adjective beside tool names of any gender («Заливка … активен», «Калька … активен»). A gender-neutral word avoids the mismatch. | активен | используется |
| newDocName | low | The drawing's title is «название» elsewhere (layerUnnamed «(без названия)», titles of drawings); «Имя» is a person's or file's name. | Имя (необязательно) | Название (необязательно) |
| clubSizeAlert | medium | Number mismatch: plural «работы» is picked up by singular «её». | Makapix Club не принимает работы {width} × {height}, поэтому в таком размере её нельзя будет опубликовать в Club. | Makapix Club не принимает работы размером {width} × {height}, поэтому рисунок такого размера нельзя будет опубликовать в Club. |
| exportedFlattenedNote | medium | «Сведены» is the term for flattening layers; applied to pixels it does not say what happened (partial transparency was lost). | Полупрозрачные пиксели сведены. | Полупрозрачность пикселей не сохранена. |
| autosaveFailed | medium | «Автосохранить» without an object is not idiomatic, and «память устройства» reads as RAM; the English means storage space. | Не удалось автосохранить. Проверьте память устройства | Автосохранение не удалось. Проверьте свободное место на устройстве |
| shareCanceled | low | Share is «поделиться» everywhere else (menuShare, shareFailedShort); «Отправка» is a different word for the same action. | Отправка отменена | Вы отменили «Поделиться» → better: Публикация через «Поделиться» отменена; simplest: Отменено |
| cropResultOversize | low | «за холстом» twice in one sentence; importNativeNote says the same thing with «за пределами холста». | Часть за холстом {canvasWidth}×{canvasHeight} сохраняется за холстом. | Часть за пределами холста {canvasWidth}×{canvasHeight} сохраняется за холстом. |
| cropResultBeyond | low | «1:1: …» — two colons in a row; the sibling lines start with «Размещено 1:1». | 1:1: {width} × {height} px, больше области за холстом. Дальняя часть не импортируется. | Размещено 1:1: {width} × {height} px, больше области за холстом. Дальняя часть не импортируется. |
