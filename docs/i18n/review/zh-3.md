# Translation review: Simplified Chinese (zh), pack 3 (messages 1101–1645)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| engineRefused | low | Drops "the engine"; the passive gives no agent, and the same English is rendered differently in `engineRefusedFallback` (编辑器拒绝了此更改). Use one wording for both. | 此更改被拒绝 | 编辑器引擎拒绝了此更改 |
| openTooLarge | low | "超出此设备的能力" is a slightly unnatural collocation; 处理能力 is the usual phrase. | 无法打开 {name}：帧数或像素过多，超出此设备的能力。 | 无法打开 {name}：帧数或像素过多，超出此设备的处理能力。 |
| outgoingOpenNew | low | "打开一幅新画作" reads as opening an existing picture; for a new empty drawing the UI verb is 新建 (as in `galleryNew` 新建画作). | 打开一幅新画作？ | 新建画作？ |
| outgoingKeep | low | Locative phrase is missing 中 (compare `discardDrawingBody` 保留在“我的画作”中). | 保留在“我的画作” | 保留在“我的画作”中 |
| placeSummary | low | Telegraphic and drops "Import"; the canvas size is tacked on after a comma, so the sentence does not say the position is on that canvas. | {width} × {height} px 放在 ({x}, {y})，画布 {canvasWidth}×{canvasHeight}。背景：第 {frame} 帧。 | 导入 {width} × {height} px，放在 {canvasWidth}×{canvasHeight} 画布的 ({x}, {y})。背景：第 {frame} 帧。 |
| placeDroppedStorage | low | Same text as `placeDroppedCanvas`; the reason (beyond the storage area vs beyond the canvas) is lost, and the two warnings exist to tell them apart. | 将被丢弃：{edges}。 | 超出存储区域，将被丢弃：{edges}。 |
| placeDroppedCanvas | low | See `placeDroppedStorage`: the reason is lost. | 将被丢弃：{edges}。 | 超出画布，将被丢弃：{edges}。 |
| placeReachHint | low | 访问 (access, as in a website) is odd for reaching pixels on a canvas; 查看/编辑 or 移回 says it. Same in `batchNotSquare`. | 可用移动工具和“画布外区域”视图访问。 | 可用移动工具或“画布外区域”视图查看。 |
| batchNotSquare | low | Same 访问 as `placeReachHint`. | …（可用移动工具访问） | …（可用移动工具移回） |
| batchAddToSelection | low | 添加到所选 leaves 所选 dangling as a noun; 所选项 / 当前选择 is the natural noun. Same in `layersSelectAdds` and `layersSelectReplaces`. | 添加到所选 | 添加到所选项 |
| framesEveryNthMenu | medium | 每隔 N 帧 is ambiguous in Chinese: 每隔 2 帧 is commonly read as "skip 2, take the 3rd", while the dialog's N = 2 means every second frame. Name the action as "one frame out of every N". Same in `framesEveryNthTitle`. | 每隔 N 帧… | 每 N 帧选一帧… |
| framesEveryNthTitle | medium | See `framesEveryNthMenu`. | 每隔 N 帧 | 每 N 帧选一帧 |
| framesShiftHint | low | 位数 normally means "number of digits"; here it is the number of positions. | 移动的位数。负数表示向前移动。 | 要移动的位置数。负数表示向前移动。 |
| framesShiftClamped | low | 原为 ("was originally") hides that the number was clamped to the limit. | 移动 {count} 位（原为 {requested}） | 移动 {count} 位（已从 {requested} 限制到此值） |
| framesNeedTwo | low | 两帧或更多 is understandable but 至少两帧 is the idiomatic UI phrasing; same for `layersNeedTwo`. | 请选择两帧或更多 | 请至少选择两帧 |
| layersNeedTwo | low | See `framesNeedTwo`. | 请选择两个或更多图层 | 请至少选择两个图层 |
| framesSetDurationSub | low | Drops "preset": the choice is among fps presets, not a free fps value. | 为所有所选帧设置同一时长或 fps | 为所有所选帧设置同一时长或 fps 预设 |
| layersSelectAdds | low | 所选 used as a bare noun (see `batchAddToSelection`). | 符合条件的图层会添加到所选 | 符合条件的图层会添加到所选项 |
| layersSelectReplaces | low | Same as `layersSelectAdds`. | 符合条件的图层会替换所选 | 符合条件的图层会替换所选项 |
| layersPickBlend | medium | Word order is unnatural (reads "blend abnormal"); the button means "blend mode other than Normal". | 混合非正常 | 非正常混合 |
| layersBiggerRows | medium | 放大行 ("enlarge row") is not natural UI Chinese for taller rows. | 放大行 | 增大行高 |
| layersSmallerRows | medium | See `layersBiggerRows`. | 缩小行 | 减小行高 |
| layersBlendTitle | low | The heading is over the blend mode list; 混合 alone reads as the verb "mix". 混合模式 is the glossary noun. | {count, plural, other{{count} 个图层的混合}} | {count, plural, other{{count} 个图层的混合模式}} |
| layersRenameHelper | low | A Chinese running list uses 、 rather than half-width commas. | {token} = 从上往下 1, 2, 3… | {token} = 从上往下 1、2、3… |
| palettesHint | low | 载入 here vs 加载 elsewhere in the editor (`clubLoadFailed` 加载到编辑器); pick one. | 点按调色板即可载入。 | 点按调色板即可加载。 |
| paletteSortBody | medium | 色阶 is the name of the Levels tool (`toolLevels`) and means "levels" to any Photoshop user; the glossary says Ramp is described in Chinese, and `acSummary` already describes it (按色相成组). | 将颜色重新排列成色阶：先灰色，再按色相，由深到浅。 | 将颜色重新排列为由深到浅的色组：先灰色，再按色相。 |
| pickSourcePrev | low | 之前 alone under a swatch is vague (before what?); the swatch is the color set before the dialog opened. 原色 / 原来 is the usual label beside a new-vs-old color pair. | 之前 | 原来 |
| patternsHint | low | 在此工具（{tool}）中使用 is clumsy; put the tool name in the sentence. | 点按图案即可在此工具（{tool}）中使用。 | 点按图案即可用于 {tool}。 |
| ditherPageHint | low | 翻转 is the Flip tool's word (`toolFlip`); here pixels switch from one color to the other, which is 切换. | …图案决定随着渐变推进哪些像素先翻转。… | …图案决定随着渐变推进哪些像素先切换。… |
| ditherFamilyNoise | medium | 噪点 is photographic grain; the signal-processing terms are 噪声 (白噪声, 蓝噪声, 梯度噪声), which is what dithering literature and image tools use. Change the whole family together. | 噪点 | 噪声 |
| ditherBlueNoise | medium | Standard term is 蓝噪声 (see `ditherFamilyNoise`). | 蓝噪点 | 蓝噪声 |
| ditherWhiteNoise | medium | Standard term is 白噪声. | 白噪点 | 白噪声 |
| ditherGradientNoise | medium | Same family term. | 梯度噪点 | 梯度噪声 |
| ditherHintIgn | medium | Same family term (interleaved gradient noise = 交错梯度噪声). | 交错梯度噪点，{count} 级 | 交错梯度噪声，{count} 级 |
| ditherHintRowsHalf | medium | 50 % 时隔行 is cryptic (隔行 alone is "interlaced"); it should say that at 50 % every other row is filled. Same for `ditherHintColsHalf`. | 50 % 时隔行 | 50 % 时每隔一行填充 |
| ditherHintColsHalf | medium | See `ditherHintRowsHalf`. | 50 % 时隔列 | 50 % 时每隔一列填充 |
| ditherHintHatch | low | Hatching in drawing is 排线; 斜线阴影 ("diagonal shadow") is a paraphrase. | 斜线阴影，{count} 级 | 排线，{count} 级 |
| memBlocked | low | 后再继续 drops "growing it": editing can continue, only growing the drawing is blocked. | 请减少帧、图层或画布尺寸后再继续。 | 减少帧、图层或画布尺寸后才能继续扩大。 |
| engineRefusedFallback | low | Same English as `engineRefused` but a different rendering; use one. | 编辑器拒绝了此更改 | 编辑器引擎拒绝了此更改 |
| cmdMirrorCycle | low | Drops the cycle order the English shows (off, H, V, both); there is room on a 290 px line. | 镜像：下一模式 | 镜像（循环：关 · 水平 · 垂直 · 双向） |
| replayOlderChip | low | 较早的录制 is a literal rendering; a chip marking a recording from an older editor version reads naturally as 旧版录制. | 较早的录制 | 旧版录制 |

