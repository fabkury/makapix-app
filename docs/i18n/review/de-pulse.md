# German (de) review: Pulse pack

Pack: `pulse-de.jsonl`, 15 messages, one batch. Terms checked against `GLOSSARY.md` and the
shipped `app_de.arb`. 12 messages need no change.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| pulseMore | low | "weitere" is the plural (or feminine) form, so with a count of 1 it disagrees with every noun the cards count ("+1 weitere" for ein Werk, ein Kommentar, ein Abzeichen, ein Remix). The message has no plural branch; "mehr" is invariable and just as short. | `+{count} weitere` | `+{count} mehr` |
| pulsePromoted | low | "ist jetzt" states a present condition, but the card is a dated entry in a timeline and may be days old (and the work may since have been removed from the feed). The English is a past event ("was added"), and the shipped toast `modPromotedToast` already says "Zu den Empfehlungen hinzugefügt". | `{count, plural, one{Ein Werk von <b>{who}</b> ist jetzt in den Empfehlungen} other{{count} Werke von <b>{who}</b> sind jetzt in den Empfehlungen}}` | `{count, plural, one{Ein Werk von <b>{who}</b> wurde zu den Empfehlungen hinzugefügt} other{{count} Werke von <b>{who}</b> wurden zu den Empfehlungen hinzugefügt}}` |
| pulseReputation | low | "Reputation gewinnen" with a bare object reads like winning a prize; the idiom for a growing standing is "an etwas gewinnen" (an Ansehen, an Reputation gewinnen). | `<b>{who}</b> hat Reputation gewonnen` | `<b>{who}</b> hat an Reputation gewonnen` |

## Systemic notes

- No high or medium findings. Placeholders, `<b>` tags, and both plural branches are intact in
  all seven plural messages; the `one` branches use the article ("ein Werk", "einen Remix"),
  matching the English.
- Terminology matches the glossary and the shipped file: Werk, Remix/Remixe, Kommentar,
  Abzeichen, Player, Reputation, veröffentlichen, "Empfehlungen" (the feed name,
  `feedRecommended`), "registrieren" (as in the `players*` messages), "hat auf … reagiert"
  (as in `notifReaction`), "Gesamt" (as in `playersTotal`).
- Tense: the card lines use the Perfekt ("hat … veröffentlicht"), the natural tense for a
  timeline of completed actions and the one the notifications use. `pulsePromoted` is the only
  line that steps out of it (present "ist jetzt"); see the table.
- "Puls" for the page name is a sound choice: short, native, and it carries the same image as
  the English. `pulseComingSoon` uses it without an article, as a name; lowercase "alles"
  after the colon is correct because what follows is not a full sentence.
- No "du"/"Sie" address occurs in this pack; nothing to check there.
