# Review: iOS permission prompts (InfoPlist.strings)

Files: `docs/i18n/flip/ios/<lang>.lproj/InfoPlist.strings` (es, pt-BR, fr, de, ru, ja, zh-Hans).
Syntax checked in all seven: each line is `"KEY" = "value";`, straight double quotes around the
value, no unescaped straight quote inside (French uses the typographic apostrophe ’), UTF-8.
Glossary terms (artwork, avatar) and address forms match GLOSSARY.md in every file. In these
prompts "artwork" is the Club artwork (the photo picker serves the avatar, Contribute, and the
detail page; the editor's Open/Import go through Files), so *Werk* / *работа* are the right
glossary words, not the editor's *Zeichnung* / *рисунок*.

| language | key | severity | problem | current | proposed |
|---|---|---|---|---|---|
| es | NSPhotoLibraryUsageDescription | low | "para que elijas … para tu avatar" stacks two *para* and drops the "can" of the source; Apple's Spanish prompts say "para que puedas …". | Makapix necesita acceso a tus fotos para que elijas una imagen para tu avatar o tu obra. | Makapix necesita acceso a tus fotos para que puedas elegir una imagen para tu avatar o tu obra. |
| fr | NSPhotoLibraryUsageDescription | low | Bare subjunctive "pour que vous choisissiez" reads stiff; "puissiez choisir" is the idiomatic form and keeps the source's "can". | Makapix a besoin d’accéder à vos photos pour que vous choisissiez une image pour votre avatar ou votre œuvre. | Makapix a besoin d’accéder à vos photos pour que vous puissiez choisir une image pour votre avatar ou votre œuvre. |
| fr | NSCameraUsageDescription | low | "a besoin de l’appareil photo" says the app needs the camera itself, not access to it, and differs from the library prompt's "a besoin d’accéder à"; iOS prompts phrase it as access. | Makapix a besoin de l’appareil photo si vous voulez prendre une photo pour votre avatar ou votre œuvre. | Makapix a besoin d’accéder à l’appareil photo si vous souhaitez prendre une photo pour votre avatar ou votre œuvre. |

## Verdict per language

- **es**: correct and natural (tú, *obra*, "u obra" right); one polish item.
- **pt-BR**: clean; natural Brazilian prompt with *você* and *arte*, no findings.
- **fr**: correct (vous, *œuvre*); two polish items to read like Apple's own prompts.
- **de**: clean; natural, du, *Werk*, no findings.
- **ru**: clean; вы lowercase, *работа*, natural phrasing, no findings.
- **ja**: clean; です／ます, space around Makapix, full-width punctuation, no findings.
- **zh-Hans**: clean; 你, half-width space after Makapix, full-width punctuation, no findings.
