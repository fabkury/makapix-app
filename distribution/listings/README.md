# Store listings

The text of the store listings, one file per store language. **Not live**: the stores show what
was last uploaded, and these files reach them only when someone uploads them. User decision
2026-10-02: all eight go live together at the language flip (`docs/i18n/PLAN.md`, L4), the
corrected English included.

## Google Play (`play/<code>.json`)

`title` (at most 30 characters), `shortDescription` (80), `fullDescription` (4,000). The
English source is the live Play listing as read on 2026-10-02, with two corrections: canvases
are up to 512×512 (not 256×256) and frames hold up to 128 layers (not 64). The translations
follow `docs/i18n/GLOSSARY.md`; Spanish is one text for both `es-419` and `es-ES`.

## App Store (`appstore/<locale>.json`)

Only the App Store's own fields: `subtitle` (at most 30 characters), `promotionalText` (170,
editable without a new version), `keywords` (100, comma-separated, no spaces, never repeating
words of the name or subtitle). The rest is shared so each text has one source:

- **description** = the Play `fullDescription` of the language `_play` names (user decision
  2026-10-02: the App Store uses Play's description; it also fixes the App Store's own stale
  "64 layers" and "256×256");
- **What's New** = `distribution/whatsnew/whatsnew-<_play>`;
- **screenshots** = `docs/marketing/out/<lang>/appstore/` (iPhone 6.9") and `ipad/` (13").

Locales: en-US, es-MX, es-ES, pt-BR, fr-FR, de-DE, ru, ja, zh-Hans. es-MX and es-ES share the
text but not the keywords: Mexico's storefront also indexes the en-US keywords, Spain's does not.
Subtitle (user choice): "Pixel art studio & community"; Spanish and Portuguese say "editor"
where Portuguese grammar would not fit "estúdio" in 30 characters. Promotional text: evergreen
(user choice). Each language was reviewed independently on 2026-10-02 (store-copy and keyword
review); the findings are applied.