## Systemic notes

1. **Overall quality is high.** Placeholders, the half-width space between Chinese and Latin
   letters or digits, full-width punctuation, the single-character ellipsis, and the glossary
   terms (帧, 图层, 画布, 主色, 混合模式, 正片叠底, 滤色, 拜耳, 半色调, 开 / 关, 回放, 延时视频,
   结尾, 画面比例, 章节, 移位, 堆叠, 所选) are applied consistently across the pack. The findings
   are mostly local wording, not structural problems.

2. **Noise terms: use 噪声, not 噪点.** The dither family (`ditherFamilyNoise`,
   `ditherBlueNoise`, `ditherWhiteNoise`, `ditherGradientNoise`, `ditherHintIgn`) uses 噪点,
   which means photographic grain. The established terms for these dither kinds are 蓝噪声,
   白噪声, and 梯度噪声. I would add "noise (dither) = 噪声" to the glossary and change all five
   together.

3. **Do not reuse a tool's name for an ordinary word.** 色阶 (the Levels tool) is used for a
   palette ramp in `paletteSortBody`, and 翻转 (the Flip tool) for pixels switching color in
   `ditherPageHint`. A reader who knows the tools will read both as the tools. The glossary
   already says Ramp is described rather than named in Chinese; `acSummary` follows that rule
   and `paletteSortBody` should too.

4. **所选 as a bare noun.** The glossary picks 所选 for frame and layer selection, which works
   as a modifier (所选帧, 所选图层). Where English uses "the selection" as a noun (`batchAddToSelection`,
   `layersSelectAdds`, `layersSelectReplaces`), 所选 is left dangling; 所选项 is the natural
   noun form. I would note this in the glossary next to the Selection rule.

5. **One English string, one rendering.** `engineRefused` and `engineRefusedFallback` have the
   same English and two different Chinese texts; `placeDroppedStorage` and
   `placeDroppedCanvas` have different English and the same Chinese, which erases the
   distinction the two warnings exist to make.

6. **Plural messages: two styles.** Some plural messages keep ICU syntax with only `other`
   (`framesSelectedCount`, `paletteColorCount`, …) and others are flattened to a plain string
   that still uses `{count}` (`editorDocInfo`, `openedFrames`, `importedFrames`,
   `exportedAnimation`, `placeMemoryFrames`, `toolsHiddenCount`). Both should generate correct
   code because the placeholders are declared in the English template, so this is not a
   defect; settling on `{count, plural, other{…}}` everywhere, as the brief describes, would
   make the file uniform and easier to check.
