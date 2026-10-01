# Translation review brief

You are an independent, native-level reviewer of one language of an app's translation. You
have not seen how the translation was made; judge only what is on the page.

**The app.** Makapix Club: a pixel-art social network (feeds, posts, comments, profiles,
moderation, "players" = physical display devices that show artworks) with a built-in animated
pixel-art editor, the Makapix Editor (drawing tools, layers, frames, palettes, replay and
timelapse).

**Inputs.** Your prompt names one pack: a JSON-lines file in this folder, about 550 messages.
Fields: `n`, `key`, `context` (a note for translators: where the text appears and what it must
fit), `en` (the English source), the translation under review (field named by its language
code), optional `placeholders`. ICU syntax: `{name}` placeholders and
`{count, plural, one{…} other{…}}`. Also read
`C:\Users\fab\F\Estudo\Tecnologia\makapix-app\docs\i18n\GLOSSARY.md` first: the project's
style and terminology rules. The glossary is the project's decision on terms: report a glossary
term itself only if it is wrong or would mislead a native speaker. You may grep the other two
packs of your language (same folder, `<lang>-1/2/3.jsonl`) to check a term's consistency.

**Check each message for:**
1. Meaning: does it say what the English says, in that context?
2. Naturalness: would a native speaker write it this way in an app?
3. Register and conventions of the language (below).
4. Terminology: glossary terms used consistently; the same English term rendered the same way
   across messages unless the context differs.
5. Grammar, agreement (also with placeholders and counts), spelling, typos.
6. ICU: plural branches present and grammatical; every placeholder present and untouched.
7. Punctuation conventions of the language; the ellipsis is the single character `…`.
8. Fit: when `context` says short, one word, or narrow, flag a translation that is clearly much
   longer than the English.

**Language conventions.**
- **pt (Brazilian Portuguese):** "você"; Brazilian vocabulary and spelling, not European.
- **fr:** "vous"; infinitives or imperatives used consistently for actions; a no-break space
  (U+00A0) before `:` `;` `!` `?` and inside « » (in the pack it looks like a normal space;
  flag only a missing space). In French the `one` plural branch also covers 0.
- **de:** informal "du" throughout, never "Sie"; nouns capitalized; the short native word over a
  long compound when both exist; „…" quotation marks; a space before `…` when it replaces
  whole words.
- **ru:** polite "вы" in lowercase; tool names are nouns, button and menu actions infinitives;
  «…» quotes; all four plural branches (`one`, `few`, `many`, `other`) grammatical for their
  numbers (1 кадр, 2 кадра, 5 кадров; `other` serves fractions).
- **ja:** です／ます, no pronouns; no space between Japanese and Latin letters or digits;
  full-width punctuation; natural UI Japanese (as in major Japanese apps), not translationese.
  Plural messages have only `other`.
- **zh (Simplified Chinese):** 你; a half-width space between Chinese and Latin letters or
  digits; full-width punctuation; natural mainland UI Chinese. Plural messages have only
  `other`.

**Report only real problems.** Do not rewrite for taste: a correct, natural translation needs
no entry. Do not flag brand names or technical tokens the glossary keeps untranslated, or
letters and abbreviations the context says are deliberate.

**Output.** Create the file your prompt names under
`C:\Users\fab\F\Estudo\Tecnologia\makapix-app\docs\i18n\review\`: a heading, then a table
`| key | severity | problem | current | proposed |`. Severity: **high** = wrong or misleading
meaning, broken placeholder or plural, offensive; **medium** = unnatural or awkward,
inconsistent term, wrong register, grammar error; **low** = polish. Work through the pack in
order, in batches of about 100 messages, and append each batch's findings to the file as you
go, so nothing is lost if you are interrupted. End the file with a section headed exactly
`## Systemic notes`: patterns that recur, and terms you would change everywhere, with the
reason. That heading marks the review as complete.

**Constraints.** Do not edit any other file. Do not run flutter, dart, cargo, or git commands
(a test run is using the toolchain).

**Final reply:** the count of findings per severity and the three most important systemic
notes, in a few lines.
