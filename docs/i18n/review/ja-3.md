# Japanese (ja) review, pack 3 (messages 1101–1645)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| toolNoteLastVisible | medium | 「最後の表示ツール」 is not natural Japanese; it reads like a tool named "last display". The note means this is the only tool still shown. | 最後の表示ツール | 最後の1つ |
| selectInvert | medium | Collides with `optFlipSelection` (pack 2), which is also 「選択範囲を反転」 but means mirroring the selected pixels. Here the wording is the standard Photoshop/CLIP STUDIO term for Select > Inverse and should stay; the Flip option is the one to reword (see systemic notes). | 選択範囲を反転 | 選択範囲を反転 (keep; reword optFlipSelection) |
| openOverMax | low | 「切り抜きしてください」 is clumsy; the verb form reads better. | 「画像をインポート…」で縮小または切り抜きしてください。 | 「画像をインポート…」で縮小または切り抜いてください。 |
| cropCanvasTitle | low | The page title drops 「キャンバス」 and so matches the import crop page title (`importCrop`) word for word, unlike the menu item that opens it and the sibling title `resizeCanvasTitle`. | 切り抜き | キャンバスを切り抜き |
| previewFrameOf | low | Spacing differs from the other frame counters (`frameOfCount`, `layerOfCount` use 「{index}/{total}」 with no spaces). | フレーム {current} / {total} | フレーム {current}/{total} |
| cropResultBeyond | low | 「遠い部分」 ("the far part") is a literal rendering and unclear; it is the part beyond the off-canvas area. | 1:1 で配置：{width} × {height} px。キャンバス外領域より大きいため、遠い部分はインポート時に破棄されます。 | 1:1 で配置：{width} × {height} px。キャンバス外領域より大きいため、はみ出した部分はインポート時に破棄されます。 |
| cropResultOversize | medium | 「キャンバス外の部分はキャンバス外に保持」 is circular and awkward; `importNativeNote` already has the natural wording 「キャンバスからはみ出した部分」. | 1:1 で配置：{width} × {height} px。{canvasWidth}×{canvasHeight} のキャンバス外の部分はキャンバス外に保持されます。 | 1:1 で配置：{width} × {height} px。{canvasWidth}×{canvasHeight} のキャンバスからはみ出した部分はキャンバス外に保持されます。 |
| placeDroppedStorage | low | 「破棄：」 alone drops "beyond storage", and `placeDroppedCanvas` is now identical, so the two cases read the same. | 破棄：{edges} | 保持領域外を破棄：{edges} |
| placeDroppedCanvas | low | Same as above; says nothing about the canvas. | 破棄：{edges} | キャンバス外を破棄：{edges} |
| framesShiftHint | low | Uses 「コマ」 for a frame position while every other frame string, including the sibling `framesEveryNthMenu`, says 「フレーム」 (glossary: frame = フレーム). | ずらすコマ数。負の数は前へずらします。 | ずらすフレーム数。負の数で前へずらします。 |
| framesShiftByN | low | Same 「コマ」 term mix, and a space before Japanese text that `framesEveryNthMenu` 「Nフレームごと…」 does not have. | N コマずらす… | Nフレームずらす… |
| framesScaleTitle | medium | 「表示時間を倍率変更」 treats 倍率変更 as a verb taking を, which is ungrammatical. | 表示時間を倍率変更 | 表示時間の倍率を変更 |
| paletteExportGpl | medium | Export is 「エクスポート」 everywhere else in the editor (glossary; `ioExportFrame`, `exportedFormat`…). 「書き出す」 makes this one look like a different action. | .gpl で書き出す | .gpl をエクスポート |
| paletteImport | medium | Import is 「インポート」 (glossary), and 「読み込む」 already means "load" on this same page (`palettesHint`: tap a palette to load it), so import and load become the same word. | パレットを読み込む（.gpl/.json） | パレットをインポート（.gpl/.json） |
| paletteImported | medium | Same: the toast should use the Import verb. | {count, plural, other{「{name}」を読み込みました（{count}色）}} | {count, plural, other{「{name}」をインポートしました（{count}色）}} |
| acOverBody | low | "Imported photos" uses 「読み込んだ」 instead of the glossary Import verb. | …グラデーションや読み込んだ写真が原因のことが多いです。 | …グラデーションやインポートした写真が原因のことが多いです。 |
| patInverse | low | 「反転」 is the Flip word in this app (glossary: Flip = 反転, Invert = 色反転), so 「（反転）」 suggests a mirrored pattern. The pattern actually has its ON and OFF cells swapped. | {name}（反転） | {name}（オン/オフ反転） |
| ditherHintRowsHalf | low | Japanese writes 「50%」 with no space. | 50 % で1行おき | 50%で1行おき |
| ditherHintColsHalf | low | Same as above. | 50 % で1列おき | 50%で1列おき |
| ditherHintRows | low | A full sentence joined to a fragment with 「、」 reads awkwardly in a one-line note. | 行が埋まっていきます、{count} 段階 | 行が順に埋まる（{count}段階） |
| ditherHintCols | low | Same as above. | 列が埋まっていきます、{count} 段階 | 列が順に埋まる（{count}段階） |
| memBlocked | medium | 「ブロックしました」 is translationese, and in this app ブロック is the glossary word for blocking a user. | ブロックしました：この変更を行うとメモリの上限を超えます。続けるには、フレーム、レイヤー、またはキャンバスサイズを減らしてください。 | この変更はできません：メモリの上限を超えます。続けるには、フレーム、レイヤー、またはキャンバスサイズを減らしてください。 |
| cmdMirrorCycle | low | Drops the list of modes the key cycles through. There is room for them on a 290 px line. | ミラー：次のモード | ミラー切替（オフ・左右・上下・両方） |
| kbPickColor | low | 「色を拾う」 is colloquial, and the tool itself is 「スポイト」. | 色を拾う | スポイト |
| replayOlderChip | medium | 「旧い」 is a non-standard reading (表外読み) that looks odd in UI text. Natural Japanese is 「古い」 or 「旧バージョン」. | 旧い記録 | 旧バージョンの記録 |
| timelapseExport | medium | Export is 「エクスポート」 everywhere else in the editor (glossary). | タイムラプスを書き出す | タイムラプスをエクスポート |
| timelapseFailed | medium | Same term inconsistency. | タイムラプスを書き出せませんでした：{error} | タイムラプスをエクスポートできませんでした：{error} |
| timelapseExported | medium | Same term inconsistency. | タイムラプスを書き出しました | タイムラプスをエクスポートしました |

