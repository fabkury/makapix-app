# Store listings

The text of the store listings, one file per store language. **Not live**: the stores show what
was last uploaded, and these files reach them only when someone uploads them (at the language
flip, `docs/i18n/PLAN.md`, L4).

## Google Play (`play/<code>.json`)

`title` (at most 30 characters), `shortDescription` (80), `fullDescription` (4,000). The
English source is the live Play listing as read on 2026-10-02, with two corrections: canvases
are up to 512×512 (not 256×256) and frames hold up to 128 layers (not 64). The translations
follow `docs/i18n/GLOSSARY.md`; Spanish is one text for both `es-419` and `es-ES`.

## App Store

Not drafted yet: its subtitle and keywords are only readable in App Store Connect, and its API
refused on 2026-10-02 until an updated agreement is accepted there (Business). The description
can reuse the Play full description.
