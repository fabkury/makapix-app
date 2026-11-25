# Spanish (es) review: Pulse pack

Pack: `pulse-es.jsonl`, 15 messages, one batch. Checked against `GLOSSARY.md` and the shipped
`app_es.arb` / `app_en.arb`.

| key | severity | problem | current | proposed |
|---|---|---|---|---|

No findings: all 15 messages are correct, natural, and consistent with the glossary and the
shipped strings.

## Systemic notes

- **No changes proposed.** Meaning, register (neutral international Spanish), ICU plural
  branches, placeholders, and the `<b>{who}</b>` tags are intact in every message.
- **Terms match the shipped app.** obra, publicar, remix / remixes (`artworkRemixCount`),
  comentario, reproductor + registrar (`playersRegisterA`), insignia, reputación, and
  "se añadió a Recomendados" (identical wording to `notifPromoted`, `modPromotedToast`).
  The filter chip "Todo" matches `optAll`.
- **No gender agreement with {who}.** Every card line uses a simple-past verb (reaccionó,
  publicó, escribió, registró, recibió, ganó) or makes the artwork the subject
  (`pulsePromoted`), so nothing depends on the member's gender.
- **"Pulso" as the page name** is a natural one-word title. `modHubNote` already uses
  lowercase "pulso" for the website Moderator Dashboard's pulse section, a different thing
  from this page; the English source has the same overlap ("pulse" / "Pulse"), so it is not
  a translation defect, only something to know.
- **Considered and not flagged (taste only):** "recibió una insignia" for "earned a badge"
  (the context says "was awarded", so it fits); "Pulso llega pronto" (present for a near
  future is idiomatic; "Próximamente" would lose the page name).