## Systemic notes

1. **Spaces between Japanese and Latin text or digits.** The glossary says "no space between
   Japanese and Latin or digits", but this pack (like packs 1 and 2) puts a space there almost
   everywhere: 「Club へ移動」, 「Makapix Club は」, 「.mkpx を保存」, 「1:1 で配置」, 「左へ 1 px」,
   「約 {size} MB」, 「1024 フレーム」, 「フレームは 1 から」. Spacing around placeholders is
   inconsistent too: 「{count}フレーム」 and 「{count}色」 have no space, while 「{count} 段階」,
   「{count} 個」, 「{count} 件」, 「{count} ずらします」, 「フレーム {number}」 and 「{name} を開きました」 do.
   About 35 messages in this pack break the rule as written. The project should pick one rule. Either
   enforce the glossary rule, perhaps with a scanner (the space can stay before units written in Latin
   letters, such as px and MB, if wanted), or change the glossary to the "space around Latin words"
   style many Japanese apps use. Right now the app follows neither consistently.
   Affected keys in this pack: menuGoToClub, clubSizeOk, clubSizeNearest, clubSizeAlert,
   fileSaveTitle, loadNewerVersion, loadNotMkpx, openNotSupported, importNativeNote,
   importSameSize, importPlaced, importTooLarge, nudgeLeft/Up/Down/Right, fieldCanvasPixels,
   cropResultBeyond/Oversize/Native, placeSummary, placeMemoryFrames/Over/Of, batchUndoHolds,
   framesDeleteAgain, framesErrStart, framesShiftByN, framesSetDurationSub, layersDeleteAgain,
   layersResetSub, layersErrStart, layersRenameHelper, paletteExportGpl, replaceColorToleranceHelp,
   plus the placeholder cases above.
2. **Export and Import use two vocabularies.** The glossary sets エクスポート and インポート, and the
   File menu follows it, but the palette and timelapse strings switch to 書き出す and 読み込む. On the
   Palettes page, 読み込む also already means "load a palette", so Import and Load merge into one word.
   Use エクスポート and インポート everywhere and keep 読み込む for load only.
3. **反転 is overloaded.** The glossary makes 反転 mean Flip (geometry) and 色反転 mean Invert
   (colors). Japanese image editors, though, use 「選択範囲を反転」 for Select > Inverse (`selectInvert`,
   which is correct), and the Flip tool's `optFlipSelection` (pack 2) uses exactly the same string to
   mean mirroring the selected pixels. `patInverse` uses 反転 for a third meaning, swapping ON and OFF
   cells. Keep 「選択範囲を反転」 for Select > Inverse. Reword the Flip option so it cannot be confused
   with it, for example 「選択範囲を左右/上下反転」 or 「選択部分を反転（鏡像）」.
4. **Plural messages with the ICU wrapper removed.** Some plural messages lost the
   `{count, plural, other{…}}` wrapper and are plain strings (`editorDocInfo`, `toolsHiddenCount`,
   `openedFrames`, `importedFrames`, `exportedAnimation`, `placeMemoryFrames`), while most keep
   `other{…}`. The plain strings work with gen-l10n, but the two styles are inconsistent. Prefer the
   wrapped `other{…}` form so the files read uniformly.
5. **Minor native-feel issues** recur in short notes that splice a full sentence and a fragment
   with 「、」 (the dither hints), and in literal renderings of English spatial words (「遠い部分」,
   「キャンバス外の部分はキャンバス外に保持」). The other notes avoid both, and the natural wording
   already exists elsewhere in the pack (「キャンバスからはみ出した部分」).
