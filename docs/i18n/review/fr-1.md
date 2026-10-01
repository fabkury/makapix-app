# French (fr) translation review: part 1 of 3 (messages 1–550)

Independent review of `fr` against the English source and `docs/i18n/GLOSSARY.md`. Only real
problems are listed; a message that is not in the table was judged correct and natural.

Severity: **high** = wrong or misleading meaning, broken placeholder or plural; **medium** =
unnatural, inconsistent term, wrong register, grammar error; **low** = polish.

Result: no **high** findings in this part. 3 medium, 12 low.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| settingsMentionsSummary | medium | Mixes two persons in one sentence ("vous mentionner" … "que je suis"), and "que je suis" also reads as the verb *être* ("the people that I am"). | `Qui peut vous mentionner : {policy, select, following{les personnes que je suis} nobody{personne} other{tout le monde}}` | `Qui peut vous mentionner : {policy, select, following{les personnes que vous suivez} nobody{personne} other{tout le monde}}` |
| commentsSignIn | low | A button, but in the imperative; the other sign-in buttons use the infinitive ("Se connecter", "Se connecter / Créer un compte"). | `Connectez-vous pour commenter` | `Se connecter pour commenter` |
| modTagsAddLabel | low | "tag" in a sheet that says "hashtag" everywhere else (title, errors, toasts). | `Ajouter un tag` | `Ajouter un hashtag` |
| playerManageSubtitle | low | "Enregistrer" is the app's word for Save; "enregistrer des appareils" is understandable but momentarily reads as "save devices". | `Enregistrer, renommer ou retirer des appareils` | `Associer, renommer ou retirer des appareils` (only if the register flow in the other parts uses the same verb; change both together) |
| createAccountIntro | low | "le vérifier" attaches to the nearest masculine noun, "mot de passe"; it is the email address that gets verified. | `…nous vous enverrons un code à 6 chiffres pour le vérifier.` | `…nous vous enverrons un code à 6 chiffres pour vérifier votre adresse.` |
| onboardingProfileTitle | low | "Ajoutez votre touche" is not idiomatic on its own; the set phrase is "touche personnelle". | `Ajoutez votre touche (facultatif)` | `Ajoutez une touche personnelle (facultatif)` |
| feedRecommended | low | Masculine plural, while the feed lists "œuvres" (feminine) and other labels agree with it ("Animée", "Masquée"). | `Recommandés` | `Recommandées` |
| feedRecent | low | Same agreement issue as feedRecommended (the feed of the newest artworks). `sortRecent` (hashtags) is correctly masculine and stays. | `Récents` | `Récentes` |
| accountCanPostPublicly | low | "publier publiquement" is a clumsy repetition. | `Peut publier publiquement` | `Publication publique autorisée` |
| homeOffline | medium | "Votre session enregistrée est affichée" is unnatural: a session is not something that is "displayed". The point is that the app is showing what it remembers while offline. | `Impossible de joindre Makapix Club. Votre session enregistrée est affichée.` | `Impossible de joindre Makapix Club. Vous restez connecté avec votre session enregistrée.` |
| notifTrust | low | "Vous avez reçu la Confiance" reads oddly: an abstract noun with an article does not come across as the name of a status. "pour diffusion publique" is stiff. | `Vous avez reçu la Confiance : vos publications sont désormais approuvées automatiquement pour diffusion publique` | `Vous avez obtenu le statut Confiance : vos publications sont désormais rendues publiques sans approbation préalable` |
| notifTrustBy | low | Same as notifTrust. | `{who} vous a accordé la Confiance : vos publications sont désormais approuvées automatiquement pour diffusion publique` | `{who} vous a accordé le statut Confiance : vos publications sont désormais rendues publiques sans approbation préalable` |
| contributeUploadTitle | medium | "Importer" is the editor's word for Import (glossary: open / import are distinct gestures), and here it names something else: uploading a file as a post. The rest of this part says "envoyer" / "Envois" for upload (`accountUploads`, `avatarUploadFailed`). | `Importer un fichier` | `Envoyer un fichier` |
| artworkTaggedByMod | low | The legend explains hashtags that a moderator added; "Tagué" has no clear subject (the artwork is feminine, the hashtags plural). The tooltip on the same hashtags says "Ajouté par les modérateurs". | `Tagué par un modérateur` | `Hashtags ajoutés par un modérateur` (or `Ajouté par un modérateur` if space is tight) |
| artworkMenuDemote | low | "Retirer de la mise en avant" is heavy and not quite grammatical (one is not removed "from the putting forward"). | `Retirer de la mise en avant…` | `Ne plus mettre en avant…` |

## Systemic notes

- **Upload has two words.** "Envois" / "envoyer" (account row, avatar errors) versus
  "Importer un fichier" (Contribute page). "Importer" should stay reserved for the editor's Import
  gesture, as the glossary asks; use "envoyer" / "envoi" for every upload to the Club, and add the
  term to the glossary.
- **Agreement with "œuvre".** The glossary makes an artwork feminine, and most labels follow
  ("Animée", "Masquée", "Aucune œuvre trouvée"), but the feed names "Recommandés" and "Récents"
  are masculine. Decide once: labels that describe artworks agree in the feminine.
- **Buttons: infinitive, with a few imperatives.** Buttons and menu items are infinitives almost
  everywhere ("Se connecter", "Créer un compte", "Modifier le profil"); headings and instructions
  are imperatives with "vous" ("Créez votre compte", "Saisissez votre code"). That split is good
  French app style. The exceptions are buttons written as imperatives: `commentsSignIn`, and
  `profileCreateFirst` ("Créez votre premier pixel art", acceptable because of "votre").
- **Person: "vous" throughout, one slip.** `settingsMentionsSummary` switches to "je" inside a
  "vous" sentence. If the mention-policy options appear elsewhere as standalone radio labels
  (other parts), keep them in the same person as this summary.
- **"Enregistrer" carries two meanings**: Save (forms, files) and Register (player devices). It is
  correct French in both, but in one app "Associer un lecteur" would remove the ambiguity. Check
  the player registration messages in the other parts before changing.
- **Tool names mix nouns and verbs**, and three tools have a short label that is a different word
  from the full name (Remplissage / Remplir, Sélectionner / Sélection, Redimensionner / Échelle).
  The English mixes too and the tile width forces it, so none is listed above; if the full names
  are ever revisited, "Remplir" and "Sélection" for both forms would be tidier.
- **Masculine as the default for the user** ("Vous serez déconnecté", "Vous êtes désormais
  modérateur", "Nouveau sur Makapix Club ?", "Abonné"). This is the usual choice in French apps
  and is consistent here; no change proposed, only noted as a decision.
- **Clean points**: no-break spaces before `:` `;` `!` `?` and inside « » are present everywhere;
  the ellipsis is always `…`; every placeholder and ICU branch is intact; plural `one` branches
  read correctly for 0 and 1; "remix" is kept invariable in the plural; glossary terms
  (publication, fil, pseudo, lecteur, calque, image, à la une, sélection, mettre en avant,
  masquer / réafficher, connexions associées) are used consistently.
