# French (fr) review: Pulse pack

Pack: `pulse-fr.jsonl`, 15 messages, one batch. Checked against `GLOSSARY.md` and the shipped
`app_fr.arb`. Messages not listed have no problem.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| pulsePromoted | medium | "a rejoint Recommandés" has no article: a feed name used as a bare noun reads as broken French. The shipped messages write "Elle rejoint le fil Recommandés" (`modPromoteBody`) and "Ajoutée aux Recommandés" (`modPromotedToast`); this line should match them. | `{count, plural, one{Une œuvre de <b>{who}</b> a rejoint Recommandés} other{{count} œuvres de <b>{who}</b> ont rejoint Recommandés}}` | `{count, plural, one{Une œuvre de <b>{who}</b> a rejoint les Recommandés} other{{count} œuvres de <b>{who}</b> ont rejoint les Recommandés}}` |
| pulsePromoted | low | "de {who}" cannot elide: a handle that starts with a vowel gives "Une œuvre de alice" instead of "d'alice". This is the only "de + handle" construction in `app_fr.arb`. Tolerable with a bold handle, but a wording with the handle as subject avoids it and matches the other cards, which all start with the handle. | `Une œuvre de <b>{who}</b> a rejoint Recommandés` | Optional: `{count, plural, one{<b>{who}</b> a une œuvre parmi les Recommandés} other{<b>{who}</b> a {count} œuvres parmi les Recommandés}}` |
| pulseTitle | low | "Pouls" is first of all the medical word (the heartbeat felt at the wrist); alone on a button tooltip, without "de la communauté", it is less transparent than the English "Pulse". It is understandable and the metaphor exists ("prendre le pouls de…"), so this is a naming choice for the project, not an error. | `Pouls` | Keep, or `Activité` if a self-explanatory label is preferred (then `pulseComingSoon` becomes "Activité arrive bientôt : tout ce que fait la communauté, au même endroit.") |

## Systemic notes

- **Recommended feed in running text.** Inside a sentence the feed name takes an article:
  "les Recommandés", "aux Recommandés", or "le fil Recommandés", as the shipped moderation
  messages do. Bare "Recommandés" is right only as a tab or chip label.
- **Handle after "de".** French cannot elide before a placeholder. Prefer sentences where the
  handle is the subject (as the other nine Pulse lines are); the app had no "de {who}" before
  this pack.
- **Everything else is consistent with the shipped file and the glossary**: œuvre, publier,
  remix (invariable in the plural), commentaire, lecteur + enregistrer, badge, réputation;
  passé composé in every card line, parallel to `notifReaction` ("{who} a réagi…"); the
  no-break space before ":" is present in `pulseReputationTotal` and `pulseComingSoon`; all
  placeholders, `<b></b>` tags, and both plural branches are intact, and the `one` branches read
  correctly for 0 and 1. The filter chips ("Tout", "Lecteurs", "Réputation") are short and
  fit.
