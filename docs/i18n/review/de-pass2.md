# German (de): second-pass review of the reworded messages

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| clubSizeAlert | high | The rewrite drops the whole second line, so `{nearestWidth}` and `{nearestHeight}` are missing and the user no longer learns the nearest size the Club accepts. | Makapix Club nimmt keine Werke im Format {width} × {height} an, daher kann diese Zeichnung in dieser Größe nicht im Club veröffentlicht werden. | Makapix Club nimmt keine Werke im Format {width} × {height} an, daher kann diese Zeichnung in dieser Größe nicht im Club veröffentlicht werden.\nNächste akzeptierte Größe: {nearestWidth} × {nearestHeight}. |
| importNativeNote | medium | "Placed 1:1" was dropped. That is the note's first piece of information (the image keeps its own size), and `before` had it. | Was über die {width}×{height}-Leinwand hinausragt, bleibt außerhalb der Leinwand erhalten. | 1:1 platziert. Was über die {width}×{height}-Leinwand hinausragt, bleibt außerhalb der Leinwand erhalten. |
| pmdNoLicenseShort | low | A bare "Keine" where a license name would be does not say what is missing, so it reads as a cut-off word. `before` ("Keine Lizenz") was clear. If the slot really cannot fit two words, the © sign says "all rights reserved" without words. | Keine | Keine Lizenz (or ©) |
| placeMemoryOf | low | "der {free} MB freien Speichers" is a stilted genitive of measure. The plain dative reads naturally. | Braucht bis zu ~{size} MB der {free} MB freien Speichers. | Braucht bis zu ~{size} MB von {free} MB freiem Speicher. |

Checked 78 messages.
