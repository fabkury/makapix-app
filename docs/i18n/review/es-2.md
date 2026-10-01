# Spanish review, part 2 of 3 (messages 551–1100)

Independent review of `es` against the English source and `docs/i18n/GLOSSARY.md`. Only real
problems are listed; a message that is absent from the table was read and found correct.

Totals: **high 0 · medium 4 · low 28**.

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| modDemoteBodyUnknown | low | "categoría destacada" reads as "outstanding category", not "the category it was promoted to". | Sale de su categoría destacada y vuelve a su posición normal en los feeds. | Sale de la categoría en la que estaba destacada y vuelve a su posición normal en los feeds. |
| pendingRejected | low | Word order: "solo" should sit next to what it restricts. | Rechazada: la publicación solo sigue visible en el perfil del artista. | Rechazada: la publicación sigue visible solo en el perfil del artista. |
| pmdNoLicenseShort | low | Fit: context asks for "very short" (English is 3 letters); 12 characters in a row that otherwise holds a license code such as "CC BY". | Sin licencia | Sin lic. |
| reportResolved | low | A colon after "Gracias" is not natural Spanish; the dash here is a pause, not an explanation. | Gracias: hemos revisado tu denuncia. | Gracias. Hemos revisado tu denuncia. |
| reportResolvedOn | low | Same "Gracias:" pattern. | Gracias: hemos revisado tu denuncia ({subject}). | Gracias. Hemos revisado tu denuncia ({subject}). |
| reportSendFailed | low | "Comprueba" is the Peninsular choice; "Revisa" is neutral across regions. | No se pudo enviar la denuncia. Comprueba tu conexión e inténtalo de nuevo. | No se pudo enviar la denuncia. Revisa tu conexión e inténtalo de nuevo. |
| reportSentBody | low | Same "Gracias:" pattern. | Gracias: un moderador la revisará. | Gracias. Un moderador la revisará. |
| monitoredIntro | low | The glossary term is "hashtag" (the page is "Hashtags supervisados"); here the same things are called "etiquetas". | Las publicaciones con estas etiquetas están ocultas de forma predeterminada. Marca una etiqueta para verla en los feeds, la búsqueda y las notificaciones. | Las publicaciones con estos hashtags están ocultas de forma predeterminada. Marca un hashtag para verlo en los feeds, la búsqueda y las notificaciones. |
| monitoredHidden | low | Feminine agrees with "etiqueta", but the badge sits next to a hashtag (masculine, glossary term). Follows from the row above. | Oculta | Oculto |
| umdHideProfileBody | low | "Ocultar de la navegación pública" is a calque of "hide from public browsing". | Ocultar el perfil de la navegación pública | Ocultar el perfil al público |
| umdRevealEmailBody | low | Repetition "registrada en el registro". | La consulta queda registrada en el registro de auditoría | La consulta queda anotada en el registro de auditoría |
| umdBanPermTitle | low | Title and its confirm button (umdBanPermAction, "Expulsar permanentemente") are the same phrase in English but differ here; umdBannedPermanently and the toast also use "permanentemente". | ¿Expulsar para siempre? | ¿Expulsar permanentemente? |
| umdRevealBody | low | Same repetition "registrada en el registro". | Úsalo solo para tareas de moderación. La consulta queda registrada en el registro de auditoría de moderación. | Úsalo solo para tareas de moderación. La consulta queda anotada en el registro de auditoría de moderación. |
| playersNameHint | low | Regionalism: "salón" for living room is Peninsular; "sala" is understood everywhere. | Pantalla del salón | Pantalla de la sala |
| errNetwork | low | "Comprueba" again (see reportSendFailed). | Error de red. Comprueba tu conexión. | Error de red. Revisa tu conexión. |
| mentionReasonFollowing | low | "Lo" assigns masculine gender to a user of unknown gender; the label works without the pronoun. | Lo sigues | Sigues |
| exportLargeWarning | low | No plural handling: if {millions} is ever 1 it reads "1 millones" (English "1 million pixels" stays correct). Safe only if the warning never fires at 1. | Exportación muy grande: {millions} millones de píxeles. … | Exportación muy grande: {millions} M de píxeles. … (or add an ICU plural) |
| shareLargeWarning | low | Same as exportLargeWarning. | Exportación muy grande: {millions} millones de píxeles. … | Same fix as exportLargeWarning. |
| tipAirbrush | low | "dejan pintura distinta" is a literal rendering of "lay different paint" and sounds odd. | Arrastra para rociar el color primario. Puntos, Suave y Niebla dejan pintura distinta. | Arrastra para rociar el color primario. Puntos, Suave y Niebla pintan de forma distinta. |
| tipOutline | medium | The context requires option names to match the option labels. Other tips keep them capitalized as names (Umbral, Diagonal, Puntos, Suave, Niebla); here "esquinas" and "grosor" are lowercased and read as common nouns, not as the options Esquinas and Grosor. | Aplicar dibuja un anillo alrededor de los píxeles de la capa con el color primario. Lado, esquinas y grosor le dan forma. | Aplicar dibuja un anillo alrededor de los píxeles de la capa con el color primario. Lado, Esquinas y Grosor le dan forma. |
| tipSelectShape | low | "Reticles" becomes the vague "marcas"; the user cannot tell which on-screen element is meant. Use the word the precision-mode messages use for the reticle (most naturally "retícula"). | Rect. / Óvalo: arrastra para esbozar una selección y ajusta las marcas. Lazo: dibuja libremente alrededor de los píxeles. | Rect. / Óvalo: arrastra para esbozar una selección y ajusta las retículas. Lazo: dibuja libremente alrededor de los píxeles. |
| tipRotate | low | "Angle" names the Ángulo button (optAngle); lowercased it reads as a common noun. | Rota la capa o el fotograma 90°, 180° o un ángulo libre. (Lienzo completo: menú ☰.) | Rota la capa o el fotograma 90°, 180° o con Ángulo libre. (Lienzo completo: menú ☰.) |
| tipResize | low | Same: "Scale" names the Escala button (optScale, whose context says this tip calls it by that name). | Escala la capa o el fotograma: ½×, 2× o una escala libre arrastrando. (Lienzo completo: menú ☰.) | Escala la capa o el fotograma: ½×, 2× o arrastra con Escala libre. (Lienzo completo: menú ☰.) |
| optRound | low | Agreement: shown after the label "Forma" (feminine) and also used for corners (esquinas); the masculine adjective agrees with neither. "Cuadrado" passes as a noun, "Redondo" does not. | Redondo | Redonda (and Cuadrada for optSquare), or the nouns Círculo / Cuadrado |
| optDiagonalTip | low | "8-connected" is connectivity, not "8 connections". | Vecinos en diagonal: la zona puede cruzar esquinas (8 conexiones) | Vecinos en diagonal: la zona puede cruzar esquinas (conectividad 8) |
| optLevelsLow | low | Spanish abbreviations take a period, and the pack does so elsewhere ("máx. {max}", "Rect.", glossary rule for abbreviations). | Mín | Mín. |
| optLevelsHigh | low | Same. | Máx | Máx. |
| colorSetAsPrimary | low | Opposite of colorUsePrimary ("Usar el color primario") but nearly the same wording; the two are easy to confuse in a menu. | Usar como primario | Definir como primario |
| mirrorChipTip | low | "Off" is rendered "No" here but "Desactivado" in the mode list this cycle refers to (mirrorModeOff); "No" is not a state name. | Dibujo en espejo: toca para alternar No · H · V · Ambos; mantén pulsado para el eje | Dibujo en espejo: toca para alternar Desactivado · H · V · Ambos; mantén pulsado para el eje |
| mirrorAxisX | medium | Decimal comma. Every other number in the app is shown with a point ("Ratio 1.00", "1.5 s"), many Spanish-speaking countries use the point, and a user who types ",5" as told may be rejected if the field parses a point. | Eje vertical en x (0 – {max}; ,5 = entre columnas) | Eje vertical en x (0 – {max}; .5 = entre columnas) |
| mirrorAxisY | medium | Same decimal comma. | Eje horizontal en y (0 – {max}; ,5 = entre filas) | Eje horizontal en y (0 – {max}; .5 = entre filas) |
| patternSwatchTipOn | medium | "Mosaico" means a mosaic or tiling, not one tile; it suggests the repeating pattern itself rather than the swatch button. The next message (patternPickFirst) calls the same element "la muestra". | {label}: {name} · toca el mosaico para cambiarlo, el borde verde para desactivarlo | {label}: {name} · toca la muestra para cambiarlo, el borde verde para desactivarlo |

