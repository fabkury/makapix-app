# Second-pass translation review brief

A first independent review of this app's translation found problems, and the messages in your
pack were reworded in response. You check the rewrites. You have not seen the first review or
the reasoning behind any change; judge only what is on the page.

**Read first:** `C:\Users\fab\AppData\Local\Temp\claude\C--Users-fab-F-Estudo-Tecnologia-makapix-app\b5695ab8-9fe3-4186-a641-fa898a6f5031\scratchpad\review\BRIEF.md`
(the app, the language conventions, the severity scale) and
`C:\Users\fab\F\Estudo\Tecnologia\makapix-app\docs\i18n\GLOSSARY.md`, including its section
"Decided in the L3 review", which records the term decisions behind many of these rewrites.
Those decisions are the project's; report one only if it is wrong for a native speaker.

**Your pack:** a JSON-lines file in this folder. Fields: `key`, `context`, `en` (source),
`before` (the old translation), the new translation (field named by the language code),
optional `placeholders`.

**For every message, check the new text:**
1. Correct meaning in context, natural, right register, grammatical (agreement included).
2. Every placeholder present and untouched; plural branches complete and grammatical.
3. Punctuation conventions of the language.
4. Not worse than `before`, and no new problem introduced (a term now inconsistent with the
   glossary, a sentence that got longer than its slot allows per `context`).

**Report only problems.** A good rewrite needs no entry.

**Output:** create the file your prompt names under
`C:\Users\fab\F\Estudo\Tecnologia\makapix-app\docs\i18n\review\`: a heading, the table
`| key | severity | problem | current | proposed |`, and a final line
`Checked N messages.` (N = the number of lines in your pack). Write the file once at the end.

**Constraints:** edit no other file; run no flutter, dart, cargo, or git commands.

**Final reply:** the count of findings per severity, in one or two lines.
