# Russian translation review — pack 2 of 3 (messages 551–1100)

Independent native-level review of `ru-2.jsonl` against `docs/i18n/GLOSSARY.md`. Only real problems are listed.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| layersDownloading | medium | «Загрузка» is used in this pack for both download (here) and upload (`publishUploading`); the sibling messages say «скачать» for download and «отправка» for upload. Use the unambiguous word. | Загрузка файла со слоями… | Скачивание файла со слоями… |
| layersNotMkpx | medium | «не корректный» written apart reads as a contrast that never comes ("not a correct one, but…"); awkward. | Это не корректный файл .mkpx. | Некорректный файл .mkpx. |
| layersTooLarge | low | A dash is needed between subject and numeric predicate; with the first dash replaced by a colon the sentence stays readable. | Слишком большой — предел для файла со слоями {size} MiB. | Слишком большой: предел для файла со слоями — {size} MiB. |
| avatarFromPostTitle | medium | «Сделать фото» is the set phrase for "take a photo"; the title reads "Take a profile photo?". The body and button already use «использовать». | Сделать фото профиля? | Использовать как фото профиля? |
| publishScaleTo | low | The bare nominative «ближайший сосед» is a calque; the method is called «метод ближайшего соседа». | Масштабировать до {width}×{height} (ближайший сосед) | Масштабировать до {width}×{height} (метод ближайшего соседа) |
| publishReplaceNote | medium | «на месте» is a calque of "in place" and reads as "on the spot". The rest of the sentence already carries the meaning. | Обновляет существующую публикацию на месте — реакции, комментарии и статистика сохраняются. Сведения выше применяются только при публикации как новой. | Обновляет саму существующую публикацию — её реакции, комментарии и статистика сохраняются. Сведения выше применяются только при публикации как новой. |
| publishUploading | medium | «Загрузка…» for an upload, while the layers-file upload is «Отправка…» (`layersUploading`) and «Загрузка» also means download (`layersDownloading`). One word per direction. | Загрузка… | Отправка… |
| publishUploadFailed | low | Same upload/download ambiguity as `publishUploading`; align with «отправить» (`layersUploadFailed`). | Не удалось загрузить. Попробуйте ещё раз. | Не удалось отправить. Попробуйте ещё раз. |
| publishShareLayersBody | medium | «Вошедшие участники» is not idiomatic (a bare participle; "members who came in"). | Вошедшие участники смогут открыть эту работу в редакторе со всеми слоями и кадрами ({size} KiB). | Участники, вошедшие в аккаунт, смогут открыть эту работу в редакторе со всеми слоями и кадрами ({size} KiB). |
| publishAllowRemixesBody, editDetailsAllowRemixesBody | low | "Public" is dropped, and «в её происхождении» alone reads as "in its origin" rather than as the name of a page. | …публиковать ремиксы с указанием вашего авторства в её происхождении. | …публиковать ремиксы; ваше авторство будет указано в общедоступном происхождении работы. |
| rulesGateBody | medium | "Banned" is rendered «блокируются», but the glossary keeps ban (забанить) distinct from a user's block (заблокировать); the next line of the same screen uses «заблокировать» for the user's own block. | …а повторные нарушители блокируются. | …а повторные нарушители получают бан. |
| pendingApproved | low | Neuter «одобрено» after a quoted title; the thing approved is a публикация (feminine). | «{title}» одобрено. | Публикация «{title}» одобрена. |
| pmdClearSelection | low | The same screen says «Выбрано: {count}» and «Выбрать все», then «Снять выделение»: two roots for one action. | Снять выделение | Снять выбор |
| pmdNoLicenseShort | medium | Context asks for "very short" (English: 3 letters); 12 characters where a license code such as "CC BY" normally sits. | Без лицензии | Без лиц. |
| pmdRequestBody | low | «после готовности» is officialese and unclear about what becomes ready. | Ссылка действует 7 дней после готовности. | Готовая ссылка действует 7 дней. |
| pmdEmailMe | low | «по почте» can be read as postal mail. | Сообщить по почте, когда ссылка будет готова | Сообщить по эл. почте, когда ссылка будет готова |
| bdrExpired | low | Neuter «Истекло» has no referent (the row is a загрузка or ссылка); the idiom is «срок истёк». | Истекло | Срок истёк |
| reportWhy | medium | «Почему вы жалуетесь?» sounds like a reproach ("why are you complaining?"). | Почему вы жалуетесь? | В чём причина жалобы? |
| publishSizeNotAllowed | low | «128–256 по обеим сторонам» is hard to parse; say "from … to … on each side". | Такой размер не допускается. Используйте 128–256 по обеим сторонам или стандартный малый размер. | Такой размер не допускается. Используйте от 128 до 256 по каждой стороне или стандартный малый размер. |