## Systemic notes

1. **Option names inside help tips.** The `tip*` messages are told to name options by their labels.
   Most do (Umbral, Diagonal, Puntos / Suave / Niebla, Rect. / Óvalo / Lazo, Lento), but tipOutline,
   tipRotate, and tipResize lowercase them (esquinas, grosor, ángulo, escala), so they stop reading
   as on-screen names. Capitalize option names in every tip.
2. **Peninsular lean.** The text is correct and natural but leans to Spain where a pan-regional
   word exists: "Comprueba tu conexión" (Revisa), "salón" (sala), "caducar / ha caducado" for
   sessions, codes, and links (understood everywhere, though "vencer" or "expirar" is more neutral;
   not listed per message), and the decimal comma in the mirror-axis labels. "Introduce" (enter a
   code) is acceptable. Decide once whether "caducar" stays; if it does, keep it everywhere as now.
3. **Em dash handling.** English dashes are consistently turned into a colon, a semicolon, or a
   period, which is right. The one misfire is "Gracias: …" (three messages): after a thank-you the
   dash is a pause, so use a period.
4. **"Promote" = "destacar" next to "featured" = "destacados".** Both are glossary decisions, and
   in this pack they are applied consistently. The friction is that a promoted post goes to the
   feed "Recomendados" while the demote texts say "quitar de destacados", which suggests a list
   called "Destacados" (the welcome page's featured set). No message is wrong; if it ever
   confuses moderators, "quitar de Recomendados" in the demote dialog would be clearer when the
   category is that feed.
5. **Hashtag vs. etiqueta.** Where English says "tag", the Spanish says "etiqueta"
   (editDetailsModTags, monitoredIntro, and the feminine badge monitoredHidden), while the glossary
   term and the page titles say "hashtag". One word is better; "hashtag" is the glossary's.
6. **Replace** is "sustituir" in the Club (publishReplace, layersReplaced) and both "reemplazar"
   and "sustituir" in the editor (optReplace, paletteReplaceInArtwork vs. paletteOverwriteBody).
   Both are correct; picking one would be tidier.
7. **Fijar** renders Pin (ruler), Lock (resize), and Lock Ratio. They never share a row, so it is
   not a defect, but "Bloquear" for the two locks would keep Pin distinct.
8. Checked and found consistent: informal "tú" throughout, «…» quotation marks everywhere, the
   single-character ellipsis, opening ¿ and ¡, every placeholder present, all plural branches
   present and grammatical, gender agreement with "publicación" / "obra" / "descarga" in toasts
   and chips, and the glossary terms (obra, publicación, denunciar / denuncia, expulsar /
   readmitir, reproductor, archivo con capas, linaje, fotograma, lienzo, boceto, tramado,
   degradado, umbral, espejo).
