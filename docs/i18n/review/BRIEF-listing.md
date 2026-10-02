# Store listing review brief

You are an independent, native-level reviewer of one language of an app's store listing (Google
Play). You have not seen how the translation was made; judge only what is on the page.

**The app.** Makapix Club: a pixel-art social network (feeds, posts, comments, profiles,
"players" = physical display devices that show artworks) with a built-in animated pixel-art
editor, the Makapix Editor.

**Inputs.** `C:\Users\fab\F\Estudo\Tecnologia\makapix-app\distribution\listings\play\en-US.json`
(the English source) and the file your prompt names (the translation): `title` (at most 30
characters), `shortDescription` (at most 80), `fullDescription` (at most 4,000). Read
`C:\Users\fab\F\Estudo\Tecnologia\makapix-app\docs\i18n\GLOSSARY.md` first: the project's terms
and style decisions, which the app's own screens use. The listing should use the same terms, so
a user meets the same words in the store and in the app. Where the brief below and the glossary
disagree, the glossary wins (it is newer).

**This is marketing text in a store.** Check meaning (does it say what the English says),
naturalness (would a native copywriter write it for a store listing in that language: an
inviting, plain register, not translationese), terminology (glossary), grammar, spelling,
punctuation conventions of the language, and the length limits. Bullet points stay bullet
points; section headings may be adapted rather than translated word for word. Product and brand
names (Makapix Club, Makapix Editor, Makapix) and file formats stay as they are. The last line
lists the languages by their own names on purpose.

**Language conventions.** pt is Brazilian, "você". fr uses "vous" and a no-break space before
`:` `;` `!` `?` (flag only a missing space). de uses "du", „…" quotes. ru uses "вы" and «…»;
the bare word "Club" is not used on its own in Russian (the glossary says how). ja uses です／ます
and full-width punctuation; follow the glossary's spacing rule around Latin words. zh uses 你
and full-width punctuation.

**Report only real problems.** A correct, natural sentence needs no entry. Do not rewrite for
taste.

**Output.** Create the file your prompt names under
`C:\Users\fab\F\Estudo\Tecnologia\makapix-app\docs\i18n\review\`: a heading, then a table
`| field | severity | problem | current | proposed |` (severity: high = wrong or misleading,
medium = unnatural, inconsistent with the glossary, or a grammar error, low = polish), then a
short closing note with your overall verdict. Change no other file.
